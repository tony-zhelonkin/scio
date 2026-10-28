#!/usr/bin/env bash
# tests/test_delegate_durable_runs.sh — delegate-cli keeps runs in a durable,
# self-ignoring _delegations root at the outermost working tree.
#
# codex is stubbed. The real binary must not run from a test.
#
# Tests:
#   1. a workdir inside a repository writes its run under <repo>/_delegations
#   2. _delegations ignores itself, so the repository stays clean
#   3. locks stay in scratch, outside the durable root
#   4. status.sh --unit finds the run through the scratch pointer from any directory
#   5. with the scratch pointer gone, status.sh --unit finds the run from inside the repository
#   6. a workdir inside a submodule resolves to the superproject's _delegations
#   7. SCIO_DELEGATIONS overrides the resolved root
set -u
. "$(dirname "$0")/_lib.sh"

setup_tmpdir
ASSETS="$TOOLKIT_ROOT/skills/delegate-cli/assets"

mkdir -p "$TMPDIR_TEST/bin" "$TMPDIR_TEST/tmp"
cat > "$TMPDIR_TEST/bin/codex" <<'EOF'
#!/usr/bin/env bash
out=; prev=
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat > /dev/null
echo "session id: stub-thread"
printf 'the answer\n' > "$out"
EOF
chmod +x "$TMPDIR_TEST/bin/codex"
printf 'do a thing\n' > "$TMPDIR_TEST/prompt.md"

export TMPDIR="$TMPDIR_TEST/tmp" PATH="$TMPDIR_TEST/bin:$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset SCIO_DELEGATIONS

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

echo "PASS [$_TEST_NAME]"
