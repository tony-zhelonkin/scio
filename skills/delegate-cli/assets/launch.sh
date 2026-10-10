#!/usr/bin/env bash

set -eu

usage() {
    echo "usage: launch.sh --unit NAME --workdir DIR --prompt FILE [options]" >&2
    echo "options: --rules FILE --model MODEL --effort LEVEL --sandbox MODE --bypass --web" >&2
    echo "  no sandbox by default (-s danger-full-access); --sandbox opts back in" >&2
    echo "  --effort rides -c model_reasoning_effort; codex exec has no effort flag" >&2
    echo "         --expect PATH [--expect PATH ...] --parallel-ok" >&2
    echo "         --resume | --fork-from UNIT" >&2
    echo "  --resume sends the prompt as a follow-up turn on this unit's codex thread" >&2
    echo "  --fork-from starts this unit as a copy of another unit's thread" >&2
}

fail() {
    code="$1"
    shift
    printf 'launch.sh: %s\n' "$*" >&2
    exit "$code"
}

shell_value() {
    printf '%q' "$1"
}

unit=
workdir=
prompt=
rules=
model=
effort=
sandbox=
bypass=0
want_web=0
parallel_ok=0
resume=0
fork_from=
expects=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --unit)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            unit="$2"
            shift 2
            ;;
        --workdir)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            workdir="$2"
            shift 2
            ;;
        --prompt)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            prompt="$2"
            shift 2
            ;;
        --rules)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            rules="$2"
            shift 2
            ;;
        --model)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            model="$2"
            shift 2
            ;;
        --effort)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            effort="$2"
            shift 2
            ;;
        --sandbox)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            sandbox="$2"
            shift 2
            ;;
        --bypass)
            bypass=1
            shift
            ;;
        --web)
            want_web=1
            shift
            ;;
        --expect)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            expects+=("$2")
            shift 2
            ;;
        --parallel-ok)
            parallel_ok=1
            shift
            ;;
        --resume)
            resume=1
            shift
            ;;
        --fork-from)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            fork_from="$2"
            shift 2
            ;;
        --bg)
            fail 2 "--bg has been removed; run the foreground launcher through the caller's background-task mechanism"
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

[ -n "$unit" ] || { usage; exit 2; }
case "$unit" in
    .|..|*[![:alnum:]_.-]*) fail 2 "unit must contain only letters, numbers, dot, underscore, or hyphen" ;;
esac
[ -n "$workdir" ] || { usage; exit 2; }
[ -d "$workdir" ] || fail 2 "workdir is not a directory: $workdir"
[ -n "$prompt" ] || { usage; exit 2; }
[ -f "$prompt" ] || fail 2 "prompt file is missing: $prompt"
[ -s "$prompt" ] || fail 2 "prompt file is empty: $prompt"
if [ -n "$rules" ] && [ ! -f "$rules" ]; then
    fail 2 "rules file is missing: $rules"
fi
if [ "$bypass" -eq 1 ] && [ -n "$sandbox" ]; then
    fail 2 "--bypass and --sandbox are mutually exclusive"
fi
if [ "$resume" -eq 1 ] && [ -n "$fork_from" ]; then
    fail 2 "--resume and --fork-from are mutually exclusive"
fi
origin=fresh
[ "$resume" -eq 0 ] || origin=resume
[ -z "$fork_from" ] || origin=fork
if [ "$origin" != fresh ] && [ -n "$rules" ]; then
    fail 2 "--rules is for a fresh thread; a $origin thread already carries its rules"
fi
workdir=$(cd "$workdir" && pwd -P)

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ "$want_web" -eq 1 ]; then
    probe_args=(--workdir "$workdir" --web)
    [ -z "$model" ] || probe_args+=(--model "$model")
    [ -z "$sandbox" ] || probe_args+=(--sandbox "$sandbox")
    set +e
    probe_output=$("$script_dir/probe.sh" "${probe_args[@]}" 2>&1)
    probe_status=$?
    set -e
    if [ "$probe_status" -ne 0 ]; then
        printf '%s\n' "$probe_output" >&2
        exit "$probe_status"
    fi
    printf '%s\n' "$probe_output" | grep -q '^WEB_MODE=config_enable$' \
        || fail 13 "probe did not authorize the configured web-search mechanism"
