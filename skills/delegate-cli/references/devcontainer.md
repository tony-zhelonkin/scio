# The devcontainer

Work runs in Docker devcontainers, from a raw terminal or from a tmux session inside one. These facts
shape every hand-off, whichever worker takes it.

## Mounts and namespaces

| Fact | Consequence |
|---|---|
| The container blocks unprivileged user namespaces | bwrap fails to start, so codex runs unsandboxed and the container is the boundary (`references/codex.md`) |
| Workspaces are host bind mounts | an unsandboxed worker reaches everything under its workdir, so scope the workdir |
| `/tmp` and `/dev/shm` are mounted `noexec` | a script there runs as `bash script.sh`; a direct call exits 126 even with the executable bit set |
| `/dev/shm` holds 64 MB until a rebuild applies `shm_size` | marimo kernels and workers share it; read `df -h /dev/shm` first |
| One RTX 5000 Ada serves the container, and the qwen model occupies most of it | GPU training starts after the user unloads the model (`references/pi-ollama.md`) |
| `$OLLAMA_HOST` points at the host's Ollama | pi's model lives on the host and survives a container rebuild |

## Worktrees for writing workers

Each writing worker gets its own detached worktree. A dataset checkout can run to gigabytes, so the
worktree is sparse and checks out the paths the task reads:

```bash
repo=/workspaces/Meta-Aging/14761-DM; wt="$scratch/bench/$unit"
git -C "$repo" worktree add --no-checkout --detach "$wt" HEAD
git -C "$wt" sparse-checkout set --cone 02_analysis docs
git -C "$wt" checkout -q
```

- Create the worktree in the repository that owns the code. A submodule is its own repository, and a
  superproject worktree holds each submodule as an empty directory.
- A fresh worktree lacks the gitignored links a setup step creates. In a scio project,
  `sciagent activate` links `02_analysis/helpers/figure-style`, and tests that import
  `helpers.figure_style` need it to collect. Recreate the link before running the acceptance tests:
  `ln -sfn "$repo/01_modules/scio/lib/figure-style" "$wt/02_analysis/helpers/figure-style"`.
- A sparse tree omits `03_results/`. Tell an exploration worker, or add the paths it must read.
- Remove a worktree once its result is accepted: `git -C "$repo" worktree remove --force "$wt"`.

## Terminal and tmux

The orchestrator itself often runs inside tmux, and `$TMUX` is set when it does. A worker runs in one
of three ways:

| Need | Run |
|---|---|
| The orchestrator waits on the result | a harness background task; the harness notifies on exit |
| The owner watches live, and the orchestrator gets a completion signal | an `r2*` window driven by `tmux-pair` |
| The owner runs it by hand | `! <command>` in the prompt, in the foreground |

The `tmux-pair` skill holds the shared-session conventions: reading the owner's panes, a shared REPL,
and `r2*` windows the owner can watch. Its `r2.sh run` waits on a tmux wait-for channel, so a worker
in a watched window still gives the orchestrator a completion signal. Write the worker's output to a
file as well, because a window's scrollback closes with the window.
