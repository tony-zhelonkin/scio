#!/usr/bin/env bash
# Verify pi's read-only mapping contract and readiness failures without a live model.
set -u
. "$(dirname "$0")/_lib.sh"
setup_tmpdir
ASSETS="$TOOLKIT_ROOT/skills/delegate-cli/assets"
mkdir -p "$TMPDIR_TEST/bin" "$TMPDIR_TEST/repo"
git init -q "$TMPDIR_TEST/repo"
printf 'Map the relevant code.\n' > "$TMPDIR_TEST/prompt.md"
cat > "$TMPDIR_TEST/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CURL_ARGS"
case "$READY_CASE" in
    spaced) printf '{ "models": [ { "name": "qwen3.6:35b" } ] }\n' ;;
    model) printf '{"models":[{"model":"qwen3.6:35b"}]}\n' ;;
    absent) printf '{"models":[{"name":"qwen3.6:35b-other"}]}\n' ;;
    broken) printf 'not-json\n' ;;
    shape) printf '{"models":{}}\n' ;;
    down) exit 7 ;;
esac
STUB
cat > "$TMPDIR_TEST/bin/pi" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$PI_ARGS"
[ "${EMPTY_RESULT:-0}" = 1 ] && exit 0
printf '{"type":"message_end","message":{"role":"assistant","usage":{"input":40,"output":8},"content":[{"type":"text","text":"mapped fixture"}]}}\n'
STUB
chmod +x "$TMPDIR_TEST/bin/pi" "$TMPDIR_TEST/bin/curl"
export PATH="$TMPDIR_TEST/bin:$PATH" OLLAMA_HOST=http://mapping-fixture:11434
export PI_ARGS="$TMPDIR_TEST/pi.args" CURL_ARGS="$TMPDIR_TEST/curl.args"
export SCIO_DELEGATIONS="$TMPDIR_TEST/runs" READY_CASE=spaced
unset SCIO_DELEGATION_RUN
launch() { "$ASSETS/pi.sh" --unit "$1" --workdir "$TMPDIR_TEST/repo" --prompt "$TMPDIR_TEST/prompt.md" "${@:2}" > "$TMPDIR_TEST/output" 2>&1; }
launch readonly
assert_eq "$?" 0 'spaced JSON is a ready model'
assert_grep '^ollama/qwen3.6:35b$' "$PI_ARGS" 'model is explicitly pinned'
assert_grep '^read,grep,find,ls,locate,lines$' "$PI_ARGS" 'mapping has read-only tools and the exact-line tools by default'
assert_grep '/assets/pi_lines.ts$' "$PI_ARGS" 'loads the exact-line extension'
assert_grep 'cite a line only as it appears' "$PI_ARGS" 'prompt carries the line citation rule'
assert_grep '^--no-session$' "$PI_ARGS" 'pi keeps no harness session'
assert_grep '^--offline$' "$PI_ARGS" 'startup is offline'
assert_grep '^http://mapping-fixture:11434/api/ps$' "$CURL_ARGS" 'uses configured read-only readiness endpoint'
assert_eq "$(cat "$SCIO_DELEGATIONS/readonly/current/final.md")" 'mapped fixture' 'records map'
READY_CASE=model launch alternate
assert_eq "$?" 0 'model field is accepted'
launch editing --tools read,edit,write,bash,grep,find,ls
assert_eq "$?" 0 'explicit editing tool list works'
assert_grep '^read,edit,write,bash,grep,find,ls,locate,lines$' "$PI_ARGS" 'passes explicit tools with the exact-line tools'
for scenario in absent broken shape down; do
    : > "$PI_ARGS"
    READY_CASE=$scenario launch "$scenario"
    rc=$?
    expected=41
    [ "$scenario" != absent ] || expected=40
    assert_eq "$rc" "$expected" "$scenario exit code"
    assert_eq "$(cat "$PI_ARGS")" '' "$scenario never launches pi"
    [ ! -e "$SCIO_DELEGATIONS/$scenario" ] || { echo 'FAIL: failed preflight published a run'; exit 1; }
done
EMPTY_RESULT=1 launch empty
assert_eq "$?" 30 'empty answer fails'
assert_grep '^state.failed$' "$SCIO_DELEGATIONS/empty/current/status.tsv" 'empty answer is recorded as failed'
SCIO_DELEGATION_RUN=outer/1 launch nested
assert_eq "$?" 34 'worker cannot delegate again'
echo "PASS [$_TEST_NAME]"