fi

run_root="${TMPDIR:-/tmp}/scio-delegate"

# A unit's thread and workdir, from its newest run. Runs recorded before the
# launcher kept these files still carry both in the codex banner.
recorded_thread() {
    local dir="$run_root/$1/current"
    if [ -s "$dir/thread" ]; then
        cat "$dir/thread"
    elif [ -f "$dir/stream.log" ]; then
        sed -n 's/^session id: *//p' "$dir/stream.log" | head -n 1
    fi
}

recorded_workdir() {
    local dir="$run_root/$1/current"
    if [ -s "$dir/workdir" ]; then
        cat "$dir/workdir"
    elif [ -f "$dir/stream.log" ]; then
        sed -n 's/^workdir: *//p' "$dir/stream.log" | head -n 1
    fi
}

# A continued thread keeps its workdir: the cached context describes that tree.
source_thread=
if [ "$origin" != fresh ]; then
    source_unit="$unit"
    [ "$origin" = resume ] || source_unit="$fork_from"
    source_thread=$(recorded_thread "$source_unit")
    [ -n "$source_thread" ] || fail 2 "unit $source_unit has no recorded codex thread to $origin"
    source_workdir=$(recorded_workdir "$source_unit")
    [ ! -d "$source_workdir" ] || source_workdir=$(cd "$source_workdir" && pwd -P)
    if [ -n "$source_workdir" ] && [ "$source_workdir" != "$workdir" ]; then
        fail 2 "unit $source_unit ran in $source_workdir; a $origin must use the same --workdir"
    fi
fi

# This run's own thread: a resume continues its source, a fork gets a new one.
thread=
[ "$origin" != resume ] || thread="$source_thread"

lock_root="$run_root/locks"
mkdir -p "$lock_root"
lock="$lock_root/$unit.lock"

lock_pid_live() {
    candidate_lock="$1"
    candidate_pid=
    if [ -r "$candidate_lock/pid" ]; then
        IFS= read -r candidate_pid < "$candidate_lock/pid" || true
    fi
    case "$candidate_pid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    kill -0 "$candidate_pid" 2>/dev/null
}

clear_dead_lock() {
    dead_lock="$1"
    rm -f "$dead_lock/pid" 2>/dev/null || true
    rmdir "$dead_lock" 2>/dev/null || true
}

if ! mkdir "$lock" 2>/dev/null; then
    if lock_pid_live "$lock"; then
        fail 20 "unit is already active: $unit"
    fi
    clear_dead_lock "$lock"
    mkdir "$lock" 2>/dev/null || fail 20 "unit lock cannot be acquired: $unit"
fi
printf '%s\n' "$$" > "$lock/pid"

release_lock() {
    rm -f "$lock/pid" 2>/dev/null || true
    rmdir "$lock" 2>/dev/null || true
}
trap 'release_lock' EXIT HUP INT TERM

