#!/usr/bin/env bash
# tests/test_tmux_pair_stage.sh — a milestone stage runs on a terminal of its own in r2-<name>,
# rendered by weight, with the whole output in a plain log and the stage's exit returned.
#
# Runs on a private tmux server; skips where tmux is absent.
#
# Tests:
#   1. stage.py gives the command a terminal and writes a plain log with the bar at its final state
#   2. the render weighs lines: tagged bold, warnings dim and folded on repeat, errors red
#   3. r2.sh stage opens r2-<name>, waits for the exit, prints the tail and STAGE= with the exit code
#   4. run turns a one-line `CMD 2>&1 | tee LOG` into stage.py
set -u
. "$(dirname "$0")/_lib.sh"

command -v tmux >/dev/null || { echo "SKIP [$_TEST_NAME] tmux is absent"; exit 0; }

setup_tmpdir
R2="$TOOLKIT_ROOT/skills/tmux-pair/scripts/r2.sh"
STAGE="$TOOLKIT_ROOT/skills/tmux-pair/scripts/stage.py"

REPO="$TMPDIR_TEST/repo"
mkdir -p "$REPO"
cat > "$REPO/fake_stage.py" <<'EOF'
import sys, warnings
print("[fit] best epoch 281")
print("tty", sys.stdout.isatty())
for _ in range(2):
    warnings.warn_explicit("Last batch is small", UserWarning, "/venv/lib/site-packages/scvi/split.py", 210)
for i in (0, 50, 100):
    sys.stderr.write(f"\rEpoch {i}/100")
sys.stderr.write("\n")
sys.exit(int(sys.argv[1]) if len(sys.argv) > 1 else 0)
EOF

# --- 1 and 2. stage.py ---------------------------------------------------------
(cd "$REPO" && script -qefc "'$STAGE' --name fake --log logs/fake.log -- python3 fake_stage.py 3" /dev/null) \
    > "$TMPDIR_TEST/render.out" 2>&1
assert_eq "$?" "3" "case1: stage.py exits with the stage's code"
assert_grep '^tty True$' "$REPO/logs/fake.log" "case1: the stage writes to a terminal"
assert_grep '^Epoch 100/100$' "$REPO/logs/fake.log" "case1: the log keeps the bar at its final state"
assert_eq "$(grep -c 'UserWarning' "$REPO/logs/fake.log")" "2" "case1: the log keeps every warning"
assert_grep '^# exit 3 after ' "$REPO/logs/fake.log" "case1: the log closes with the exit"
assert_grep $'\033\\[1;36m\\[fit\\]' "$TMPDIR_TEST/render.out" "case2: a tagged line renders bold"
assert_eq "$(grep -c $'\033\\[2m.*UserWarning' "$TMPDIR_TEST/render.out")" "1" "case2: a warning renders dim, once"
assert_grep '1 repeated warning lines folded' "$TMPDIR_TEST/render.out" "case2: the footer counts folded repeats"
assert_grep $'\033\\[1;31m■ exit 3' "$TMPDIR_TEST/render.out" "case2: a failed exit renders red"

# --- 3 and 4. r2.sh -----------------------------------------------------------
SOCK="scio-test-$$"
tmux -L "$SOCK" -f /dev/null new-session -d -s t -x 160 -y 40 -c "$REPO"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null' EXIT
export TMUX="$(tmux -L "$SOCK" display-message -p '#{socket_path}'),1,0"
export TMUX_PANE="$(tmux -L "$SOCK" display-message -p '#{pane_id}')"

"$R2" stage 30_fake "$REPO" 60 <<<'python3 fake_stage.py' > "$TMPDIR_TEST/stage.out" 2>&1
assert_eq "$?" "0" "case3: r2.sh stage exits with the stage's code"
assert_grep "^STAGE=r2-30_fake exit=0 log=$REPO/logs/30_fake.log$" "$TMPDIR_TEST/stage.out" "case3: STAGE line"
assert_grep '^\[fit\] best epoch 281$' "$TMPDIR_TEST/stage.out" "case3: the tail carries the stage's lines"
assert_eq "$(tmux -L "$SOCK" show-options -pqv -t r2-30_fake @r2_kind)" "stage" "case3: the pane is marked a stage"

"$R2" sh r2-raw "$REPO" > /dev/null
printf 'python3 fake_stage.py 2>&1 | tee logs/raw.log\n' | "$R2" run t:r2-raw 60 > /dev/null 2> "$TMPDIR_TEST/run.err"
assert_grep 'a stage runs through stage.py' "$TMPDIR_TEST/run.err" "case4: run says it rewrote the tee"
assert_grep '^tty True$' "$REPO/logs/raw.log" "case4: the rewritten command writes to a terminal"

echo "PASS [$_TEST_NAME]"
