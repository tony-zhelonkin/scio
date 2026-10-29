#!/usr/bin/env bash
# tests/test_delegate_agy.sh — agy.sh records a run like launch.sh and pi.sh: same root,
# same status schema, depth guard, and a workspace outside every repository for a consult.
#
# agy is stubbed; the stub writes stream-json and proves where it ran and what it received.
#
# Tests:
#   1. a consult prepends the no-tools line and runs in an empty scratch directory outside the repo
#   2. the run lands in <repo>/_delegations with worker=agy, the answer in final.md, THREAD and USAGE printed
#   3. research prepends the web-search line and USAGE counts tool steps by name
#   4. workspace mode runs in --workdir and leaves the prompt as written
#   5. agy.sh refuses to start inside a delegation (exit 34)
#   6. an empty answer fails the run with exit 30
#   7. view.sh renders an agy stream: title, tool line, answer bar and footer
set -u
. "$(dirname "$0")/_lib.sh"

setup_tmpdir
ASSETS="$TOOLKIT_ROOT/skills/delegate-cli/assets"
export NO_COLOR=1

mkdir -p "$TMPDIR_TEST/bin" "$TMPDIR_TEST/tmp"
cat > "$TMPDIR_TEST/bin/agy" <<'STUB'
#!/usr/bin/env bash
prompt="$2"
printf '{"event":"init","conversation_id":"conv-1","init":{"model":"%s","cwd":"%s"}}\n' "${4:-?}" "$PWD"
printf '%s\n' "$prompt" > "$PWD/.prompt_seen"
if printf '%s' "$prompt" | grep -q 'Use web search'; then
  printf '{"event":"step_update","step_update":{"step_index":2,"state":"ACTIVE","step_type":"tool","tool_name":"search_web","tool_info":{"parameters":{"query":"q1"}}}}\n'
  printf '{"event":"step_update","step_update":{"step_index":2,"state":"DONE","step_type":"tool","tool_name":"search_web","duration_seconds":1.5}}\n'
  printf '{"event":"step_update","step_update":{"step_index":4,"state":"ACTIVE","step_type":"tool","tool_name":"search_web","tool_info":{"parameters":{"query":"q2"}}}}\n'
  printf '{"event":"step_update","step_update":{"step_index":4,"state":"DONE","step_type":"tool","tool_name":"search_web","duration_seconds":0.5}}\n'
fi
if printf '%s' "$prompt" | grep -q 'EMPTY'; then
  printf '{"event":"result","result":{"status":"SUCCESS","response":"","usage":{}}}\n'
else
  printf '{"event":"step_update","step_update":{"step_index":5,"state":"DONE","step_type":"agent_response","text_delta":"stub agy answer run=%s"}}\n' "${SCIO_DELEGATION_RUN:-unset}"
  printf '{"event":"result","result":{"status":"SUCCESS","response":"stub agy answer run=%s","duration_seconds":2,"usage":{"input_tokens":7700,"output_tokens":40,"cache_read_tokens":0}}}\n' "${SCIO_DELEGATION_RUN:-unset}"
fi
STUB
chmod +x "$TMPDIR_TEST/bin/agy"
export TMPDIR="$TMPDIR_TEST/tmp" PATH="$TMPDIR_TEST/bin:$PATH"

REPO="$TMPDIR_TEST/repo"
git init -q "$REPO"
printf '# Count the things\n\nHow many?\n' > "$TMPDIR_TEST/prompt.md"

# --- 1 and 2. consult ---------------------------------------------------------
(cd "$REPO" && "$ASSETS/agy.sh" --unit u_consult --prompt "$TMPDIR_TEST/prompt.md" --model m-stub) > "$TMPDIR_TEST/consult.out" 2>&1 \
    || { echo "FAIL [$_TEST_NAME] case1: agy.sh failed:"; cat "$TMPDIR_TEST/consult.out"; exit 1; } >&2
run="$REPO/_delegations/u_consult/current"
cwd=$(cat "$run/workdir")
case "$cwd" in
    "$TMPDIR_TEST/tmp/scio-delegate/agy/u_consult/"*) ;;
    *) echo "FAIL [$_TEST_NAME] case1: consult should run under scratch, ran in $cwd" >&2; exit 1 ;;
