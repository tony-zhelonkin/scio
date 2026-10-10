#!/usr/bin/env bash
#
# Read a delegation run's status. Read-only: it takes no prompt, performs none of
# the launcher's validations, acquires no lock, and can observe a run someone
# else started.
#
# It reports quantities and refuses to invent one. There is no phase, no
# percentage and no estimate of semantic completion, because nothing on disk
# supports them. Whether a run is hung or merely slow is a judgement the reader
# makes from heartbeat age, activity age and elapsed time.

set -eu

usage() {
    echo "usage: status.sh --unit NAME | --file STATUS_TSV [--wait]" >&2
}

fail() {
    code="$1"
    shift
    printf 'status.sh: %s\n' "$*" >&2
    exit "$code"
}

unit=
status_file=
wait_mode=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --unit)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            unit="$2"
            shift 2
            ;;
        --file)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            status_file="$2"
            shift 2
            ;;
        --wait)
            wait_mode=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if [ -n "$unit" ] && [ -n "$status_file" ]; then
    fail 2 "--unit and --file are mutually exclusive"
fi

if [ -n "$unit" ]; then
    case "$unit" in
        .|..|*[![:alnum:]_.-]*) fail 2 "unit must contain only letters, numbers, dot, underscore, or hyphen" ;;
    esac
    status_file="${TMPDIR:-/tmp}/scio-delegate/$unit/current/status.tsv"
fi

[ -n "$status_file" ] || { usage; exit 2; }

# 3 is "never started in this runtime root", distinct from 4, "started and the
# record is broken". Conflating them would hide a corrupt snapshot behind the
# same message as a typo in the unit name.
[ -e "$status_file" ] || fail 3 "no status for this unit in ${TMPDIR:-/tmp}/scio-delegate"
[ -r "$status_file" ] || fail 4 "status exists but is unreadable: $status_file"

now_epoch() {
    date -u +%s
}

path_bytes() {
    if [ -f "$1" ]; then
        wc -c < "$1" | tr -d '[:space:]'
    else
        printf '0'
    fi
}

path_mtime() {
    if [ -e "$1" ]; then
        stat -c %Y "$1" 2>/dev/null || printf '%s' '-'
    else
        printf '%s' '-'
    fi
}

# age <epoch> — seconds since an epoch field, or '-' when it was never set.
age() {
    case "$1" in
        ''|-|*[!0-9]*) printf '%s' '-' ;;
        *) printf '%s' "$(( $(now_epoch) - $1 ))" ;;
    esac
}

emit_snapshot() {
    local file="$1"
    local schema= unit_v= run_id= state= launcher_pid= child_pid=
    local start_epoch= sample_epoch= activity_epoch= terminal_epoch=
    local codex_exit= result_exit= origin= thread=
    local -a roles=() a_bytes=() a_mtime=() b_bytes=() b_mtime=() paths=()
    local key f2 f3 f4 f5 f6 f7

    # A single pass, keyed on field 1, so an unknown row is ignored rather than
    # shifting the parse. Artifact rows carry six fields, scalars carry one.
    while IFS=$'\t' read -r key f2 f3 f4 f5 f6 f7; do
        case "$key" in
            schema)              schema="$f2" ;;
            unit)                unit_v="$f2" ;;
            run_id)              run_id="$f2" ;;
            state)               state="$f2" ;;
            launcher_pid)        launcher_pid="$f2" ;;
            child_pid)           child_pid="$f2" ;;
            start_epoch)         start_epoch="$f2" ;;
            sample_epoch)        sample_epoch="$f2" ;;
            last_activity_epoch) activity_epoch="$f2" ;;
            terminal_epoch)      terminal_epoch="$f2" ;;
            codex_exit)          codex_exit="$f2" ;;
            result_exit)         result_exit="$f2" ;;
            origin)              origin="$f2" ;;
            thread)              thread="$f2" ;;
            artifact)
                roles+=("$f2"); a_bytes+=("$f3"); a_mtime+=("$f4")
                b_bytes+=("$f5"); b_mtime+=("$f6"); paths+=("$f7")
                ;;
        esac
    done < "$file"

    [ -n "$schema" ] || fail 4 "status has no schema row: $file"
    [ "$schema" = "1" ] || fail 4 "status schema $schema is not readable by this reader (expects 1)"
    [ -n "$state" ] || fail 4 "status has no state row: $file"

    # Artifacts are re-stat'ed rather than reported from the snapshot: the paths
    # are recorded, the read is free, and a caller asking mid-run wants the
    # current size. Baselines stay as recorded — they are what the run started
    # from and cannot be re-measured later.
    local i present=0 total=0 stream_bytes=0 final_bytes=0 live_bytes live_mtime
    local -a out_bytes=() out_mtime=()
    for i in "${!paths[@]}"; do
        live_bytes=$(path_bytes "${paths[$i]}")
        live_mtime=$(path_mtime "${paths[$i]}")
        out_bytes+=("$live_bytes"); out_mtime+=("$live_mtime")
        case "${roles[$i]}" in
            stream) stream_bytes="$live_bytes" ;;
            final)  final_bytes="$live_bytes" ;;
            expect)
                total=$(( total + 1 ))
                [ "$live_bytes" = "0" ] && [ "$live_mtime" = "-" ] || present=$(( present + 1 ))
                ;;
        esac
    done

    printf 'SUMMARY\tunit=%s\trun_id=%s\tstate=%s\tlauncher_pid=%s\tchild_pid=%s' \
        "$unit_v" "$run_id" "$state" "${launcher_pid:--}" "${child_pid:--}"
    printf '\telapsed_s=%s\theartbeat_age_s=%s\tactivity_age_s=%s' \
        "$(age "$start_epoch")" "$(age "$sample_epoch")" "$(age "$activity_epoch")"
    printf '\tstream_bytes=%s\tfinal_bytes=%s\texpected_present=%s/%s' \
        "$stream_bytes" "$final_bytes" "$present" "$total"
    printf '\tcodex_exit=%s\tresult_exit=%s' "${codex_exit:--}" "${result_exit:--}"
    printf '\torigin=%s\tthread=%s\n' "${origin:--}" "${thread:--}"

    for i in "${!paths[@]}"; do
        printf 'ARTIFACT\trole=%s\tbytes=%s\tmtime_epoch=%s\tbaseline_bytes=%s\tbaseline_mtime=%s\tpath=%s\n' \
            "${roles[$i]}" "${out_bytes[$i]}" "${out_mtime[$i]}" \
            "${b_bytes[$i]}" "${b_mtime[$i]}" "${paths[$i]}"
    done

    _STATUS_STATE="$state"
    _STATUS_RESULT="$result_exit"
}

read_state() {
    awk -F'\t' '$1 == "state" { print $2 }' "$1" 2>/dev/null | tail -n 1
}

if [ "$wait_mode" -eq 1 ]; then
    # Shadowing a run the harness does not own: this process is the background
    # task, and its exit is the wake-up. Fixed cadence, no timeout knob — the
    # caller that wants to stop waiting owns its own task.
    while :; do
        case "$(read_state "$status_file")" in
            succeeded|failed|interrupted) break ;;
        esac
        sleep 2
    done
fi

emit_snapshot "$status_file"

# The run's outcome, so a shadowing harness task fails when the run failed. A
# single read reports 0: it succeeded in reading, whatever the run did.
if [ "$wait_mode" -eq 1 ]; then
    case "${_STATUS_RESULT:-}" in
        ''|-|*[!0-9]*) exit 0 ;;
        *) exit "$_STATUS_RESULT" ;;
    esac
fi
exit 0
