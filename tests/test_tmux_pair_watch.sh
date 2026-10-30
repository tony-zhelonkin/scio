#!/usr/bin/env bash
# tests/test_tmux_pair_watch.sh — one run, one window: r2.sh watch opens r2-<unit>
# rendering the run's stream, ls names the unit with its state, done closes it.
#
# Runs on a private tmux server; skips where tmux is absent.
#
# Tests:
#   1. watch opens a window named r2-<unit> whose pane shows the rendered stream
#   2. a second watch of the same unit reuses the window
#   3. ls lists the window with unit= and the run's state
#   4. done closes the window, and done on a closed unit exits 2
#   5. run with a one-line tail -f of a stream runs view.sh --follow instead
#   6. watch before the launch waits for the run, then renders it
#   7. a new run of the unit (a resume) renders in the same window
set -u
. "$(dirname "$0")/_lib.sh"

command -v tmux >/dev/null || { echo "SKIP [$_TEST_NAME] tmux is absent"; exit 0; }

setup_tmpdir
R2="$TOOLKIT_ROOT/skills/tmux-pair/scripts/r2.sh"
export NO_COLOR=1

REPO="$TMPDIR_TEST/repo"
git init -q "$REPO"
RUN="$REPO/_delegations/u_watch/run1"
mkdir -p "$RUN"
printf '{"type":"message_end","message":{"role":"user","content":[{"type":"text","text":"# Count the entries"}]}}\n' > "$RUN/stream.jsonl"
printf '{"type":"message_end","message":{"role":"assistant","model":"qwen3.6:35b","usage":{"input":9,"output":1},"content":[{"type":"text","text":"3 entries."}]}}\n' >> "$RUN/stream.jsonl"
printf 'schema\t1\nunit\tu_watch\nworker\tpi\nrun_id\trun1\nstate\tsucceeded\nlauncher_pid\t1\nchild_pid\t1\n' > "$RUN/status.tsv"
printf 'start_epoch\t100\nsample_epoch\t110\nlast_activity_epoch\t110\nterminal_epoch\t110\ncodex_exit\t0\nresult_exit\t0\norigin\tfresh\nthread\t-\n' >> "$RUN/status.tsv"
ln -s run1 "$REPO/_delegations/u_watch/current"

SOCK="scio-test-$$"
tmux -L "$SOCK" -f /dev/null new-session -d -s t -x 160 -y 40 -c "$REPO"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null' EXIT
export TMUX="$(tmux -L "$SOCK" display-message -p '#{socket_path}'),1,0"
export TMUX_PANE="$(tmux -L "$SOCK" display-message -p '#{pane_id}')"

out=$("$R2" watch u_watch "$REPO") || { echo "FAIL [$_TEST_NAME] case1: watch failed: $out" >&2; exit 1; }
assert_eq "$out" "WINDOW=r2-u_watch unit=u_watch" "case1: watch names the window after the unit"
for _ in $(seq 1 20); do
    tmux -L "$SOCK" capture-pane -p -t r2-u_watch | grep -q '3 entries' && break
    sleep 0.25
done
assert_grep '^■ pi  Count the entries' <(tmux -L "$SOCK" capture-pane -p -t r2-u_watch) \
    "case1: the window's first line names the brief"
assert_grep '^▌ 3 entries.$' <(tmux -L "$SOCK" capture-pane -p -t r2-u_watch) \
    "case1: the window renders the worker's message"

assert_eq "$("$R2" watch u_watch "$REPO")" "WINDOW=r2-u_watch reused" "case2: a second watch reuses the window"

ls_out=$("$R2" ls)
assert_grep 'r2-u_watch .* unit=u_watch .* state=succeeded elapsed_s=[0-9]*' <(printf '%s\n' "$ls_out") \
    "case3: ls names the unit with its state"

assert_eq "$("$R2" done u_watch)" "CLOSED=r2-u_watch" "case4: done closes the window"
assert_eq "$(tmux -L "$SOCK" list-windows -F '#{window_name}' | grep -c '^r2-u_watch$')" "0" \
    "case4: the window is gone"
"$R2" done u_watch 2>/dev/null
assert_eq "$?" "2" "case4: done on a closed unit exits 2"

"$R2" sh r2-u_raw "$REPO" >/dev/null
printf 'tail -f %s\n' "$RUN/stream.jsonl" | timeout 20 "$R2" run t:r2-u_raw 3 >/dev/null 2>"$TMPDIR_TEST/run.err" || true
assert_grep 'a stream reads through view.sh' "$TMPDIR_TEST/run.err" "case5: run says it rewrote the tail into view.sh"
for _ in $(seq 1 20); do
    tmux -L "$SOCK" capture-pane -p -t r2-u_raw | grep -q '3 entries' && break
    sleep 0.2
done
tmux -L "$SOCK" capture-pane -p -t r2-u_raw > "$TMPDIR_TEST/run.pane"
assert_grep '■ pi  Count the entries' "$TMPDIR_TEST/run.pane" "case5: the pane shows the rendered title line"

wait_for() {
    for _ in $(seq 1 30); do
        tmux -L "$SOCK" capture-pane -p -t "$1" | grep -q "$2" && return 0
        sleep 0.25
    done
    return 1
}
out=$("$R2" watch u_late "$REPO") || { echo "FAIL [$_TEST_NAME] case6: watch before the launch failed: $out" >&2; exit 1; }
wait_for r2-u_late 'waiting for u_late' || { echo "FAIL [$_TEST_NAME] case6: the window waits for the run" >&2; exit 1; }
mkdir -p "$REPO/_delegations/u_late/run1"
cp "$RUN/stream.jsonl" "$REPO/_delegations/u_late/run1/stream.jsonl"
ln -s run1 "$REPO/_delegations/u_late/current"
wait_for r2-u_late '3 entries' || { echo "FAIL [$_TEST_NAME] case6: the window renders the run once it starts" >&2; exit 1; }

mkdir -p "$REPO/_delegations/u_late/run2"
printf '{"type":"message_end","message":{"role":"assistant","model":"qwen3.6:35b","usage":{"input":9,"output":1},"content":[{"type":"text","text":"resumed answer."}]}}\n' \
    > "$REPO/_delegations/u_late/run2/stream.jsonl"
ln -sfn run2 "$REPO/_delegations/u_late/current"
wait_for r2-u_late 'resumed answer' || { echo "FAIL [$_TEST_NAME] case7: a new run renders in the same window" >&2; exit 1; }
tmux -L "$SOCK" capture-pane -p -t r2-u_late > "$TMPDIR_TEST/late.pane"
assert_grep '── next run run2 ──' "$TMPDIR_TEST/late.pane" "case7: the window marks the next run"

echo "PASS [$_TEST_NAME]"
