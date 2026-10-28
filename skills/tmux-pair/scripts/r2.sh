#!/usr/bin/env bash
#
# The agent's half of a shared tmux session. It reads any pane, owns the windows
# named r2*, and writes to a pilot's pane only after the pilot hands it over.
# Every write waits on a tmux wait-for channel, so a caller learns the moment a
# cell or command finishes and reads back only the output that cell produced.

set -eu

usage() {
    cat >&2 <<'EOF'
usage: r2.sh peek TARGET [LINES]       last LINES (default 40) of any pane, wrapped lines joined
       r2.sh repl NAME [python|r]      open window NAME (r2*) running IPython or R; reuses a live one
       r2.sh sh NAME [DIR]             open window NAME (r2*) running a shell in DIR
       r2.sh run TARGET [TIMEOUT]      paste stdin into TARGET as one block, wait, print its new output
       r2.sh hand TARGET               mark a pilot's pane writable, after the pilot hands it over
       r2.sh unhand TARGET             return a handed pane to the pilot
       r2.sh ls                        list r2 windows and handed panes
EOF
}

die() { echo "r2.sh: $*" >&2; exit 2; }

[ -n "${TMUX:-}" ] || die "run inside tmux: \$TMUX is unset"

field() { tmux display-message -p -t "$1" "$2"; }

kind_of() {
    local k
    k=$(tmux show-options -pqv -t "$1" @r2_kind)
    [ -n "$k" ] && { echo "$k"; return; }
    case "$(field "$1" '#{pane_current_command}')" in
        ipython*|python*) echo python ;;
        R|radian) echo r ;;
        *) echo shell ;;
    esac
}

prompt_ready() {
    local target="$1" kind="$2" pattern i
    case "$kind" in
        python) pattern='In \[[0-9]+\]: *$' ;;
        r) pattern='^(> |r\$> ) *$' ;;
        *) pattern='[$#] *$' ;;
    esac
    for i in $(seq 1 40); do
        tmux capture-pane -p -t "$target" | grep -Eq "$pattern" && return 0
        sleep 0.5
    done
    die "$target showed no $kind prompt within 20 s"
}

writable() {
    local target="$1" name pane focus
    pane=$(field "$target" '#{pane_id}')
    [ "$pane" != "${TMUX_PANE:-}" ] || die "$target is the agent's own pane"
    name=$(field "$target" '#{window_name}')
    case "$name" in r2*) return 0 ;; esac
    [ "$(tmux show-options -pqv -t "$target" @r2_handed)" = 1 ] \
        || die "$target belongs to the pilot; ask, then: r2.sh hand $target"
    focus=$(field "$target" '#{pane_active}#{window_active}#{session_attached}')
    case "$focus" in 11[1-9]*) die "the pilot is focused on $target; wait or ask" ;; esac
}

paste() {
    printf '%s' "$2" | tmux load-buffer -b r2buf -
    tmux paste-buffer -p -d -b r2buf -t "$1"
    tmux send-keys -t "$1" Enter
}

signal_line() {
    case "$1" in
        python) echo "_r2s = __import__('subprocess').run(['tmux', 'wait-for', '-S', '$2'])" ;;
        r) echo "invisible(system('tmux wait-for -S $2'))" ;;
        *) echo "tmux wait-for -S $2" ;;
    esac
}

open_window() {
    local name="$1" kind="$2" dir="$3"
    shift 3
    case "$name" in r2*) ;; *) die "agent windows are named r2*: got $name" ;; esac
    if tmux list-windows -F '#{window_name}' | grep -qx "$name"; then
        prompt_ready "$name" "$kind"
        echo "WINDOW=$name reused"
        return
    fi
    tmux new-window -d -n "$name" -c "$dir" "$@"
    tmux set-option -p -t "$name" @r2_kind "$kind"
    prompt_ready "$name" "$kind"
    echo "WINDOW=$name kind=$kind"
}

cmd_run() {
    local target="$1" timeout="${2:-600}" code kind ch start now from rc
    writable "$target"
    code=$(cat)
    [ -n "$code" ] || die "run reads the block from stdin, and stdin was empty"
    kind=$(kind_of "$target")
    ch="r2-$$-$(date +%s%N)"
    start=$(( $(field "$target" '#{history_size}') + $(field "$target" '#{cursor_y}') ))
    paste "$target" "$code"
    paste "$target" "$(signal_line "$kind" "$ch")"
    rc=0
    timeout "$timeout" tmux wait-for "$ch" || rc=$?
    now=$(field "$target" '#{history_size}')
    from=$(( start - now ))
    tmux capture-pane -p -J -t "$target" -S "$from" \
        | grep -v -- "$ch" \
        | cat -s | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
    [ "$rc" = 0 ] || { echo "r2.sh: no signal within ${timeout} s; the block may still be running" >&2; exit 124; }
}

verb="${1:-}"
[ -n "$verb" ] || { usage; exit 2; }
shift

case "$verb" in
    peek)
        [ $# -ge 1 ] || { usage; exit 2; }
        tmux capture-pane -p -J -t "$1" -S "-${2:-40}" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' | tail -n "${2:-40}"
        ;;
    repl)
        [ $# -ge 1 ] || { usage; exit 2; }
        case "${2:-python}" in
            python) open_window "$1" python "${PWD}" /opt/venvs/base/bin/ipython --no-banner ;;
            r) open_window "$1" r "${PWD}" R --no-save --quiet ;;
            *) die "repl kinds are python and r: got $2" ;;
        esac
        ;;
    sh)
        [ $# -ge 1 ] || { usage; exit 2; }
        open_window "$1" shell "${2:-$PWD}" bash
        ;;
    run)
        [ $# -ge 1 ] || { usage; exit 2; }
        cmd_run "$@"
        ;;
    hand)
        [ $# -eq 1 ] || { usage; exit 2; }
        tmux set-option -p -t "$1" @r2_handed 1
        echo "HANDED=$(field "$1" '#{session_name}:#{window_index}.#{pane_index}') cmd=$(field "$1" '#{pane_current_command}')"
        ;;
    unhand)
        [ $# -eq 1 ] || { usage; exit 2; }
        tmux set-option -p -u -t "$1" @r2_handed
        echo "UNHANDED=$1"
        ;;
    ls)
        tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{window_name} #{pane_current_command} kind=#{@r2_kind} handed=#{@r2_handed}' \
            | awk '$2 ~ /^r2/ || $NF == "handed=1"'
        ;;
    -h|--help) usage ;;
    *) usage; exit 2 ;;
esac