for candidate_lock in "$lock_root"/*.lock; do
    [ -d "$candidate_lock" ] || continue
    [ "$candidate_lock" != "$lock" ] || continue
    if lock_pid_live "$candidate_lock"; then
        if [ "$parallel_ok" -ne 1 ]; then
            fail 21 "another delegation unit is active; use --parallel-ok only for disjoint work"
        fi
    else
        clear_dead_lock "$candidate_lock"
        if [ -d "$candidate_lock" ] && [ "$parallel_ok" -ne 1 ]; then
            fail 21 "another delegation lock has no verifiable live pid: $candidate_lock"
        fi
    fi
done

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_dir="$run_root/$unit/$run_id"
mkdir -p "$run_dir"
rendered="$run_dir/prompt.md"
final="$run_dir/final.md"
stream="$run_dir/stream.log"
status_file="$run_dir/status.tsv"
pid_file="$run_dir/pid"
thread_file="$run_dir/thread"
printf '%s\n' "$workdir" > "$run_dir/workdir"
[ -z "$thread" ] || printf '%s\n' "$thread" > "$thread_file"

if [ -n "$rules" ]; then
    cat "$rules" "$prompt" > "$rendered"
else
    cat "$prompt" > "$rendered"
fi

expect_paths=()
for expected in "${expects[@]}"; do
    case "$expected" in
        /*) expect_paths+=("$expected") ;;
        *) expect_paths+=("$workdir/$expected") ;;
    esac
done


# The unit's `current` symlink points at the newest run, so a reader that knows
# only the unit name can find it. Relative, so the tree survives being moved,
# and replaced by rename(2) so a reader never observes it absent.
unit_dir="$run_root/$unit"
publish_current() {
    ln -s "$run_id" "$unit_dir/.current.$$" 2>/dev/null || return 0
    mv -Tf "$unit_dir/.current.$$" "$unit_dir/current" 2>/dev/null \
        || rm -f "$unit_dir/.current.$$"
}

print_paths() {
    printf 'RUN_DIR=%s\n' "$(shell_value "$run_dir")"
    printf 'PROMPT=%s\n' "$(shell_value "$rendered")"
    printf 'FINAL=%s\n' "$(shell_value "$final")"
    printf 'STREAM=%s\n' "$(shell_value "$stream")"
    printf 'STATUS=%s\n' "$(shell_value "$status_file")"
    printf 'PID_FILE=%s\n' "$(shell_value "$pid_file")"
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

now_epoch() {
    date -u +%s
}

# Roles are fixed so a reader can key on them: prompt, stream and final are the
# launcher's own files, expect the caller's declared outputs.
artifact_roles=(prompt stream final)
artifact_paths=("$rendered" "$stream" "$final")
for measured_path in ${expect_paths[@]+"${expect_paths[@]}"}; do
    artifact_roles+=(expect)
    artifact_paths+=("$measured_path")
done

# Baselines are taken once, before Codex starts, so a reader can tell an output
# this run produced from one that was already on disk.
baseline_bytes=()
baseline_mtime=()
for measured_path in "${artifact_paths[@]}"; do
    baseline_bytes+=("$(path_bytes "$measured_path")")
    baseline_mtime+=("$(path_mtime "$measured_path")")
done

# A fingerprint of every artifact's size and mtime. When it changes, the run did
# something observable, which is what last_activity_epoch records.
fingerprint() {
    local i out=
    for i in "${!artifact_paths[@]}"; do
        out="$out$(path_bytes "${artifact_paths[$i]}"):$(path_mtime "${artifact_paths[$i]}")|"
    done
    printf '%s' "$out"
}

start_epoch=$(now_epoch)
last_activity_epoch="$start_epoch"
last_fingerprint=$(fingerprint)

# One atomic snapshot: written to a sibling temporary file and renamed, so a
# reader either sees the previous complete record or this one, never a partial.
STATUS_SCHEMA=1
write_status() {
    local state="$1" child="$2" codex_exit="$3" result_exit="$4" terminal="$5"
    local tmp="$status_file.tmp.$$" i
    {
        printf 'schema\t%s\n' "$STATUS_SCHEMA"
        printf 'unit\t%s\n' "$unit"
        printf 'run_id\t%s\n' "$run_id"
        printf 'state\t%s\n' "$state"
        printf 'launcher_pid\t%s\n' "$$"
        printf 'child_pid\t%s\n' "$child"
        printf 'start_epoch\t%s\n' "$start_epoch"
        printf 'sample_epoch\t%s\n' "$(now_epoch)"
        printf 'last_activity_epoch\t%s\n' "$last_activity_epoch"
        printf 'terminal_epoch\t%s\n' "$terminal"
        printf 'codex_exit\t%s\n' "$codex_exit"
        printf 'result_exit\t%s\n' "$result_exit"
        printf 'origin\t%s\n' "$origin"
        printf 'thread\t%s\n' "${thread:--}"
        for i in "${!artifact_paths[@]}"; do
            printf 'artifact\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "${artifact_roles[$i]}" \
                "$(path_bytes "${artifact_paths[$i]}")" \
                "$(path_mtime "${artifact_paths[$i]}")" \
                "${baseline_bytes[$i]}" \
                "${baseline_mtime[$i]}" \
                "${artifact_paths[$i]}"
        done
    } > "$tmp"
    mv -f "$tmp" "$status_file"
}

# A fresh or forked thread is named in the codex banner once the child starts.
capture_thread() {
    [ "$origin" != resume ] || return 0
    [ ! -s "$thread_file" ] || return 0
    local seen
    seen=$(sed -n 's/^session id: *//p' "$stream" 2>/dev/null | head -n 1)
    [ -n "$seen" ] || return 0
    thread="$seen"
    printf '%s\n' "$thread" > "$thread_file"
}

