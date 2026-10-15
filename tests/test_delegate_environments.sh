#!/usr/bin/env bash
# tests/test_delegate_environments.sh — the launcher's behaviour is predictable
# across the environments it actually meets.
#
# codex does not behave the same everywhere. In scbio-docker dev containers as
# shipped, a SANDBOXED codex cannot read files at all: the container policy
# blocks the namespace or filter operation the sandbox is built on, so the run
# fails in a way that reads like a model refusing to cooperate. It launches
# cleanly only with an authorized bypass. These tests pin what the launcher and
# probe do in each of those conditions, so the answer is the same next time
# rather than rediscovered.
#
# codex is stubbed throughout: no test spends real tokens or depends on a
# network. Set SCIO_DELEGATE_LIVE=1 to add one real-binary smoke test at the end.
#
# Tests:
#   1. codex absent from PATH             -> probe exits 10, names it
#   2. sandbox blocks file reads          -> probe exits 14, SANDBOX_FILE_READ=blocked
#   3. sandbox works                      -> probe reports SANDBOX_FILE_READ=ok
#   4. codex fails under launch           -> state=failed, the REAL exit code recorded
#   5. codex writes no final              -> result_exit=30, codex_exit=0
#   6. --bypass reaches codex             -> the flag appears in the invocation
#   7. --sandbox MODE reaches codex       -> -s MODE appears in the invocation
#   8. the run root follows TMPDIR        -> nothing is written outside it
#   9. codex killed mid-run               -> terminal state, not a frozen 'running'
set -u
. "$(dirname "$0")/_lib.sh"

setup_tmpdir
ASSETS="$TOOLKIT_ROOT/skills/delegate-cli/assets"

# _mkenv <name> — isolated runtime root, workdir, prompt. Sets TD, W, P, BIN.
_mkenv() {
    TD="$TMPDIR_TEST/$1"
    BIN="$TD/bin"
    W="$TD/work"
    P="$TD/prompt.md"
    mkdir -p "$TD/tmp" "$W" "$BIN"
    printf 'do a bounded thing\n' > "$P"
}

# Every stub records its own argv so a test can assert what the launcher passed.
_argv_recorder() {
    printf 'printf "%%s\\n" "$@" > "%s/argv"\n' "$TD"
}

# --- 1. codex absent -------------------------------------------------------
# The system directories stay on PATH so the interpreter still resolves; only
# the directory holding codex is dropped. Skipped if codex is installed into a
# system directory on this host, where the condition cannot be constructed.
_mkenv e1
if [ -x /usr/bin/codex ] || [ -x /bin/codex ]; then
    echo "SKIP [$_TEST_NAME] case1: codex is in a system directory here" >&2
else
    set +e
    out1=$(PATH="$BIN:/usr/bin:/bin" "$ASSETS/probe.sh" --workdir "$W" 2>&1); rc1=$?
    set -e
    [ "$rc1" -eq 10 ] || {
        echo "FAIL [$_TEST_NAME] case1: rc was $rc1, expected 10 for absent codex" >&2
        printf '%s\n' "$out1" >&2; exit 1
    }
    printf '%s\n' "$out1" | grep -q 'not available on PATH' || {
        echo "FAIL [$_TEST_NAME] case1: message does not name the cause" >&2
        printf '%s\n' "$out1" >&2; exit 1
    }
fi

# A codex stub whose exec help advertises the flags probe.sh requires, so the
# capability gate passes and the test isolates the condition under study.
_capable_stub() {
    local body="$1"
    cat > "$BIN/codex" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  --version) echo "codex-cli-exec 9.9.9"; exit 0 ;;
esac
if [ "\${1:-}" = exec ] && [ "\${2:-}" = --help ]; then
  cat <<'HELP'
Usage: codex exec [OPTIONS] [PROMPT]
  -C, --cd <DIR>
      --skip-git-repo-check
  -o, --output-last-message <FILE>
  -m, --model <MODEL>
  -s, --sandbox <MODE>
  -c, --config <KEY=VALUE>
      --enable <FEATURE>
      --dangerously-bypass-approvals-and-sandbox
  Reads the prompt from stdin when PROMPT is '-'.
