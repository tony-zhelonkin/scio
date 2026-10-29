#!/usr/bin/env bash
#
# Run agy headlessly as a recorded delegation: the same _delegations root, status record
# and depth guard as launch.sh and pi.sh, with the answer and a usage line printed at the end.
# A consult runs in an empty scratch workdir, so the repository's structure stays out of
# the model's context; a research run adds web search; a workspace run names its directory.

set -eu

DEFAULT_MODEL=gemini-3.8-flash-medium
HEARTBEAT_S=2
NO_TOOLS_LINE='Answer from knowledge alone: no tool use, no file reads, no web search.'
RESEARCH_LINE='Use web search. Cite the URL of every source you relied on.'

usage() {
    echo "usage: agy.sh --unit NAME --prompt FILE [--mode consult|research|workspace] [--workdir DIR] [--model MODEL] [--timeout DURATION]" >&2
    echo "  consult (default): empty scratch workdir, the prompt opens with the no-tools line" >&2
    echo "  research: empty scratch workdir, the prompt opens with the web-search line" >&2
    echo "  workspace: runs in --workdir, which is required; agy reads the directory" >&2
    echo "  --model takes a slug from 'agy models'; default $DEFAULT_MODEL" >&2
    echo "  --timeout is a Go duration for --print-timeout; default 10m consult, 25m otherwise" >&2
    echo "  exit 30: agy returned no answer; exit 34: nested delegation" >&2
}

fail() {
    code="$1"
    shift
    printf 'agy.sh: %s\n' "$*" >&2
    exit "$code"
}

unit=
workdir=
prompt=
mode=consult
model="$DEFAULT_MODEL"
timeout_d=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --unit)    [ "$#" -ge 2 ] || { usage; exit 2; }; unit="$2"; shift 2 ;;
        --workdir) [ "$#" -ge 2 ] || { usage; exit 2; }; workdir="$2"; shift 2 ;;
        --prompt)  [ "$#" -ge 2 ] || { usage; exit 2; }; prompt="$2"; shift 2 ;;
        --mode)    [ "$#" -ge 2 ] || { usage; exit 2; }; mode="$2"; shift 2 ;;
        --model)   [ "$#" -ge 2 ] || { usage; exit 2; }; model="$2"; shift 2 ;;
        --timeout) [ "$#" -ge 2 ] || { usage; exit 2; }; timeout_d="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)         usage; exit 2 ;;
    esac
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$script_dir/roots.sh"
refuse_nested agy.sh

[ -n "$unit" ] || { usage; exit 2; }
case "$unit" in
    .|..|*[![:alnum:]_.-]*) fail 2 "unit must contain only letters, numbers, dot, underscore, or hyphen" ;;
esac
[ -s "$prompt" ] || fail 2 "prompt file is missing or empty: $prompt"
case "$mode" in
    consult|research) [ -z "$timeout_d" ] && timeout_d=$([ "$mode" = consult ] && echo 10m || echo 25m) ;;
    workspace) [ -n "$workdir" ] || fail 2 "--mode workspace needs --workdir"; [ -n "$timeout_d" ] || timeout_d=25m ;;
    *) fail 2 "mode is consult, research or workspace: $mode" ;;
esac
command -v agy >/dev/null || fail 2 "agy is not on PATH"

# The run records under the repository the caller stands in. A consult or research run
# works in an empty directory under scratch, outside every repository, so agy loads no
# workspace context: measured 7.7k input tokens there against 24k anywhere inside a tree.
record_dir="${workdir:-$PWD}"
[ -d "$record_dir" ] || fail 2 "workdir is not a directory: $record_dir"
record_dir=$(cd "$record_dir" && pwd -P)
run_root=$(delegations_root "$record_dir")
[ -n "$run_root" ] || run_root="$scratch_root"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_dir="$run_root/$unit/$run_id"
make_run_dir "$run_root" "$run_dir"
rendered="$run_dir/prompt.md"
stream="$run_dir/stream.jsonl"
final="$run_dir/final.md"
status_file="$run_dir/status.tsv"