refresh_activity() {
    local current
    current=$(fingerprint)
    if [ "$current" != "$last_fingerprint" ]; then
        last_fingerprint="$current"
        last_activity_epoch=$(now_epoch)
    fi
}

print_bytes() {
    local i
    for i in "${!artifact_paths[@]}"; do
        printf 'BYTES\t%s\t%s\n' "$(path_bytes "${artifact_paths[$i]}")" "${artifact_paths[$i]}"
    done
}

# Fixed cadence. A tunable would be a knob whose only effect is how stale a
# reader's answer may be, and the reader already reports that as heartbeat age.
HEARTBEAT_S=2

# No sandbox unless one is asked for. Codex invokes bwrap only to enforce a
# sandbox, and bwrap cannot create a namespace in these containers — so an
# enforced sandbox means every file tool fails while codex still exits 0, and the
# worker writes about a repository it never read. The container is the boundary
# instead (owner ruling, 2026-08-25). Pass --sandbox to opt back in.
DEFAULT_SANDBOX=danger-full-access

# The model delegations run on. Named here rather than left to whatever the
# host config happens to carry, so a fan-out is reproducible across machines
# whose ~/.codex/config.toml differ. A newer model can outrun the installed
# CLI: the server then refuses it by name, which run_codex classifies below.
DEFAULT_MODEL=gpt-6-astra