HELP
  exit 0
fi
$body
EOF
    chmod +x "$BIN/codex"
}

# --- 2. the sandbox blocks file reads -------------------------------------
# This is the scbio-docker condition. The bwrap denial goes to the stream, which
# is where probe.sh looks, and the exit is nonzero.
_mkenv e2
_capable_stub 'cat > /dev/null
echo "bwrap: setting up uid map: Operation not permitted" >&2
exit 1'
set +e
out2=$(TMPDIR="$TD/tmp" PATH="$BIN:$PATH" \
    "$ASSETS/probe.sh" --workdir "$W" --sandbox workspace-write --file-read-check 2>&1); rc2=$?
set -e
[ "$rc2" -eq 14 ] || {
    echo "FAIL [$_TEST_NAME] case2: rc was $rc2, expected 14" >&2
    printf '%s\n' "$out2" >&2; exit 1
}
printf '%s\n' "$out2" | grep -q 'SANDBOX_FILE_READ=blocked' || {
    echo "FAIL [$_TEST_NAME] case2: the blocked condition is not reported as a fact" >&2
    printf '%s\n' "$out2" >&2; exit 1
}
# The remedy must be stated, because rewording the prompt is not one.
printf '%s\n' "$out2" | grep -q 'bypass' || {
    echo "FAIL [$_TEST_NAME] case2: no remedy named" >&2
    printf '%s\n' "$out2" >&2; exit 1
}

# --- 3. the sandbox works -------------------------------------------------
_mkenv e3
_capable_stub 'out=; prev=; pfile=
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
prompt=$(cat)
# Echo back the nonce the probe asked us to read.
nfile=$(printf "%s" "$prompt" | sed -n "s#.*Read \\(/[^ ]*nonce.txt\\).*#\\1#p" | head -n 1)
cat "$nfile" > "$out"
exit 0'
set +e
out3=$(TMPDIR="$TD/tmp" PATH="$BIN:$PATH" \
    "$ASSETS/probe.sh" --workdir "$W" --file-read-check 2>&1); rc3=$?
set -e
[ "$rc3" -eq 0 ] || {
    echo "FAIL [$_TEST_NAME] case3: rc was $rc3 for a working sandbox" >&2
    printf '%s\n' "$out3" >&2; exit 1
}
printf '%s\n' "$out3" | grep -q 'SANDBOX_FILE_READ=ok' || {
    echo "FAIL [$_TEST_NAME] case3: a working file read is not reported" >&2
    printf '%s\n' "$out3" >&2; exit 1
}

# _state <runtime-root> <unit>
_state() {
    awk -F'\t' '$1 == "state" { print $2 }' \
        "$1/scio-delegate/$2/current/status.tsv" 2>/dev/null | tail -n 1
}
_field() {
    awk -F'\t' -v k="$3" '$1 == k { print $2 }' \
        "$1/scio-delegate/$2/current/status.tsv" 2>/dev/null | tail -n 1
}

# --- 4. codex fails: the real exit code survives -------------------------
# The old wrapper's printed exit code was decorative. The recorded one must be
# the child's actual status, because that is what a caller acts on.
_mkenv e4
_capable_stub 'cat > /dev/null; echo "sandbox denied" >&2; exit 7'
set +e
TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_fail --workdir "$W" --prompt "$P" --sandbox workspace-write \
    > "$TD/out" 2>&1
rc4=$?
set -e
[ "$rc4" -eq 7 ] || {
    echo "FAIL [$_TEST_NAME] case4: launcher rc was $rc4, expected codex's 7" >&2
    cat "$TD/out" >&2; exit 1
}
[ "$(_state "$TD/tmp" u_fail)" = "failed" ] || {
    echo "FAIL [$_TEST_NAME] case4: state was '$(_state "$TD/tmp" u_fail)'" >&2; exit 1
}
[ "$(_field "$TD/tmp" u_fail codex_exit)" = "7" ] || {
    echo "FAIL [$_TEST_NAME] case4: codex_exit was '$(_field "$TD/tmp" u_fail codex_exit)'" >&2
    exit 1
}

