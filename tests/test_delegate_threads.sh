#!/usr/bin/env bash
# tests/test_delegate_threads.sh — a unit's codex thread can be continued or
# copied, so a follow-up reuses the context the worker already built.
#
# codex keys its prompt cache per thread: a fresh thread re-pays everything after
# the shared system prefix, while a resumed one re-pays only the new turn. These
# tests pin how the launcher records a thread and hands it back to codex.
#
# codex is stubbed throughout: no test spends real tokens.
#
# Tests:
#   1. a fresh run records its thread    -> thread file, status row, THREAD= line
#   2. every launch disables plugins     -> --disable plugins in the invocation
#   3. --resume continues the thread     -> exec resume <id>, sandbox via -c, run from workdir
#   4. --resume with nothing to resume   -> exit 2, names the unit
#   5. --resume elsewhere                -> exit 2, a thread keeps its workdir
#   6. --resume with --rules             -> exit 2, the thread already has them
#   7. --fork-from copies another thread -> exec fork <id>, new thread recorded
#   8. a legacy run without a thread file -> the banner's session id is resumed
#   9. --resume under an enforced sandbox -> the mode rides -c and a denial is still 32
set -u
. "$(dirname "$0")/_lib.sh"

setup_tmpdir
ASSETS="$TOOLKIT_ROOT/skills/delegate-cli/assets"

# One runtime root for every case, because resume and fork read earlier runs.
RT="$TMPDIR_TEST/rt"
BIN="$TMPDIR_TEST/bin"
W="$TMPDIR_TEST/work"
W2="$TMPDIR_TEST/elsewhere"
P="$TMPDIR_TEST/prompt.md"
R="$TMPDIR_TEST/rules.md"
LOG="$TMPDIR_TEST/calls"
mkdir -p "$RT" "$BIN" "$W" "$W2" "$LOG"
printf 'do a bounded thing\n' > "$P"
printf 'house rules\n' > "$R"

# The stub prints the banner line the launcher reads, numbering fresh and forked
# threads so each gets its own id, and records argv and cwd per call.
cat > "$BIN/codex" <<EOF
#!/usr/bin/env bash
n=\$(ls "$LOG" | wc -l); n=\$((n + 1))
printf '%s\n' "\$@" > "$LOG/\$n.argv"
pwd > "$LOG/\$n.cwd"
out=; prev=
for a in "\$@"; do [ "\$prev" = "-o" ] && out="\$a"; prev="\$a"; done
cat > /dev/null
case "\$2" in
  resume) id="\${@: -2:1}" ;;
  *)      id="00000000-0000-0000-0000-00000000000\$n" ;;
esac
echo "workdir: \$(pwd)"
echo "session id: \$id"
[ -z "\${STUB_DENY:-}" ] || echo "bwrap: No permissions to create new namespace"
printf 'done\n' > "\$out"
EOF
chmod +x "$BIN/codex"

