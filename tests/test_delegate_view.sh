#!/usr/bin/env bash
# tests/test_delegate_view.sh — view.sh renders a codex text stream and a pi JSON
# stream to the same human layout: the worker's voice, one line per command with its
# outcome, folded output with its test summary kept, and a footer.
#
# Tests:
#   1. codex: header names model, effort and the brief's title
#   2. codex: the worker's messages carry the voice bar
#   3. codex: a command is one line with ✓ or ✗ and a duration
#   4. codex: long output folds, and a pytest summary inside the fold survives
#   5. codex: a result arriving after later sections is shown as a late command
#   6. codex: the token footer closes the run and the final message prints once
#   7. codex: --full prints the output unfolded
#   8. pi: the brief's title, the voice, a tool call with its outcome and the usage footer
#   9. a unit name resolves to the stream under _delegations
set -u
. "$(dirname "$0")/_lib.sh"

setup_tmpdir
VIEW="$TOOLKIT_ROOT/skills/delegate-cli/assets/view.sh"
export NO_COLOR=1

CODEX="$TMPDIR_TEST/stream.log"
{
    printf 'OpenAI Codex v0.163.0\n--------\nworkdir: /w\nmodel: gpt-6.1-sol\nprovider: openai\napproval: never\n'
    printf 'reasoning effort: medium\nreasoning summaries: none\nsession id: abc-123\n--------\nuser\n'
    printf 'You are a worker.\n\n# S00: the pillars\n\nDo it.\n\ncodex\nI will read the audit first.\n\n'
    printf 'exec\n/bin/bash -lc '"'"'cat big.txt'"'"' in /w\n succeeded in 12ms:\n'
    for i in $(seq 1 40); do printf 'line %s\n' "$i"; done
    printf '350 passed, 12 deselected in 15.9s\ntrailer a\ntrailer b\ntrailer c\n\n'
    printf 'exec\n/bin/bash -lc '"'"'false'"'"' in /w\n exited 1 in 3ms:\nboom\n\n'
    printf 'exec\n/bin/bash -lc '"'"'pytest -q'"'"' in /w\n\ncodex\nStill waiting on the suite.\n\n'
    printf ' succeeded in 401147ms:\n2700 passed in 350s\n\n'
    printf 'codex\nDone: 2700 passed.\ntokens used\n142,039\nDone: 2700 passed.\n'
} > "$CODEX"

"$VIEW" "$CODEX" > "$TMPDIR_TEST/codex.out" 2>&1 || {
    echo "FAIL [$_TEST_NAME] view.sh failed on the codex stream" >&2
    cat "$TMPDIR_TEST/codex.out" >&2
    exit 1
}
out="$TMPDIR_TEST/codex.out"

assert_grep '^■ gpt-6.1-sol · medium  S00: the pillars$' "$out" "case1: the header names model, effort and title"
assert_grep '^▌ I will read the audit first.$' "$out" "case2: the voice bar marks the worker's message"
assert_grep '^  \$ cat big.txt  ✓ 12ms$' "$out" "case3: a command is one line with its outcome"
assert_grep '^  \$ false  ✗ exited 1 3ms$' "$out" "case3: a failure shows its exit"
assert_grep '… 39 lines$' "$out" "case4: long output folds"
assert_grep '^    350 passed, 12 deselected in 15.9s$' "$out" "case4: the test summary survives the fold"
assert_eq "$(grep -c '^    line 2[0-9]$' "$out")" "0" "case4: the middle of the output is folded away"
assert_grep '^  \$ pytest -q  … running$' "$out" "case5: a command still running when the stream moved on"
assert_grep '^  ↳ pytest -q  ✓ 6m41s$' "$out" "case5: the late result names its command"
assert_grep '^■ tokens used 142,039$' "$out" "case6: the token footer closes the run"
assert_eq "$(grep -c '^▌ Done: 2700 passed.$' "$out")" "1" "case6: the final message prints once"

"$VIEW" --full "$CODEX" > "$TMPDIR_TEST/full.out" 2>&1
assert_eq "$(grep -c '^    line 2[0-9]$' "$TMPDIR_TEST/full.out")" "10" "case7: --full prints the output unfolded"

PI="$TMPDIR_TEST/stream.jsonl"
{
    printf '{"type":"agent_start"}\n'
    printf '{"type":"message_end","message":{"role":"user","content":[{"type":"text","text":"You are a worker.\\n\\n# Count the entries\\n\\nUse ls."}]}}\n'
    printf '{"type":"message_end","message":{"role":"assistant","model":"qwen3.6:35b","usage":{"input":800,"output":30},"content":[{"type":"thinking","thinking":"List first."},{"type":"toolCall","id":"c1","name":"bash","arguments":{"command":"ls -1 | wc -l"}}]}}\n'
    printf '{"type":"tool_execution_end","toolCallId":"c1","toolName":"bash","result":{"content":[{"type":"text","text":"3"}]},"isError":false,"durationMs":4}\n'
    printf '{"type":"message_end","message":{"role":"assistant","model":"qwen3.6:35b","usage":{"input":900,"output":10},"content":[{"type":"text","text":"3 entries."}]}}\n'
    printf '{"type":"agent_end"}\n'
} > "$PI"

"$VIEW" "$PI" > "$TMPDIR_TEST/pi.out" 2>&1 || {
    echo "FAIL [$_TEST_NAME] view.sh failed on the pi stream" >&2
    cat "$TMPDIR_TEST/pi.out" >&2
    exit 1
}
out="$TMPDIR_TEST/pi.out"
assert_grep '^■ pi  Count the entries$' "$out" "case8: the header names the brief's title"
assert_grep '^  model qwen3.6:35b$' "$out" "case8: the model is named"
assert_grep '^  \$ bash ls -1 | wc -l  ✓ 4ms$' "$out" "case8: a tool call is one line with its outcome"
assert_grep '^    3$' "$out" "case8: the tool result is shown"
assert_grep '^▌ 3 entries.$' "$out" "case8: the voice bar marks the worker's message"
assert_grep '^■ turns 2 · tool calls 1 · peak context 900 · output tokens 40$' "$out" "case8: the usage footer"

REPO="$TMPDIR_TEST/repo"
git init -q "$REPO"
mkdir -p "$REPO/_delegations/u_view/run1"
cp "$PI" "$REPO/_delegations/u_view/run1/stream.jsonl"
ln -s run1 "$REPO/_delegations/u_view/current"
( cd "$REPO" && "$VIEW" u_view ) > "$TMPDIR_TEST/unit.out" 2>&1 || {
    echo "FAIL [$_TEST_NAME] case9: view.sh failed to resolve the unit" >&2
    cat "$TMPDIR_TEST/unit.out" >&2
    exit 1
}
assert_grep '^▌ 3 entries.$' "$TMPDIR_TEST/unit.out" "case9: a unit name resolves to its current stream"

echo "PASS [$_TEST_NAME]"
