#!/usr/bin/env bash
# tests/test_delegate_durable_runs.sh — delegate-cli keeps runs in a durable,
# self-ignoring _delegations root at the outermost working tree, and delegation
# stays one level deep.
#
# codex, pi and curl are stubbed; each stub's output proves the stub ran.
#
# Tests:
#   1. a workdir inside a repository writes its run under <repo>/_delegations
#   2. _delegations ignores itself, so the repository stays clean
#   3. locks stay in scratch, outside the durable root
#   4. status.sh --unit finds the run through the scratch pointer from any directory
#   5. with the scratch pointer gone, status.sh --unit finds the run from inside the repository
#   6. a workdir inside a submodule resolves to the superproject's _delegations
#   7. SCIO_DELEGATIONS overrides the resolved root
#   8. the worker runs with SCIO_DELEGATION_RUN naming its unit and run
#   9. launch.sh and pi.sh refuse to start inside a delegation (exit 34)
#  10. pi.sh records a run in the same root and prints the final message and usage
#  11. status.sh --all lists one SUMMARY line per unit, with its worker
#  12. pi.sh stops with exit 40 when the model is missing from the GPU
set -u
. "$(dirname "$0")/_lib.sh"

setup_tmpdir
ASSETS="$TOOLKIT_ROOT/skills/delegate-cli/assets"

mkdir -p "$TMPDIR_TEST/bin" "$TMPDIR_TEST/tmp"
cat > "$TMPDIR_TEST/bin/codex" <<'STUB'
#!/usr/bin/env bash
out=; prev=
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat > /dev/null
echo "session id: stub-thread"
printf 'stub answer run=%s\n' "${SCIO_DELEGATION_RUN:-unset}" > "$out"
STUB
cat > "$TMPDIR_TEST/bin/pi" <<'STUB'
#!/usr/bin/env bash
printf '{"type":"message_end","message":{"role":"assistant","usage":{"input":900,"output":40},"content":[{"type":"toolCall"},{"type":"text","text":"stub pi answer run=%s"}]}}\n' "${SCIO_DELEGATION_RUN:-unset}"
STUB
cat > "$TMPDIR_TEST/bin/curl" <<'STUB'
#!/usr/bin/env bash
[ -n "${STUB_OLLAMA_EMPTY:-}" ] && { echo '{"models":[]}'; exit 0; }
echo '{"models":[{"name":"qwen3.6:35b"}]}'
STUB
chmod +x "$TMPDIR_TEST/bin/codex" "$TMPDIR_TEST/bin/pi" "$TMPDIR_TEST/bin/curl"
printf 'do a thing\n' > "$TMPDIR_TEST/prompt.md"

export TMPDIR="$TMPDIR_TEST/tmp" PATH="$TMPDIR_TEST/bin:$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset SCIO_DELEGATIONS SCIO_DELEGATION_RUN

_repo() {
    git init -q "$1"
    printf 'x\n' > "$1/file.txt"
    git -C "$1" add file.txt
    git -C "$1" commit -q -m init
}

_launch() {
    "$ASSETS/launch.sh" --unit "$1" --workdir "$2" --prompt "$TMPDIR_TEST/prompt.md" \
        > "$TMPDIR_TEST/$1.out" 2>&1 || {
        echo "FAIL [$_TEST_NAME] launch of $1 failed" >&2
        cat "$TMPDIR_TEST/$1.out" >&2
        exit 1
    }
}

# --- 1+2+3. the durable root, self-ignoring, with locks in scratch -----------
REPO="$TMPDIR_TEST/repo"
_repo "$REPO"
mkdir -p "$REPO/sub/dir"
_launch u_durable "$REPO/sub/dir"

assert_file_exists "$REPO/_delegations/u_durable/current/final.md" \
    "case1: the run should live under <repo>/_delegations"
assert_grep '^RUN_DIR=.*/repo/_delegations/u_durable/' "$TMPDIR_TEST/u_durable.out" \
    "case1: RUN_DIR should name the durable root"
assert_eq "*" "$(cat "$REPO/_delegations/.gitignore")" \
    "case2: _delegations/.gitignore should hold a single *"
assert_eq "" "$(git -C "$REPO" status --porcelain)" \
    "case2: the repository should stay clean"
[ ! -e "$REPO/_delegations/locks" ] || {
    echo "FAIL [$_TEST_NAME] case3: locks belong in scratch, found $REPO/_delegations/locks" >&2
    exit 1
}

# --- 4. the scratch pointer serves status.sh from any directory --------------
assert_symlink "$TMPDIR/scio-delegate/u_durable/current" \
    "case4: the launcher should leave a scratch pointer"
( cd / && "$ASSETS/status.sh" --unit u_durable ) > "$TMPDIR_TEST/s4.out" 2>&1 || {
    echo "FAIL [$_TEST_NAME] case4: status.sh --unit failed through the pointer" >&2
    cat "$TMPDIR_TEST/s4.out" >&2
    exit 1
}
assert_grep 'state=succeeded' "$TMPDIR_TEST/s4.out" "case4: the run should read succeeded"