case "$mode" in
    consult)   { printf '%s\n\n' "$NO_TOOLS_LINE"; cat "$prompt"; } > "$rendered"; agy_cwd="$scratch_root/agy/$unit/$run_id" ;;
    research)  { printf '%s\n\n' "$RESEARCH_LINE"; cat "$prompt"; } > "$rendered"; agy_cwd="$scratch_root/agy/$unit/$run_id" ;;
    workspace) cp "$prompt" "$rendered"; agy_cwd="$record_dir" ;;
esac
mkdir -p "$agy_cwd"
printf '%s\n' "$agy_cwd" > "$run_dir/workdir"
printf '%s %s\n' "$model" "$mode" > "$run_dir/worker"

start_epoch=$(date -u +%s)
activity_epoch="$start_epoch"
last_bytes=0

stream_bytes() {
    if [ -f "$stream" ]; then wc -c < "$stream" | tr -d '[:space:]'; else printf '0'; fi
}

# Schema 1, the record launch.sh writes, so status.sh reads all three; codex_exit carries agy's exit.
write_status() {
    local state="$1" child="$2" child_exit="$3" result_exit="$4" terminal="$5" f
    local tmp="$status_file.tmp.$$"
    {
        printf 'schema\t1\n'
        printf 'unit\t%s\n' "$unit"
        printf 'worker\tagy\n'
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
        printf 'origin\tfresh\n'
        printf 'thread\t%s\n' "${conversation_id:--}"
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

# The prompt rides -p as its value and every flag follows it; stream-json gives one event per line.
(cd "$agy_cwd" && SCIO_DELEGATION_RUN="$unit/$run_id" exec agy -p "$(cat "$rendered")" \
    --model "$model" --output-format stream-json --print-timeout "$timeout_d") \
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

# The answer and the usage line come from the result event; tool steps are counted by name.
usage_line=$(python3 -I - "$stream" "$final" <<'EOF'
import json, sys, collections
tools = collections.Counter(); final = ""; usage = {}; conv = "-"; model = "?"; status = "-"
for line in open(sys.argv[1]):
    try: e = json.loads(line)
    except ValueError: continue
    ev = e.get("event")
    if ev == "init":
        conv = e.get("conversation_id", "-"); model = (e.get("init") or {}).get("model", "?")
    elif ev == "step_update":
        s = e.get("step_update") or {}
        if s.get("step_type") == "tool" and s.get("state") == "ACTIVE": tools[s.get("tool_name", "?")] += 1
    elif ev == "result":
        r = e.get("result") or {}
        final = r.get("response", ""); usage = r.get("usage") or {}; status = r.get("status", "-")
open(sys.argv[2], "w").write(final)
calls = " ".join(f"{k}={v}" for k, v in sorted(tools.items())) or "none"
print(f"USAGE\tmodel={model}\tstatus={status}\tinput_tokens={usage.get('input_tokens', 0)}\tcached={usage.get('cache_read_tokens', 0)}\toutput_tokens={usage.get('output_tokens', 0)}\ttool_calls={calls}")
print(conv)
EOF
) || usage_line="USAGE	unreadable stream
-"
conversation_id=$(printf '%s\n' "$usage_line" | sed -n '2p')
usage_line=$(printf '%s\n' "$usage_line" | sed -n '1p')

result_status="$child_status"
[ "$result_status" -ne 0 ] || [ -s "$final" ] || result_status=30
state=succeeded
[ "$result_status" -eq 0 ] || state=failed
write_status "$state" "$child_pid" "$child_status" "$result_status" "$(date -u +%s)"

printf 'THREAD=%s\n%s\n' "$conversation_id" "$usage_line"
if [ -s "$final" ]; then
    printf -- '--- FINAL MESSAGE ---\n'
    cat "$final"
    printf '\n'
fi
exit "$result_status"