esac
assert_grep '^Answer from knowledge alone' "$cwd/.prompt_seen" "case1: the consult prompt opens with the no-tools line"
assert_grep '^# Count the things' "$cwd/.prompt_seen" "case1: the brief follows the no-tools line"
assert_grep '^worker	agy$' "$run/status.tsv" "case2: status names the worker"
assert_grep '^state	succeeded$' "$run/status.tsv" "case2: the run succeeded"
assert_grep '^thread	conv-1$' "$run/status.tsv" "case2: status carries the conversation id"
assert_grep '^stub agy answer run=u_consult/' "$run/final.md" "case2: final.md holds the answer and the worker saw SCIO_DELEGATION_RUN"
assert_grep '^THREAD=conv-1$' "$TMPDIR_TEST/consult.out" "case2: THREAD printed"
assert_grep '^USAGE	model=m-stub	status=SUCCESS	input_tokens=7700	cached=0	output_tokens=40	tool_calls=none$' "$TMPDIR_TEST/consult.out" "case2: USAGE line"
assert_grep '^--- FINAL MESSAGE ---$' "$TMPDIR_TEST/consult.out" "case2: final message marker"

# --- 3. research --------------------------------------------------------------
(cd "$REPO" && "$ASSETS/agy.sh" --unit u_research --mode research --prompt "$TMPDIR_TEST/prompt.md") > "$TMPDIR_TEST/research.out" 2>&1 \
    || { echo "FAIL [$_TEST_NAME] case3: agy.sh research failed"; cat "$TMPDIR_TEST/research.out"; exit 1; } >&2
assert_grep '^Use web search' "$(cat "$REPO/_delegations/u_research/current/workdir")/.prompt_seen" "case3: research prompt opens with the web-search line"
assert_grep 'tool_calls=search_web=2$' "$TMPDIR_TEST/research.out" "case3: USAGE counts tool steps by name"

# --- 4. workspace -------------------------------------------------------------
mkdir -p "$REPO/sub"
(cd "$REPO" && "$ASSETS/agy.sh" --unit u_ws --mode workspace --workdir "$REPO/sub" --prompt "$TMPDIR_TEST/prompt.md") > "$TMPDIR_TEST/ws.out" 2>&1 \
    || { echo "FAIL [$_TEST_NAME] case4: agy.sh workspace failed"; cat "$TMPDIR_TEST/ws.out"; exit 1; } >&2
assert_eq "$(cat "$REPO/_delegations/u_ws/current/workdir")" "$REPO/sub" "case4: workspace mode runs in --workdir"
assert_eq "$(head -1 "$REPO/sub/.prompt_seen")" "# Count the things" "case4: the prompt is sent as written"

# --- 5. nested ----------------------------------------------------------------
SCIO_DELEGATION_RUN=outer/1 "$ASSETS/agy.sh" --unit u_nested --prompt "$TMPDIR_TEST/prompt.md" > /dev/null 2>"$TMPDIR_TEST/nested.err"
assert_eq "$?" "34" "case5: a nested launch exits 34"
assert_grep 'one level deep' "$TMPDIR_TEST/nested.err" "case5: the refusal names the rule"

# --- 6. empty answer ----------------------------------------------------------
printf 'EMPTY please\n' > "$TMPDIR_TEST/empty.md"
(cd "$REPO" && "$ASSETS/agy.sh" --unit u_empty --prompt "$TMPDIR_TEST/empty.md") > /dev/null 2>&1
assert_eq "$?" "30" "case6: an empty answer exits 30"
assert_grep '^state	failed$' "$REPO/_delegations/u_empty/current/status.tsv" "case6: the run is marked failed"

# --- 7. view ------------------------------------------------------------------
"$ASSETS/view.sh" "$REPO/_delegations/u_research/current/stream.jsonl" > "$TMPDIR_TEST/view.out"
assert_grep '^■ agy  gemini-3.8-flash-medium$' "$TMPDIR_TEST/view.out" "case7: title names the model"
assert_grep '^  \$ search_web q1  ✓ 1.5s$' "$TMPDIR_TEST/view.out" "case7: a tool step is one line with its duration"
assert_grep '^▌ stub agy answer run=u_research/' "$TMPDIR_TEST/view.out" "case7: the answer sits on the bar"
assert_grep '^■ SUCCESS · tool calls 2 · input 7700 (cached 0) · output 40 · 2s$' "$TMPDIR_TEST/view.out" "case7: footer"

echo "PASS [$_TEST_NAME]"