# --- 5. codex succeeds but writes nothing --------------------------------
_mkenv e5
_capable_stub 'cat > /dev/null; echo "done talking"; exit 0'
set +e
TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_nofinal --workdir "$W" --prompt "$P" > "$TD/out" 2>&1
rc5=$?
set -e
[ "$rc5" -eq 30 ] || {
    echo "FAIL [$_TEST_NAME] case5: rc was $rc5, expected 30 for an absent final" >&2
    cat "$TD/out" >&2; exit 1
}
[ "$(_field "$TD/tmp" u_nofinal codex_exit)" = "0" ] || {
    echo "FAIL [$_TEST_NAME] case5: codex succeeded, so codex_exit must be 0" >&2; exit 1
}

# --- 6+7. the authorization flags actually reach codex -------------------
# The container that blocks the sandbox is the reason --bypass exists, so the
# flag reaching the child is the thing worth pinning.
_mkenv e6
_capable_stub "$(_argv_recorder)
out=; prev=
for a in \"\$@\"; do [ \"\$prev\" = \"-o\" ] && out=\"\$a\"; prev=\"\$a\"; done
cat > /dev/null; printf 'ok\n' > \"\$out\"; exit 0"
TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_bypass --workdir "$W" --prompt "$P" --bypass > "$TD/out" 2>&1
grep -qx -- '--dangerously-bypass-approvals-and-sandbox' "$TD/argv" || {
    echo "FAIL [$_TEST_NAME] case6: --bypass did not reach codex" >&2
    cat "$TD/argv" >&2; exit 1
}

_mkenv e7
_capable_stub "$(_argv_recorder)
out=; prev=
for a in \"\$@\"; do [ \"\$prev\" = \"-o\" ] && out=\"\$a\"; prev=\"\$a\"; done
cat > /dev/null; printf 'ok\n' > \"\$out\"; exit 0"
TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_sbx --workdir "$W" --prompt "$P" --sandbox read-only > "$TD/out" 2>&1
grep -qx -- 'read-only' "$TD/argv" || {
    echo "FAIL [$_TEST_NAME] case7: --sandbox value did not reach codex" >&2
    cat "$TD/argv" >&2; exit 1
}
# --bypass and --sandbox together are refused rather than silently reconciled.
set +e
out7=$(TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_both --workdir "$W" --prompt "$P" --bypass --sandbox read-only 2>&1); rc7=$?
set -e
[ "$rc7" -ne 0 ] || {
    echo "FAIL [$_TEST_NAME] case7: --bypass with --sandbox was accepted" >&2; exit 1
}