# --- 5. with the pointer gone, the durable root of the cwd serves status.sh --
rm -rf "$TMPDIR/scio-delegate/u_durable"
( cd "$REPO/sub" && "$ASSETS/status.sh" --unit u_durable ) > "$TMPDIR_TEST/s5.out" 2>&1 || {
    echo "FAIL [$_TEST_NAME] case5: status.sh --unit failed after the pointer was cleared" >&2
    cat "$TMPDIR_TEST/s5.out" >&2
    exit 1
}
assert_grep 'state=succeeded' "$TMPDIR_TEST/s5.out" "case5: the run should read succeeded"

# --- 6. a submodule workdir resolves to the superproject ---------------------
SUPER="$TMPDIR_TEST/super"
_repo "$SUPER"
_repo "$TMPDIR_TEST/child"
git -C "$SUPER" -c protocol.file.allow=always submodule add -q "$TMPDIR_TEST/child" child
git -C "$SUPER" commit -q -m "add child"
_launch u_sub "$SUPER/child"
assert_file_exists "$SUPER/_delegations/u_sub/current/final.md" \
    "case6: a submodule run should land in the superproject's _delegations"
[ ! -e "$SUPER/child/_delegations" ] || {
    echo "FAIL [$_TEST_NAME] case6: the submodule grew its own _delegations" >&2
    exit 1
}

# --- 7. SCIO_DELEGATIONS overrides -------------------------------------------
SCIO_DELEGATIONS="$TMPDIR_TEST/elsewhere" _launch u_env "$REPO"
assert_file_exists "$TMPDIR_TEST/elsewhere/u_env/current/final.md" \
    "case7: SCIO_DELEGATIONS should place the run"

# --- 8. the worker carries its delegation in the environment -----------------
assert_grep '^stub answer run=u_durable/[0-9TZ]*-[0-9]*$' "$REPO/_delegations/u_durable/current/final.md" \
    "case8: the stub should have run with SCIO_DELEGATION_RUN=<unit>/<run_id>"

# --- 9. a launcher inside a delegation refuses --------------------------------
SCIO_DELEGATION_RUN=outer/1 "$ASSETS/launch.sh" --unit u_nested --workdir "$REPO" \
    --prompt "$TMPDIR_TEST/prompt.md" > "$TMPDIR_TEST/n.out" 2>&1
rc_launch=$?
SCIO_DELEGATION_RUN=outer/1 "$ASSETS/pi.sh" --unit u_nested --workdir "$REPO" \
    --prompt "$TMPDIR_TEST/prompt.md" >> "$TMPDIR_TEST/n.out" 2>&1
rc_pi=$?
assert_eq "$rc_launch $rc_pi" "34 34" "case9: both launchers should refuse a nested start"
assert_grep 'one level deep' "$TMPDIR_TEST/n.out" "case9: the refusal should name the rule"
[ ! -e "$REPO/_delegations/u_nested" ] || {
    echo "FAIL [$_TEST_NAME] case9: a refused launch left a run directory" >&2
    exit 1
}

# --- 10. pi.sh records into the same root -------------------------------------
"$ASSETS/pi.sh" --unit u_pi --workdir "$REPO/sub" --prompt "$TMPDIR_TEST/prompt.md" \
    > "$TMPDIR_TEST/pi.out" 2>&1 || {
    echo "FAIL [$_TEST_NAME] case10: pi.sh failed" >&2
    cat "$TMPDIR_TEST/pi.out" >&2
    exit 1
}
assert_grep '^stub pi answer run=u_pi/' "$REPO/_delegations/u_pi/current/final.md" \
    "case10: pi.sh should write the final message with the delegation in the environment"
assert_grep 'USAGE.turns=1.tool_calls=1.peak_context=900.output_tokens=40' "$TMPDIR_TEST/pi.out" \
    "case10: pi.sh should print the usage line"
assert_grep '^--- FINAL MESSAGE ---$' "$TMPDIR_TEST/pi.out" "case10: pi.sh should print the final message"

# --- 11. the ledger lists every unit with its worker --------------------------
( cd "$REPO/sub" && "$ASSETS/status.sh" --all ) > "$TMPDIR_TEST/all.out" 2>&1 || {
    echo "FAIL [$_TEST_NAME] case11: status.sh --all failed" >&2
    cat "$TMPDIR_TEST/all.out" >&2
    exit 1
}
assert_eq "$(grep -c "^SUMMARY" "$TMPDIR_TEST/all.out")" "2" "case11: one line per unit (u_durable, u_pi)"
assert_grep 'unit=u_pi.worker=pi.*state=succeeded' "$TMPDIR_TEST/all.out" "case11: the pi run is listed"
assert_grep 'unit=u_durable.worker=codex' "$TMPDIR_TEST/all.out" "case11: the codex run is listed"
assert_eq "$(grep -c "^ARTIFACT" "$TMPDIR_TEST/all.out")" "0" "case11: --all prints summaries alone"

# --- 12. a missing model stops pi.sh ------------------------------------------
STUB_OLLAMA_EMPTY=1 "$ASSETS/pi.sh" --unit u_pi_missing --workdir "$REPO" \
    --prompt "$TMPDIR_TEST/prompt.md" > "$TMPDIR_TEST/m.out" 2>&1
rc=$?
assert_eq "$rc" "40" "case12: a missing model should exit 40"
assert_grep 'Ask the user to load it' "$TMPDIR_TEST/m.out" "case12: the message should hand the load to the user"

echo "PASS [$_TEST_NAME]"
