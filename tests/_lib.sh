# tests/_lib.sh — shared assert helpers and tmpdir scaffold.
# Each test sources this, calls setup_tmpdir, runs assertions.
# On failure: print actual + expected + context, exit non-zero.

# shellcheck shell=bash

set -u

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCIO_TOOLKIT="$TOOLKIT_ROOT"

_TEST_NAME="${0##*/}"

assert_eq() {
    local actual="$1" expected="$2" msg="${3:-}"
    if [[ "$actual" != "$expected" ]]; then
        echo "FAIL [$_TEST_NAME] ${msg:-assert_eq}" >&2
        echo "  expected: $(printf '%q' "$expected")" >&2
        echo "  actual:   $(printf '%q' "$actual")" >&2
        exit 1
    fi
}

assert_file_eq() {
    local a="$1" b="$2" msg="${3:-}"
    if ! diff -u "$a" "$b" >/dev/null; then
        echo "FAIL [$_TEST_NAME] ${msg:-assert_file_eq}" >&2
        echo "--- expected ($b)" >&2
        echo "+++ actual   ($a)" >&2
        diff -u "$b" "$a" >&2 || true
        exit 1
    fi
}

assert_exit() {
    local expected="$1"; shift
    "$@"
    local rc=$?
    if [[ "$rc" -ne "$expected" ]]; then
        echo "FAIL [$_TEST_NAME] expected exit $expected got $rc: $*" >&2
        exit 1
    fi
}

assert_file_exists() {
    local f="$1" msg="${2:-}"
    if [[ ! -e "$f" ]]; then
        echo "FAIL [$_TEST_NAME] ${msg:-file missing: $f}" >&2
        exit 1
    fi
}

assert_symlink() {
    local f="$1" msg="${2:-}"
    if [[ ! -L "$f" ]]; then
        echo "FAIL [$_TEST_NAME] ${msg:-not a symlink: $f}" >&2
        ls -la "$(dirname "$f")" >&2 || true
        exit 1
    fi
}

assert_grep() {
    local pattern="$1" file="$2" msg="${3:-}"
    if ! grep -q "$pattern" "$file"; then
        echo "FAIL [$_TEST_NAME] ${msg:-pattern not found: $pattern in $file}" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        exit 1
    fi
}

# The test tree allows execution, so a stub on PATH shadows the real binary and a
# script under test can run what it extracts; on a noexec /tmp the tree and TMPDIR
# move under the user's cache.
setup_tmpdir() {
    TMPDIR_TEST=$(mktemp -d)
    printf '#!/bin/sh\n' > "$TMPDIR_TEST/.exec_probe" && chmod +x "$TMPDIR_TEST/.exec_probe"
    if ! "$TMPDIR_TEST/.exec_probe" 2>/dev/null; then
        rm -rf "$TMPDIR_TEST"
        mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"
        TMPDIR_TEST=$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/scio-test.XXXXXX")
        mkdir -p "$TMPDIR_TEST/.tmp"
        export TMPDIR="$TMPDIR_TEST/.tmp"
    fi
    rm -f "$TMPDIR_TEST/.exec_probe"
    trap 'cleanup_tmpdir' EXIT
    cd "$TMPDIR_TEST"
}

cleanup_tmpdir() {
    if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
        rm -rf "$TMPDIR_TEST"
    fi
}

pass() {
    echo "PASS [$_TEST_NAME]"
}

# build_fake_toolkit <dir>
# Create a minimal toolkit layout with fixture skills, agents, and commands.
build_fake_toolkit() {
    local root="$1"
    mkdir -p "$root"/{skills/s_a,skills/s_b,skills/s_c,agents,commands,lib,bin}

    # Skills carry the two fields checked by `scio lint --check toolkit`.
    local _s
    for _s in s_a s_b s_c; do
        cat > "$root/skills/$_s/SKILL.md" <<EOF
---
name: $_s
description: Fixture skill $_s.
---

skill $_s
EOF
    done

    # Agents
    echo "agent ag_a" > "$root/agents/ag_a.md"
    echo "agent ag_b" > "$root/agents/ag_b.md"

    # Commands
    echo "cmd c_a"   > "$root/commands/c_a.md"
    echo "cmd c_b"   > "$root/commands/c_b.md"

    # Symlink lib/ and bin/ from the real toolkit so the dispatcher works.
    ln -sfn "$TOOLKIT_ROOT/lib/scio" "$root/lib/scio"
    ln -sfn "$TOOLKIT_ROOT/bin/scio" "$root/bin/scio"
}