# --- 8. the run root follows TMPDIR -------------------------------------
# A container gets its own TMPDIR; writing outside it would put run state
# somewhere the next session cannot find and the host may not allow.
_mkenv e8
_capable_stub 'out=; prev=
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat > /dev/null; printf "ok\n" > "$out"; exit 0'
TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_tmp --workdir "$W" --prompt "$P" > "$TD/out" 2>&1
[ -d "$TD/tmp/scio-delegate/u_tmp" ] || {
    echo "FAIL [$_TEST_NAME] case8: run state is not under TMPDIR" >&2; exit 1
}
run_dir=$(sed -n 's/^RUN_DIR=//p' "$TD/out" | tr -d "'")
case "$run_dir" in
    "$TD/tmp"/*) ;;
    *) echo "FAIL [$_TEST_NAME] case8: RUN_DIR '$run_dir' escapes TMPDIR" >&2; exit 1 ;;
esac

# --- 9. a killed child still reaches a terminal state -------------------
# SIGKILL on the child is the case a status writer can still record, unlike a
# SIGKILL on the launcher. Anything left at 'running' would read as in-flight
# forever.
_mkenv e9
_capable_stub 'cat > /dev/null; kill -9 $$'
set +e
TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_killed --workdir "$W" --prompt "$P" > "$TD/out" 2>&1
rc9=$?
set -e
[ "$rc9" -ne 0 ] || {
    echo "FAIL [$_TEST_NAME] case9: a killed child reported success" >&2; exit 1
}
st9=$(_state "$TD/tmp" u_killed)
case "$st9" in
    failed|interrupted) ;;
    *)
        echo "FAIL [$_TEST_NAME] case9: state was '$st9', expected a terminal state" >&2
        exit 1
        ;;
esac

# --- 8b. a sandbox denial with exit 0 is still a failure -----------------
# Measured in a v0.5.10 container on 2026-08-25: bwrap cannot create a namespace,
# every codex file tool fails, and codex EXITS 0 with an answer composed from the
# prompt alone. Three pilot scripts in Meta-Aging were authored that way. So the
# stream is the evidence and the exit code is not; a run carrying the denial can
# never be reported as a success.
_mkenv e8b
_capable_stub 'out=; prev=
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat > /dev/null
echo "bwrap: No permissions to create new namespace, likely because the kernel"
printf "I could not read it, but here is my guess.\n" > "$out"
exit 0'
set +e
TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_blind --workdir "$W" --prompt "$P" --sandbox workspace-write \
    > "$TD/out" 2> "$TD/err"
rc8b=$?
set -e
[ "$rc8b" -eq 32 ] || {
    echo "FAIL [$_TEST_NAME] case8b: rc was $rc8b, expected 32 for a blind run" >&2
    cat "$TD/err" >&2; exit 1
}
[ "$(_state "$TD/tmp" u_blind)" = "failed" ] || {
    echo "FAIL [$_TEST_NAME] case8b: state was '$(_state "$TD/tmp" u_blind)'" >&2; exit 1
}
# codex_exit records what the child really returned; result_exit records the
# verdict. Collapsing them would hide exactly this case.
[ "$(_field "$TD/tmp" u_blind codex_exit)" = "0" ] || {
    echo "FAIL [$_TEST_NAME] case8b: codex_exit must record the child's real 0" >&2; exit 1
}
grep -q 'written blind' "$TD/err" || {
    echo "FAIL [$_TEST_NAME] case8b: the refusal does not say why" >&2
    cat "$TD/err" >&2; exit 1
}

# --- 8b2. without a sandbox, a bwrap mention is content -------------------
# A worker that reads a doc naming bwrap echoes it into the stream. With no
# sandbox enforced nothing could have denied the read, so the run stands.
_mkenv e8b2
_capable_stub 'out=; prev=
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat > /dev/null
echo "/bin/bash -lc '\''cat AGENTS.md'\''"
echo "codex'\''s bwrap sandbox cannot start here (no new namespace)"
printf "read it\n" > "$out"
exit 0'
set +e
TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_mention --workdir "$W" --prompt "$P" > "$TD/out" 2> "$TD/err"
rc8b2=$?
set -e
[ "$rc8b2" -eq 0 ] || {
    echo "FAIL [$_TEST_NAME] case8b2: rc was $rc8b2, expected 0 for an unsandboxed run" >&2
    cat "$TD/err" >&2; exit 1
}
grep -q 'written blind' "$TD/err" && {
    echo "FAIL [$_TEST_NAME] case8b2: file content was reported as a sandbox denial" >&2
    cat "$TD/err" >&2; exit 1
}

# --- 8g. a version refusal is classified only when codex failed -----------
# The server refuses a model newer than the CLI and codex exits 1. The same
# phrase in a successful stream is a prompt or file quoting it.
_mkenv e8g
_capable_stub 'cat > /dev/null
echo "The '\''gpt-6-astra'\'' model requires a newer version of Codex"
exit 1'
set +e
TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_old --workdir "$W" --prompt "$P" > "$TD/out" 2> "$TD/err"
rc8g=$?
set -e
[ "$rc8g" -eq 33 ] || {
    echo "FAIL [$_TEST_NAME] case8g: a refused model returned $rc8g, expected 33" >&2
    cat "$TD/err" >&2; exit 1
}
_mkenv e8h
_capable_stub 'out=; prev=
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat > /dev/null
echo "user"
echo "Docs say: the model requires a newer version of Codex on old CLIs."
printf "done\n" > "$out"
exit 0'
set +e
TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_quote --workdir "$W" --prompt "$P" > "$TD/out" 2> "$TD/err"
rc8h=$?
set -e
[ "$rc8h" -eq 0 ] || {
    echo "FAIL [$_TEST_NAME] case8h: a successful run quoting the refusal returned $rc8h" >&2
    cat "$TD/err" >&2; exit 1
}

# --- 8c. the probe classifies it, despite the zero exit -----------------
_mkenv e8c
_capable_stub 'out=; prev=
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat > /dev/null
echo "bwrap: No permissions to create new namespace"
printf "cannot read\n" > "$out"
exit 0'
set +e
out8c=$(TMPDIR="$TD/tmp" PATH="$BIN:$PATH" \
    "$ASSETS/probe.sh" --workdir "$W" --file-read-check 2>&1); rc8c=$?
set -e
[ "$rc8c" -eq 14 ] || {
    echo "FAIL [$_TEST_NAME] case8c: rc was $rc8c, expected 14" >&2
    printf '%s\n' "$out8c" >&2; exit 1
}
printf '%s\n' "$out8c" | grep -q 'SANDBOX_FILE_READ=blocked' || {
    echo "FAIL [$_TEST_NAME] case8c: a zero-exit denial was not classified as blocked" >&2
    printf '%s\n' "$out8c" >&2; exit 1
}

# --- 8d. exit 0, no denial, no nonce -> unverified, not ok --------------
_mkenv e8d
_capable_stub 'out=; prev=
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat > /dev/null; printf "sure thing\n" > "$out"; exit 0'
set +e
out8d=$(TMPDIR="$TD/tmp" PATH="$BIN:$PATH" \
    "$ASSETS/probe.sh" --workdir "$W" --file-read-check 2>&1); rc8d=$?
set -e
[ "$rc8d" -eq 14 ] || {
    echo "FAIL [$_TEST_NAME] case8d: rc was $rc8d, expected 14" >&2; exit 1
}
printf '%s\n' "$out8d" | grep -q 'SANDBOX_FILE_READ=unverified' || {
    echo "FAIL [$_TEST_NAME] case8d: an unproven read was not reported as unverified" >&2
    printf '%s\n' "$out8d" >&2; exit 1
}

# --- 9b. the probe reports which model a launch will actually use --------
# An unsupported --model is refused by the server after launch, not by the flag
# check, so the reliable move is to pass none and read the configured default.
_mkenv e9b
_capable_stub 'exit 0'
mkdir -p "$TD/codex_home"
printf 'model = "cfg-model"\nmodel_reasoning_effort = "high"\n' > "$TD/codex_home/config.toml"
out9b=$(CODEX_HOME="$TD/codex_home" TMPDIR="$TD/tmp" PATH="$BIN:$PATH" \
    "$ASSETS/probe.sh" --workdir "$W" --model made-up 2>&1)
printf '%s\n' "$out9b" | grep -q 'CODEX_MODEL_CONFIGURED=cfg-model' || {
    echo "FAIL [$_TEST_NAME] case9b: the configured model is not reported" >&2
    printf '%s\n' "$out9b" >&2; exit 1
}
printf '%s\n' "$out9b" | grep -q 'CODEX_MODEL_REQUESTED_VALIDATED=0' || {
    echo "FAIL [$_TEST_NAME] case9b: a requested model is not flagged unvalidated" >&2
    printf '%s\n' "$out9b" >&2; exit 1
}

# --- 8e. no sandbox by default ------------------------------------------
# An enforced sandbox cannot open files in these containers, so the default is
# none and the container is the boundary. Owner ruling 2026-08-25.
_mkenv e8e
_capable_stub "$(_argv_recorder)
out=; prev=
for a in \"\$@\"; do [ \"\$prev\" = \"-o\" ] && out=\"\$a\"; prev=\"\$a\"; done
cat > /dev/null; printf 'ok\\n' > \"\$out\"; exit 0"
TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_defsbx --workdir "$W" --prompt "$P" > "$TD/out" 2>&1
grep -qx -- 'danger-full-access' "$TD/argv" || {
    echo "FAIL [$_TEST_NAME] case8e: the default sandbox is not danger-full-access" >&2
    cat "$TD/argv" >&2; exit 1
}
# The deliverable comes back from the command that produced it.
grep -q -- '--- FINAL MESSAGE ---' "$TD/out" || {
    echo "FAIL [$_TEST_NAME] case8e: the final message was not printed" >&2
    cat "$TD/out" >&2; exit 1
}
# An explicit --sandbox still wins, so re-enabling one stays possible.
_mkenv e8f
_capable_stub "$(_argv_recorder)
out=; prev=
for a in \"\$@\"; do [ \"\$prev\" = \"-o\" ] && out=\"\$a\"; prev=\"\$a\"; done
cat > /dev/null; printf 'ok\\n' > \"\$out\"; exit 0"
TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_optin --workdir "$W" --prompt "$P" --sandbox read-only > "$TD/out" 2>&1
grep -qx -- 'read-only' "$TD/argv" || {
    echo "FAIL [$_TEST_NAME] case8f: an explicit --sandbox was overridden by the default" >&2
    cat "$TD/argv" >&2; exit 1
}
grep -qx -- 'danger-full-access' "$TD/argv" && {
    echo "FAIL [$_TEST_NAME] case8f: both the default and the explicit mode were passed" >&2
    cat "$TD/argv" >&2; exit 1
}

# --- 9c. effort and web ride -c, because codex exec has no flag for either --
_mkenv e9c
_capable_stub "$(_argv_recorder)
out=; prev=
for a in \"\$@\"; do [ \"\$prev\" = \"-o\" ] && out=\"\$a\"; prev=\"\$a\"; done
cat > /dev/null; printf 'ok\\n' > \"\$out\"; exit 0"
TMPDIR="$TD/tmp" PATH="$BIN:$PATH" "$ASSETS/launch.sh" \
    --unit u_effort --workdir "$W" --prompt "$P" --effort high --web > "$TD/out" 2>&1
grep -qx -- 'model_reasoning_effort=high' "$TD/argv" || {
    echo "FAIL [$_TEST_NAME] case9c: --effort did not become -c model_reasoning_effort" >&2
    cat "$TD/argv" >&2; exit 1
}
grep -qx -- 'tools.web_search=true' "$TD/argv" || {
    echo "FAIL [$_TEST_NAME] case9c: --web did not become -c tools.web_search" >&2
    cat "$TD/argv" >&2; exit 1
}
# An effort flag would be wrong: codex exec does not have one.
grep -qE -- '^--(effort|reasoning|search)$' "$TD/argv" && {
    echo "FAIL [$_TEST_NAME] case9c: a flag codex exec lacks was passed" >&2
    cat "$TD/argv" >&2; exit 1
}

# --- 10. opt-in live smoke test ----------------------------------------
# Costs tokens and needs a configured codex, so it runs only on request.
if [ "${SCIO_DELEGATE_LIVE:-0}" = "1" ]; then
    _mkenv live
    if ! command -v codex >/dev/null 2>&1; then
        echo "SKIP [$_TEST_NAME] case10: SCIO_DELEGATE_LIVE=1 but codex is absent" >&2
    else
        printf 'Reply with exactly: SCIO_LIVE_OK\n' > "$P"
        set +e
        TMPDIR="$TD/tmp" "$ASSETS/launch.sh" --unit u_live --workdir "$W" \
            --prompt "$P" > "$TD/out" 2>&1
        rcl=$?
        set -e
        echo "INFO [$_TEST_NAME] case10: live launcher rc=$rcl state=$(_state "$TD/tmp" u_live)" >&2
        [ "$rcl" -eq 0 ] || {
            echo "FAIL [$_TEST_NAME] case10: live run failed; probe --file-read-check for the cause" >&2
            cat "$TD/out" >&2
            exit 1
        }
    fi
fi

pass
