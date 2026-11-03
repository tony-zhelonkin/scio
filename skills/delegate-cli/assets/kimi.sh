#!/usr/bin/env bash
#
# Run kimi headlessly as a recorded delegation: the same _delegations root, status record
# and depth guard as launch.sh and agy.sh, with the answer and a usage line printed at the end.
# A consult runs in an empty scratch workdir, a research run adds web search, and a workspace
# run names its directory. Prompt mode permits edits; it cannot combine with --auto.

set -eu

DEFAULT_MODEL=kimi-code/k3.1-pro
DEFAULT_EFFORT=low
HEARTBEAT_S=2
NO_TOOLS_LINE='Answer from knowledge alone: no tool use, no file reads, no web search.'
RESEARCH_LINE='Use web search. Cite the URL of every source you relied on.'

usage() {
    echo "usage: kimi.sh --unit NAME --prompt FILE [--mode consult|research|workspace] [--workdir DIR] [--model MODEL] [--effort low|high|max] [--timeout DURATION]" >&2
    echo "  consult (default): empty scratch workdir, the prompt opens with the no-tools line" >&2
    echo "  research: empty scratch workdir, the prompt opens with the web-search line" >&2
    echo "  workspace: runs in --workdir, which is required; kimi reads the directory" >&2
    echo "  --model takes a model alias; default $DEFAULT_MODEL" >&2
    echo "  --effort rides KIMI_MODEL_THINKING_EFFORT; default $DEFAULT_EFFORT" >&2
    echo "  --timeout takes a duration accepted by timeout(1); default 10m consult, 25m otherwise" >&2
    echo "  --resume continues this unit's recorded kimi session" >&2
    echo "  exit 30: kimi returned no answer; exit 34: nested delegation; exit 36: quota or auth error" >&2
}

fail() {
    code="$1"
    shift
    printf 'kimi.sh: %s\n' "$*" >&2
    exit "$code"
}

unit=
workdir=
prompt=
mode=consult
model="$DEFAULT_MODEL"
effort="$DEFAULT_EFFORT"
timeout_d=
resume=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --unit)    [ "$#" -ge 2 ] || { usage; exit 2; }; unit="$2"; shift 2 ;;
        --workdir) [ "$#" -ge 2 ] || { usage; exit 2; }; workdir="$2"; shift 2 ;;
        --prompt)  [ "$#" -ge 2 ] || { usage; exit 2; }; prompt="$2"; shift 2 ;;
        --mode)    [ "$#" -ge 2 ] || { usage; exit 2; }; mode="$2"; shift 2 ;;
        --model)   [ "$#" -ge 2 ] || { usage; exit 2; }; model="$2"; shift 2 ;;
        --effort)  [ "$#" -ge 2 ] || { usage; exit 2; }; effort="$2"; shift 2 ;;
        --timeout) [ "$#" -ge 2 ] || { usage; exit 2; }; timeout_d="$2"; shift 2 ;;
        --resume)  resume=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *)         usage; exit 2 ;;
    esac
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$script_dir/roots.sh"
refuse_nested kimi.sh

[ -n "$unit" ] || { usage; exit 2; }
case "$unit" in
    .|..|*[![:alnum:]_.-]*) fail 2 "unit must contain only letters, numbers, dot, underscore, or hyphen" ;;
esac
[ -s "$prompt" ] || fail 2 "prompt file is missing or empty: $prompt"
case "$effort" in
    low|high|max) ;;
    *) fail 2 "effort is low, high or max: $effort" ;;
esac
case "$mode" in
    consult|research) [ -z "$timeout_d" ] && timeout_d=$([ "$mode" = consult ] && echo 10m || echo 25m) ;;
    workspace) [ -n "$workdir" ] || { [ "$resume" -eq 1 ] && [ -z "$workdir" ]; } || fail 2 "--mode workspace needs --workdir"; [ -n "$timeout_d" ] || timeout_d=25m ;;
    *) fail 2 "mode is consult, research or workspace: $mode" ;;
esac
if command -v kimi >/dev/null; then
    kimi_bin=$(command -v kimi)
