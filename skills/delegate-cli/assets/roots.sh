# shellcheck shell=bash
# Where delegation runs live; sourced by launch.sh, pi.sh and status.sh so all three
# resolve one root. Runs persist in <outermost working tree>/_delegations; locks and the
# per-unit pointers stay in scratch, because locks key on live pids.

scratch_root="${TMPDIR:-/tmp}/scio-delegate"

# The outermost working tree above a directory: a linked worktree resolves to its main
# checkout, and a submodule to the superproject that holds it.
top_working_tree() {
    local top up
    top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
    if [ "$(git -C "$1" rev-parse --path-format=absolute --git-dir)" != \
         "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)" ]; then
        top=$(git -C "$1" worktree list --porcelain | sed -n '1s/^worktree //p')
    fi
    while up=$(git -C "$top" rev-parse --show-superproject-working-tree 2>/dev/null) && [ -n "$up" ]; do
        top="$up"
    done
    printf '%s\n' "$top"
}

# The durable root for a directory, or nothing when the directory sits outside a repository.
delegations_root() {
    local top
    if [ -n "${SCIO_DELEGATIONS:-}" ]; then
        printf '%s\n' "$SCIO_DELEGATIONS"
        return
    fi
    top=$(top_working_tree "$1") || return 0
    printf '%s/_delegations\n' "$top"
}

# A worker runs with SCIO_DELEGATION_RUN set, and every launcher refuses to start inside
# one: the agent the owner talks to orchestrates, and a worker does its brief itself.
refuse_nested() {
    [ -n "${SCIO_DELEGATION_RUN:-}" ] || return 0
    printf '%s: this process runs inside delegation %s. Delegation is one level deep:\n' "$1" "$SCIO_DELEGATION_RUN" >&2
    printf '%s: do the work yourself, and name any sub-task worth handing off in your report.\n' "$1" >&2
    exit 34
}

# Publish a run as its unit's newest: <unit>/current in the root, plus a scratch pointer
# that lets status.sh --unit find a durable run from any directory. Both are relative or
# absolute symlinks swapped in by rename(2), so a reader always finds one.
publish_run() {
    local run_root="$1" unit="$2" run_id="$3" pointer_dir="$scratch_root/$2"
    ln -s "$run_id" "$run_root/$unit/.current.$$" 2>/dev/null || return 0
    mv -Tf "$run_root/$unit/.current.$$" "$run_root/$unit/current" 2>/dev/null \
        || rm -f "$run_root/$unit/.current.$$"
    [ "$run_root" != "$scratch_root" ] || return 0
    mkdir -p "$pointer_dir" || return 0
    ln -s "$run_root/$unit/$run_id" "$pointer_dir/.current.$$" 2>/dev/null || return 0
    mv -Tf "$pointer_dir/.current.$$" "$pointer_dir/current" 2>/dev/null \
        || rm -f "$pointer_dir/.current.$$"
}

# Create a run directory under its root; a durable root ignores itself, so each project
# .gitignore stays as it is.
make_run_dir() {
    local run_root="$1" run_dir="$2"
    mkdir -p "$run_dir"
    [ "$run_root" = "$scratch_root" ] || [ -e "$run_root/.gitignore" ] || printf '*\n' > "$run_root/.gitignore"
}