last_argv() { ls "$LOG"/*.argv | sort -V | tail -n 1; }
thread_arg() { tail -n 2 "$1" | head -n 1; }
last_cwd() { ls "$LOG"/*.cwd | sort -V | tail -n 1; }
field() { awk -F'\t' -v k="$2" '$1 == k { print $2 }' "$RT/scio-delegate/$1/current/status.tsv" | tail -n 1; }
launch() { TMPDIR="$RT" PATH="$BIN:$PATH" "$ASSETS/launch.sh" "$@"; }
die() { echo "FAIL [$_TEST_NAME] $*" >&2; exit 1; }

# --- 1. a fresh run records its thread -------------------------------------
out1=$(launch --unit impl --workdir "$W" --prompt "$P" --rules "$R" 2>&1) || die "case1: launch failed: $out1"
t1=$(cat "$RT/scio-delegate/impl/current/thread" 2>/dev/null)
[ "$t1" = "00000000-0000-0000-0000-000000000001" ] || die "case1: thread file holds '$t1'"
[ "$(field impl thread)" = "$t1" ] || die "case1: status thread row is '$(field impl thread)'"
[ "$(field impl origin)" = fresh ] || die "case1: origin is '$(field impl origin)'"
printf '%s\n' "$out1" | grep -qx "THREAD=$t1" || die "case1: no THREAD= line in the output"
"$ASSETS/status.sh" --file "$RT/scio-delegate/impl/current/status.tsv" | grep -q "thread=$t1" \
    || die "case1: status.sh does not report the thread"

# --- 2. every launch disables plugins --------------------------------------
grep -qx -- '--disable' "$(last_argv)" && grep -qx plugins "$(last_argv)" \
    || die "case2: plugins were not disabled"

# --- 3. --resume continues the thread --------------------------------------
launch --unit impl --workdir "$W" --prompt "$P" --resume > /dev/null 2>&1 || die "case3: resume failed"
a3=$(last_argv)
[ "$(sed -n 2p "$a3")" = resume ] || die "case3: second argv word is '$(sed -n 2p "$a3")'"
grep -qx "$t1" "$a3" || die "case3: the thread id was not passed"
grep -qx 'sandbox_mode="danger-full-access"' "$a3" || die "case3: the sandbox did not ride -c"
grep -qx -- '-s' "$a3" && die "case3: resume was given -s, which it rejects"
grep -qx -- '-C' "$a3" && die "case3: resume was given -C, which it rejects"
[ "$(cat "$(last_cwd)")" = "$(cd "$W" && pwd -P)" ] || die "case3: resume ran from $(cat "$(last_cwd)")"
[ "$(field impl origin)" = resume ] || die "case3: origin is '$(field impl origin)'"
[ "$(field impl thread)" = "$t1" ] || die "case3: the resumed run lost its thread"
[ "$(thread_arg "$a3")" = "$t1" ] || die "case3: the thread id does not precede the stdin marker"

# --- 4. --resume with nothing to resume ------------------------------------
set +e
out4=$(launch --unit never-ran --workdir "$W" --prompt "$P" --resume 2>&1); rc4=$?
set -e
[ "$rc4" -eq 2 ] || die "case4: rc was $rc4"
printf '%s\n' "$out4" | grep -q 'never-ran has no recorded codex thread' || die "case4: $out4"

# --- 5. --resume elsewhere --------------------------------------------------
set +e
out5=$(launch --unit impl --workdir "$W2" --prompt "$P" --resume 2>&1); rc5=$?
set -e
[ "$rc5" -eq 2 ] || die "case5: rc was $rc5"
printf '%s\n' "$out5" | grep -q 'same --workdir' || die "case5: $out5"

# --- 6. --resume with --rules -----------------------------------------------
set +e
out6=$(launch --unit impl --workdir "$W" --prompt "$P" --resume --rules "$R" 2>&1); rc6=$?
set -e
[ "$rc6" -eq 2 ] || die "case6: rc was $rc6"
printf '%s\n' "$out6" | grep -q 'already carries its rules' || die "case6: $out6"

# --- 7. --fork-from copies another thread ----------------------------------
launch --unit worker-b --workdir "$W" --prompt "$P" --fork-from impl > /dev/null 2>&1 || die "case7: fork failed"
a7=$(last_argv)
[ "$(sed -n 2p "$a7")" = fork ] || die "case7: second argv word is '$(sed -n 2p "$a7")'"
[ "$(thread_arg "$a7")" = "$t1" ] || die "case7: the source thread does not precede the stdin marker"
t7=$(field worker-b thread)
[ -n "$t7" ] && [ "$t7" != "$t1" ] && [ "$t7" != - ] || die "case7: the fork recorded thread '$t7'"
[ "$(field worker-b origin)" = fork ] || die "case7: origin is '$(field worker-b origin)'"

# --- 8. a legacy run without a thread file ----------------------------------
# Runs recorded before the launcher kept a thread file are resumable from the
# codex banner in their stream.
legacy="$RT/scio-delegate/legacy/20260101T000000Z-1"
mkdir -p "$legacy"
printf 'workdir: %s\nsession id: 11111111-2222-3333-4444-555555555555\n' "$W" > "$legacy/stream.log"
ln -s 20260101T000000Z-1 "$RT/scio-delegate/legacy/current"
launch --unit legacy --workdir "$W" --prompt "$P" --resume > /dev/null 2>&1 || die "case8: legacy resume failed"
[ "$(thread_arg "$(last_argv)")" = 11111111-2222-3333-4444-555555555555 ] || die "case8: banner id not resumed"

# --- 9. --resume under an enforced sandbox ---------------------------------
launch --unit impl --workdir "$W" --prompt "$P" --resume --sandbox workspace-write > /dev/null 2>&1
grep -qx 'sandbox_mode="workspace-write"' "$(last_argv)" || die "case9: the explicit mode did not ride -c"
set +e
STUB_DENY=1 launch --unit impl --workdir "$W" --prompt "$P" --resume --sandbox workspace-write > /dev/null 2>&1
rc9=$?
set -e
[ "$rc9" -eq 32 ] || die "case9: a denied resume returned $rc9"

pass
