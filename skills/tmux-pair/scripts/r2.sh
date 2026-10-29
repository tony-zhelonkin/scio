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
       r2.sh stage NAME [DIR] [TIMEOUT] run the stdin command in r2-NAME, rendered by weight, logged to DIR/logs/NAME.log
       r2.sh watch UNIT [DIR]          open window r2-UNIT rendering the delegation's stream as it grows
       r2.sh done NAME                 close window r2-NAME once the run or stage is accepted
       r2.sh hand TARGET               mark a pilot's pane writable, after the pilot hands it over
       r2.sh unhand TARGET             return a handed pane to the pilot
       r2.sh ls                        list r2 windows, each watched unit with its state, and handed panes
EOF
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VIEW="$script_dir/../../delegate-cli/assets/view.sh"
STATUS="$script_dir/../../delegate-cli/assets/status.sh"
STAGE="$script_dir/stage.py"
TEE_RE='^[[:space:]]*(.*[^[:space:]])[[:space:]]*(2>&1[[:space:]]*\||\|&)[[:space:]]*tee[[:space:]]+(-a[[:space:]]+)?([^[:space:]|;&]+)[[:space:]]*$'

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

# One run, one window: r2-UNIT shows the rendered stream and stays until `done`.
cmd_watch() {
    local unit="$1" dir="${2:-$PWD}" name="r2-$1"
    [ -x "$VIEW" ] || die "view.sh is missing beside this skill: $VIEW"
    if tmux list-windows -F '#{window_name}' | grep -qx "$name"; then
        echo "WINDOW=$name reused"
        return
    fi
    tmux new-window -d -n "$name" -c "$dir" "$VIEW" --follow "$unit"
    tmux set-option -p -t "$name" @r2_kind watch
    tmux set-option -w -t "$name" @r2_unit "$unit"
    tmux set-option -w -t "$name" @r2_dir "$dir"
    echo "WINDOW=$name unit=$unit"
}

cmd_done() {
    local name="r2-$1"
    tmux list-windows -F '#{window_name}' | grep -qx "$name" || die "no window $name"
    tmux kill-window -t "$name"
    echo "CLOSED=$name"
}

unit_state() {
    local unit="$1" dir="$2"
    (cd "$dir" 2>/dev/null && "$STATUS" --unit "$unit" 2>/dev/null) \
        | sed -n '/^SUMMARY/s/.*\(state=[a-z]*\).*\(elapsed_s=[0-9]*\).*/\1 \2/p'
}

cmd_ls() {
    local line unit dir
    tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{window_name} #{pane_current_command} kind=#{@r2_kind} unit=#{@r2_unit} dir=#{@r2_dir} handed=#{@r2_handed}' \
        | awk '$2 ~ /^r2/ || $NF == "handed=1"' \
        | while read -r line; do
            unit=$(printf '%s\n' "$line" | sed -n 's/.* unit=\([^ ]*\) .*/\1/p')
            dir=$(printf '%s\n' "$line" | sed -n 's/.* dir=\([^ ]*\) .*/\1/p')
            line=$(printf '%s\n' "$line" | sed 's/ dir=[^ ]*//')
            if [ -n "$unit" ]; then
                printf '%s %s\n' "$line" "$(unit_state "$unit" "$dir")"
            else
                printf '%s\n' "$line" | sed 's/ unit= / /'
            fi
        done
}

# A delegation stream is read through view.sh: a block that tails one raw becomes the rendered follow.
read_stream_with_view() {
    local block="$1" path
    path=$(printf '%s\n' "$block" | sed -n '1{s/^[[:space:]]*tail[[:space:]]\+\(-[a-zA-Z0-9 ]\+[[:space:]]\+\)*\(.*\/_delegations\/.*\/stream\.\(log\|jsonl\)\)[[:space:]]*$/\2/p;}')
    if [ -n "$path" ] && [ "$(printf '%s\n' "$block" | grep -c .)" = 1 ] && [ -x "$VIEW" ]; then
        echo "r2.sh: a stream reads through view.sh; running: view.sh --follow $path" >&2
        printf '%s --follow %s\n' "$VIEW" "$path"
    else
        printf '%s\n' "$block"
    fi
}

# A one-line `CMD 2>&1 | tee LOG` runs through stage.py, which keeps CMD on a terminal and writes LOG.
read_tee_with_stage() {
    local block="$1" name
    if [ "$(printf '%s\n' "$block" | grep -c .)" = 1 ] && [[ $block =~ $TEE_RE ]]; then
        name=$(basename "${BASH_REMATCH[4]}" .log)
        echo "r2.sh: a stage runs through stage.py; running: stage.py --log ${BASH_REMATCH[4]} -- ${BASH_REMATCH[1]}" >&2
        printf '%q --name %q --log %q %s-- %q\n' "$STAGE" "$name" "${BASH_REMATCH[4]}" \
            "${BASH_REMATCH[3]:+--append }" "${BASH_REMATCH[1]}"
    else
        printf '%s\n' "$block"
    fi
}

# A milestone stage owns r2-NAME: stage.py renders it there, and the caller gets the tail and the exit.
cmd_stage() {
    local name="r2-${1#r2-}" dir="${2:-$PWD}" timeout="${3:-86400}" cmd log rc code
    cmd=$(cat)
    [ -n "$cmd" ] || die "stage reads the command from stdin, and stdin was empty"
    log="logs/${name#r2-}.log"
    if [ "$(printf '%s\n' "$cmd" | grep -c .)" = 1 ] && [[ $cmd =~ $TEE_RE ]]; then
        cmd="${BASH_REMATCH[1]}"
        log="${BASH_REMATCH[4]}"
    fi
    open_window "$name" shell "$dir" bash
    tmux set-option -p -t "$name" @r2_kind stage
    rc=0
    printf '%q --name %q --log %q -- %q\n' "$STAGE" "${name#r2-}" "$log" "$cmd" \
        | ( cmd_run "$name" "$timeout" ) > /dev/null || rc=$?
    tmux capture-pane -p -J -t "$name" -S -30 | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' | tail -n 30
    [ "$rc" = 0 ] || { echo "r2.sh: no exit within ${timeout} s; the stage is still running in $name" >&2; exit 124; }
    code=$(tmux capture-pane -p -J -t "$name" -S -30 | sed -n 's/^■ exit \([0-9]*\) .*/\1/p' | tail -n 1)
    echo "STAGE=$name exit=${code:-?} log=$dir/$log"
    exit "${code:-1}"
}

cmd_run() {
    local target="$1" timeout="${2:-600}" code kind ch start now from rc
    writable "$target"
    code=$(cat)
    [ -n "$code" ] || die "run reads the block from stdin, and stdin was empty"
    code=$(read_stream_with_view "$code")
    code=$(read_tee_with_stage "$code")
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
    stage)
        [ $# -ge 1 ] || { usage; exit 2; }
        cmd_stage "$@"
        ;;
    watch)
        [ $# -ge 1 ] || { usage; exit 2; }
        cmd_watch "$@"
        ;;
    done)
        [ $# -eq 1 ] || { usage; exit 2; }
        cmd_done "$1"
        ;;
    ls)
        cmd_ls
        ;;
    -h|--help) usage ;;
    *) usage; exit 2 ;;
esac