elif [ -x /home/devuser/.kimi-code/bin/kimi ]; then
    kimi_bin=/home/devuser/.kimi-code/bin/kimi
else
    fail 2 "kimi is not on PATH and /home/devuser/.kimi-code/bin/kimi is not executable"
fi

record_dir="${workdir:-$PWD}"
[ -d "$record_dir" ] || fail 2 "workdir is not a directory: $record_dir"
record_dir=$(cd "$record_dir" && pwd -P)
run_root=$(delegations_root "$record_dir")
[ -n "$run_root" ] || run_root="$scratch_root"

source_thread=
if [ "$resume" -eq 1 ]; then
    for source_dir in "$run_root/$unit/current" "$scratch_root/$unit/current"; do
        if [ -z "$source_thread" ] && [ -s "$source_dir/thread" ]; then
            source_thread=$(cat "$source_dir/thread")
        fi
        if [ -z "$workdir" ] && [ -s "$source_dir/workdir" ]; then
            workdir=$(cat "$source_dir/workdir")
        fi
    done
    [ -n "$source_thread" ] || fail 2 "unit $unit has no recorded kimi session to resume"
    if [ "$mode" = workspace ]; then
        [ -d "$workdir" ] || fail 2 "resumed workdir is not a directory: $workdir"
        record_dir=$(cd "$workdir" && pwd -P)
    fi
fi

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_dir="$run_root/$unit/$run_id"
make_run_dir "$run_root" "$run_dir"
rendered="$run_dir/prompt.md"
stream="$run_dir/stream.jsonl"
final="$run_dir/final.md"
status_file="$run_dir/status.tsv"

case "$mode" in
    consult)   { printf '%s\n\n' "$NO_TOOLS_LINE"; cat "$prompt"; } > "$rendered"; kimi_cwd="$scratch_root/kimi/$unit/$run_id" ;;
    research)  { printf '%s\n\n' "$RESEARCH_LINE"; cat "$prompt"; } > "$rendered"; kimi_cwd="$scratch_root/kimi/$unit/$run_id" ;;
    workspace) cp "$prompt" "$rendered"; kimi_cwd="$record_dir" ;;
esac
mkdir -p "$kimi_cwd"
printf '%s\n' "$kimi_cwd" > "$run_dir/workdir"
printf '%s %s %s\n' "$model" "$effort" "$mode" > "$run_dir/worker"
[ "$resume" -eq 0 ] || printf '%s\n' "$source_thread" > "$run_dir/thread"

start_epoch=$(date -u +%s)
activity_epoch="$start_epoch"
last_bytes=0

stream_bytes() {
    if [ -f "$stream" ]; then wc -c < "$stream" | tr -d '[:space:]'; else printf '0'; fi
}

