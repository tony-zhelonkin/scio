#!/usr/bin/env bash
#
# Run pi on ollama/qwen3.6:35b as a recorded delegation: the same _delegations root,
# status record and depth guard as launch.sh, with the final message and a usage line
# printed at the end.

set -eu

MODEL=ollama/qwen3.6:35b
OLLAMA_NAME=qwen3.6:35b
HEARTBEAT_S=2

usage() {
    echo "usage: pi.sh --unit NAME --workdir DIR --prompt FILE [--tools LIST]" >&2
    echo "  --tools defaults to read,grep,find,ls; a refactor adds edit,write,bash" >&2
    echo "  exit 40: the model is missing from the GPU; the user loads it" >&2
}

fail() {
    code="$1"
    shift
    printf 'pi.sh: %s\n' "$*" >&2
    exit "$code"
}

unit=
workdir=
prompt=
tools=read,grep,find,ls

while [ "$#" -gt 0 ]; do
    case "$1" in
        --unit)    [ "$#" -ge 2 ] || { usage; exit 2; }; unit="$2"; shift 2 ;;
        --workdir) [ "$#" -ge 2 ] || { usage; exit 2; }; workdir="$2"; shift 2 ;;
        --prompt)  [ "$#" -ge 2 ] || { usage; exit 2; }; prompt="$2"; shift 2 ;;
        --tools)   [ "$#" -ge 2 ] || { usage; exit 2; }; tools="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)         usage; exit 2 ;;
    esac
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$script_dir/roots.sh"
refuse_nested pi.sh

[ -n "$unit" ] || { usage; exit 2; }
case "$unit" in
    .|..|*[![:alnum:]_.-]*) fail 2 "unit must contain only letters, numbers, dot, underscore, or hyphen" ;;
esac
[ -d "$workdir" ] || fail 2 "workdir is not a directory: $workdir"
[ -s "$prompt" ] || fail 2 "prompt file is missing or empty: $prompt"
workdir=$(cd "$workdir" && pwd -P)
command -v pi >/dev/null || fail 2 "pi is not on PATH"

# The weights live on the host GPU and belong to the user; a missing model stops here.
if ! curl -s --max-time 5 "${OLLAMA_HOST:-http://172.17.0.1:11434}/api/ps" \
        | grep -q "\"name\":\"$OLLAMA_NAME\""; then
    fail 40 "$OLLAMA_NAME is missing from the GPU at ${OLLAMA_HOST:-unset}. Ask the user to load it and to check the container's Ollama passthrough."
fi

run_root=$(delegations_root "$workdir")
[ -n "$run_root" ] || run_root="$scratch_root"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_dir="$run_root/$unit/$run_id"
make_run_dir "$run_root" "$run_dir"
rendered="$run_dir/prompt.md"
stream="$run_dir/stream.jsonl"
final="$run_dir/final.md"
status_file="$run_dir/status.tsv"
cp "$prompt" "$rendered"
printf '%s\n' "$workdir" > "$run_dir/workdir"
printf '%s %s\n' "$MODEL" "$tools" > "$run_dir/worker"

start_epoch=$(date -u +%s)
activity_epoch="$start_epoch"
last_bytes=0

stream_bytes() {
    if [ -f "$stream" ]; then wc -c < "$stream" | tr -d '[:space:]'; else printf '0'; fi
}

# Schema 1, the record launch.sh writes, so status.sh reads both; codex_exit carries pi's exit.
write_status() {
    local state="$1" child="$2" child_exit="$3" result_exit="$4" terminal="$5" f
    local tmp="$status_file.tmp.$$"
    {
        printf 'schema\t1\n'
        printf 'unit\t%s\n' "$unit"
        printf 'worker\tpi\n'
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
        printf 'thread\t-\n'
        for f in prompt:"$rendered" stream:"$stream" final:"$final"; do
            printf 'artifact\t%s\t%s\t%s\t0\t-\t%s\n' "${f%%:*}" \
                "$( [ -f "${f#*:}" ] && wc -c < "${f#*:}" | tr -d '[:space:]' || printf 0)" \
                "$(stat -c %Y "${f#*:}" 2>/dev/null || printf -- -)" "${f#*:}"
        done
    } > "$tmp"
    mv -f "$tmp" "$status_file"
}

printf 'RUN_DIR=%q\nSTREAM=%q\nFINAL=%q\nSTATUS=%q\n' "$run_dir" "$stream" "$final" "$status_file"
write_status starting - - - -
publish_run "$run_root" "$unit" "$run_id"

on_signal() {
    write_status interrupted - - 130 "$(date -u +%s)"
    exit 130
}
trap 'on_signal' HUP INT TERM

# stdin closed: with it open and stdout on a file, pi waits on stdin and writes nothing.
(cd "$workdir" && SCIO_DELEGATION_RUN="$unit/$run_id" exec pi -p --mode json --model "$MODEL" \
    --no-session --offline --tools "$tools" "$(cat "$rendered")") \
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

# The final message and a usage line come from the stream's assistant message_end events.
usage_line=$(python3 -I - "$stream" "$final" <<'EOF'
import json, sys
turns = calls = out = peak = 0; final = ""
for line in open(sys.argv[1]):
    try: e = json.loads(line)
    except ValueError: continue
    if e.get("type") != "message_end" or e.get("message", {}).get("role") != "assistant": continue
    m = e["message"]; u = m.get("usage") or {}
    turns += 1; out += u.get("output", 0); peak = max(peak, u.get("input", 0))
    calls += sum(c.get("type") == "toolCall" for c in m.get("content", []))
    final = "\n".join(c["text"] for c in m.get("content", []) if c.get("type") == "text") or final
open(sys.argv[2], "w").write(final)
print(f"USAGE\tturns={turns}\ttool_calls={calls}\tpeak_context={peak}\toutput_tokens={out}")
EOF
) || usage_line="USAGE	unreadable stream"

result_status="$child_status"
[ "$result_status" -ne 0 ] || [ -s "$final" ] || result_status=30
state=succeeded
[ "$result_status" -eq 0 ] || state=failed
write_status "$state" "$child_pid" "$child_status" "$result_status" "$(date -u +%s)"

printf '%s\n' "$usage_line"
if [ -s "$final" ]; then
    printf -- '--- FINAL MESSAGE ---\n'
    cat "$final"
    printf '\n'
fi
exit "$result_status"
