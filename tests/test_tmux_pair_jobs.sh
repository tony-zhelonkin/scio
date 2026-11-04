#!/usr/bin/env bash
# Group jobs without moving the owner or losing identity after renaming.
set -eu
. "$(dirname "$0")/_lib.sh"
command -v tmux-jobs >/dev/null || { echo 'SKIP: dev-env tmux-jobs is absent'; exit 0; }
setup_tmpdir
R2="$TOOLKIT_ROOT/skills/tmux-pair/scripts/r2.sh"
SOCK="scio-jobs-test-$$"
tmux -L "$SOCK" -f /dev/null new-session -d -s project -x 160 -y 40
trap 'tmux -L "$SOCK" kill-server 2>/dev/null' EXIT
export TMUX="$(tmux -L "$SOCK" display-message -p '#{socket_path}'),1,0"
export TMUX_PANE="$(tmux display-message -p '#{pane_id}')"
original=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')
export SCIO_STREAM=explorer SCIO_LABEL='implementer · shell · interactive'
first=$("$R2" sh r2-build "$TMPDIR_TEST")
pane=$(printf '%s\n' "$first" | sed -n 's/.*PANE=\([^ ]*\).*/\1/p')
window=$(tmux display-message -p -t "$pane" '#{window_id}')
tmux rename-window -t "$window" 'my explorer'
second=$(SCIO_LABEL='reviewer · shell · interactive' "$R2" sh r2-review "$TMPDIR_TEST")
review=$(printf '%s\n' "$second" | sed -n 's/.*PANE=\([^ ]*\).*/\1/p')
assert_eq "$(tmux display-message -p -t "$review" '#{window_id}')" "$window" 'same stream shares a window after rename'
assert_eq "$(tmux show-options -pqv -t "$pane" @r2_label)" "$SCIO_LABEL" 'explicit role label'
layout=$(tmux display-message -p -t "$window" '#{window_layout}')
"$R2" sh r2-build "$TMPDIR_TEST" >/dev/null
assert_eq "$(tmux display-message -p -t "$window" '#{window_layout}')" "$layout" 'reuse preserves layout'
assert_eq "$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')" "$original" 'owner stays in original window'
assert_eq "$(tmux list-windows -t project -F '#{window_id}' | wc -l | tr -d ' ')" 1 'owner session has no added windows'
printf 'printf "hello-jobs\\n"\n' | "$R2" run "$pane" 10 > "$TMPDIR_TEST/output"
assert_grep 'hello-jobs' "$TMPDIR_TEST/output" 'owned pane executes after rename'
"$R2" done build >/dev/null
assert_eq "$(tmux display-message -p -t "$review" '#{pane_id}')" "$review" 'closing one job preserves its peer'
# A familiar name does not grant write ownership.
foreign=$(tmux new-window -d -P -F '#{pane_id}' -t project: -n r2-foreign)
if printf 'echo forbidden\n' | "$R2" run "$foreign" 1 2>/dev/null; then
    echo 'FAIL: wrote to an unowned r2-named window' >&2; exit 1
fi
if TMUX_PANE=%999999 "$R2" sh r2-stray "$TMPDIR_TEST" 2>/dev/null; then
    echo 'FAIL: accepted a stale invocation pane' >&2; exit 1
fi
printf '{"role":"assistant","content":"Kimi fixture answer"}\n' > "$TMPDIR_TEST/kimi.jsonl"
NO_COLOR=1 "$TOOLKIT_ROOT/skills/delegate-cli/assets/view.sh" "$TMPDIR_TEST/kimi.jsonl" > "$TMPDIR_TEST/kimi.out"
assert_grep 'Kimi fixture answer' "$TMPDIR_TEST/kimi.out" 'Kimi answers render'
echo "PASS [$_TEST_NAME]"