# Schema 1, the record launch.sh writes, so status.sh reads all workers; codex_exit carries kimi's exit.
write_status() {
    local state="$1" child="$2" child_exit="$3" result_exit="$4" terminal="$5" f
    local tmp="$status_file.tmp.$$"
    {
        printf 'schema\t1\n'
        printf 'unit\t%s\n' "$unit"
        printf 'worker\tkimi\n'
        printf 'run_id\t%s\n' "$run_id"
        printf 'state\t%s\n' "$state"
        printf 'launcher_pid\t%s\n' "$$"
        printf 'child_pid\t%s\n' "$child"
        printf 'start_epoch\t%s\n' "$start_epoch"
        printf 'sample_epoch\t%s\n' "$(date -u +%s)"
        printf 'last_activity_epoch\t%s\n' "$activity_epoch"
        printf 'terminal_epoch\t%s\n' "$terminal"
        printf 'codex_exit\t%s\n' "$child_exit"
        printf 'result_exit\t%s\n' "$result_exit"
        printf 'origin\t%s\n' "$([ "$resume" -eq 1 ] && printf resume || printf fresh)"
        printf 'thread\t%s\n' "${conversation_id:-${source_thread:--}}"
        for f in prompt:"$rendered" stream:"$stream" final:"$final"; do
            printf 'artifact\t%s\t%s\t%s\t0\t-\t%s\n' "${f%%:*}" \
                "$( [ -f "${f#*:}" ] && wc -c < "${f#*:}" | tr -d '[:space:]' || printf 0)" \
                "$(stat -c %Y "${f#*:}" 2>/dev/null || printf -- -)" "${f#*:}"
        done
    } > "$tmp"
    mv -f "$tmp" "$status_file"
}

conversation_id=
printf 'RUN_DIR=%q\nSTREAM=%q\nFINAL=%q\nSTATUS=%q\n' "$run_dir" "$stream" "$final" "$status_file"
write_status starting - - - -
publish_run "$run_root" "$unit" "$run_id"

on_signal() {
    write_status interrupted - - 130 "$(date -u +%s)"
    exit 130
}
trap 'on_signal' HUP INT TERM

# The prompt rides -p as its value; stream-json gives one role-tagged object per line.
kimi_args=(-p "$(cat "$rendered")" -m "$model" --output-format stream-json)
[ "$resume" -eq 0 ] || kimi_args+=(-r "$source_thread")
(cd "$kimi_cwd" && SCIO_DELEGATION_RUN="$unit/$run_id" KIMI_MODEL_THINKING_EFFORT="$effort" \
    exec timeout "$timeout_d" "$kimi_bin" "${kimi_args[@]}") \
    < /dev/null > "$stream" 2> "$run_dir/stderr.log" &
child_pid=$!
write_status running "$child_pid" - - -

while kill -0 "$child_pid" 2>/dev/null; do
    sleep "$HEARTBEAT_S"
    now_bytes=$(stream_bytes)
    if [ "$now_bytes" != "$last_bytes" ]; then
        last_bytes="$now_bytes"
        activity_epoch=$(date -u +%s)
    fi
    write_status running "$child_pid" - - -
done

set +e
wait "$child_pid"
child_status=$?
set -e

# The answer is the last assistant message; the final meta record carries the resumable session id.
usage_line=$(python3 -I - "$stream" "$final" <<'EOF'
import json, sys
assistants = tools = metas = 0; final = ""; conv = "-"
for line in open(sys.argv[1]):
    try: e = json.loads(line)
    except ValueError: continue
    role = e.get("role")
    if role == "assistant":
        assistants += 1; final = e.get("content", "")
    elif role == "tool":
        tools += 1
    elif role == "meta":
        metas += 1
        hint = e.get("session.resume_hint") or e
        conv = hint.get("session_id") or conv
open(sys.argv[2], "w").write(final)
print(f"USAGE\tmessages={assistants}\tmeta={metas}\ttool_calls={tools}")
print(conv)
EOF
) || usage_line="USAGE	unreadable stream
-"
conversation_id=$(printf '%s\n' "$usage_line" | sed -n '2p')
[ "$conversation_id" != - ] || conversation_id="$source_thread"
usage_line=$(printf '%s\n' "$usage_line" | sed -n '1p')
[ -z "$conversation_id" ] || printf '%s\n' "$conversation_id" > "$run_dir/thread"

result_status="$child_status"
if [ "$child_status" -ne 0 ] && LC_ALL=C grep -Eqi 'quota|rate limit|resource.exhausted|429|unauthori[sz]ed|authentication|invalid.*(api.?key|token)|401|403' "$run_dir/stderr.log" 2>/dev/null; then
    result_status=36
    printf 'kimi.sh: quota or authentication error; inspect %s/stderr.log.\n' "$run_dir" >&2
fi
[ "$result_status" -ne 0 ] || [ -s "$final" ] || result_status=30
state=succeeded
[ "$result_status" -eq 0 ] || state=failed
write_status "$state" "$child_pid" "$child_status" "$result_status" "$(date -u +%s)"

printf 'THREAD=%s\n%s\n' "${conversation_id:--}" "$usage_line"
if [ -s "$final" ]; then
    printf -- '--- FINAL MESSAGE ---\n'
    cat "$final"
    printf '\n'
fi
exit "$result_status"