run_codex() {
    # resume and fork accept neither -C nor -s, so they run from the workdir and
    # get the sandbox through -c; left unset, it comes from ~/.codex/config.toml.
    local codex_args=(exec)
    case "$origin" in
        fresh) codex_args+=(-C "$workdir") ;;
        *)     codex_args+=("$origin") ;;
    esac
    codex_args+=(--skip-git-repo-check -o "$final")
    codex_args+=(-m "${model:-$DEFAULT_MODEL}")
    [ -z "$effort" ] || codex_args+=(-c "model_reasoning_effort=$effort")
    if [ "$bypass" -ne 1 ] && [ "$origin" = fresh ]; then
        codex_args+=(-s "${sandbox:-$DEFAULT_SANDBOX}")
    elif [ "$bypass" -ne 1 ]; then
        codex_args+=(-c "sandbox_mode=\"${sandbox:-$DEFAULT_SANDBOX}\"")
    fi
    [ "$bypass" -ne 1 ] || codex_args+=(--dangerously-bypass-approvals-and-sandbox)
    if [ "$want_web" -eq 1 ]; then
        codex_args+=(-c tools.web_search=true --enable web_search_request)
    fi
    # Plugin skills load in a race with the first request, so the skills
    # catalog would differ run to run and a resume would re-send all of it.
    codex_args+=(--disable plugins)
    [ "$origin" = fresh ] || codex_args+=("$source_thread")

    write_status starting - - - -

    (cd "$workdir" && exec codex "${codex_args[@]}" -) < "$rendered" > "$stream" 2>&1 &
    local child_pid=$!
    printf '%s\n' "$child_pid" > "$pid_file"
    write_status running "$child_pid" - - -

    # Status is written while the child runs, not only once it is reaped: an
    # in-flight question is the one a reader actually has.
    while kill -0 "$child_pid" 2>/dev/null; do
        sleep "$HEARTBEAT_S"
        capture_thread
        refresh_activity
        write_status running "$child_pid" - - -
    done

    local codex_status=0
    set +e
    wait "$child_pid"
    codex_status=$?
    set -e

    local result_status="$codex_status"

    # A sandbox that cannot open files does not make codex fail; it makes codex
    # answer from the prompt alone and exit 0. Measured in a v0.5.10 container:
    # bwrap cannot create a namespace, every file tool fails, exit status 0. So
    # the stream is the evidence, and a run carrying that denial cannot be
    # reported as a success whatever the child returned — its output was written
    # without reading the repository. Only an enforced sandbox can deny: without
    # one, a match is file content the worker read, such as a doc naming bwrap.
    local sandbox_enforced=0
    if [ "$bypass" -ne 1 ] && [ "${sandbox:-$DEFAULT_SANDBOX}" != danger-full-access ]; then
        sandbox_enforced=1
    fi
    if [ "$sandbox_enforced" -eq 1 ] \
            && LC_ALL=C grep -Eqi 'bwrap|landlock|new namespace|sandbox helper' "$stream" 2>/dev/null; then
        if [ "$result_status" -eq 0 ]; then
            result_status=32
        fi
        printf 'launch.sh: the sandbox blocked file access; this output was written blind.\n' >&2
        printf 'launch.sh: relaunch with --sandbox danger-full-access, or fix the container policy.\n' >&2
    fi

    # A model the installed CLI is too old for is refused by the server, by
    # name, after launch. The raw 400 reads as a generic API failure, so name
    # the remedy: the model is real, this codex is behind it.
    if LC_ALL=C grep -Eqi 'requires a newer version of Codex' "$stream" 2>/dev/null; then
        if [ "$result_status" -eq 0 ]; then
            result_status=33
        fi
        printf 'launch.sh: %s needs a newer codex than this one (%s).\n' \
            "${model:-$DEFAULT_MODEL}" "$(codex --version 2>/dev/null || echo unknown)" >&2
        printf 'launch.sh: upgrade the CLI, or pass --model with one this version serves.\n' >&2
    fi

    if [ ! -s "$final" ] && [ "$result_status" -eq 0 ]; then
        result_status=30
    fi
    for measured_path in ${expect_paths[@]+"${expect_paths[@]}"}; do
        if [ ! -e "$measured_path" ] && [ "$result_status" -eq 0 ]; then
            result_status=31
        fi
    done

    capture_thread
    refresh_activity
    local state=succeeded
    [ "$result_status" -eq 0 ] || state=failed
    write_status "$state" "$child_pid" "$codex_status" "$result_status" "$(now_epoch)"

    print_bytes
    printf 'THREAD=%s\n' "$(shell_value "${thread:--}")"

    # The final message is the deliverable, so the run that produced it prints
    # it. A caller that wanted only the machine-readable head can stop at the
    # marker; the file stays either way.
    if [ -s "$final" ]; then
        printf -- '--- FINAL MESSAGE ---\n'
        cat "$final"
        printf '\n'
    fi

    return "$result_status"
}

print_paths
printf 'PROMPT_BYTES=%s\n' "$(path_bytes "$rendered")"

printf '%s\n' "$$" > "$pid_file"
write_status starting - - - -
publish_current

# A launcher killed mid-run leaves state=running with a frozen heartbeat, which
# is the honest record. A signal it can catch is recorded as interrupted.
on_signal() {
    write_status interrupted - - 130 "$(now_epoch)"
    release_lock
    exit 130
}
trap 'on_signal' HUP INT TERM

if run_codex; then
    run_status=0
else
    run_status=$?
fi
exit "$run_status"
