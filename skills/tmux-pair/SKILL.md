---
name: tmux-pair
description: >-
  Share the owner's tmux environment: inspect named panes, share a REPL, and
  place watched agents or compute in a paired jobs session. Use for work the
  owner wants to see or steer in tmux.
license: MIT
---

# Work beside the owner in tmux

Verify `$TMUX` and `$TMUX_PANE` against the live server before acting. A session
found on the machine alone does not establish that the owner is using tmux.
Outside tmux, work directly with ordinary harness delegation; create a tmux
workspace only on request. Small tasks stay in the primary conversation.
A worker's assigned role remains unchanged by being inside tmux.

## Jobs beside the project

`r2.sh` resolves the invocation pane's paired `<session>-jobs` session through
`tmux-jobs`, installed by dev-env rollout. Both sessions use the same server.
The owner presses `Ctrl-b W` to enter jobs and return, uses `Ctrl-b number` to
select a stream, `Ctrl-b ,` to rename it, and `Ctrl-b z` to zoom. Keep the owner's
focus and manual layouts. New jobs open in the background.

Windows group work streams. Panes hold individual agents, REPLs or compute.
Set `SCIO_STREAM=explorer` on related launches to group them in one window;
omitting it gives each job its own window. Set `SCIO_LABEL='reviewer · kimi · recorded'`
for a concise role/harness/mode label. Labels are metadata and survive application
terminal-title changes. Window renaming preserves job identity. No worktree is
created by this arrangement; use the directory the task requires.

```bash
SCIO_STREAM=explorer SCIO_LABEL='reviewer · kimi · recorded' \
  "$skill_dir/scripts/r2.sh" watch S02_review /workspaces/project
```

The helper prints `WINDOW=` and `PANE=`. Use the returned pane ID for subsequent
commands; pane indices can change. Opening the same job again reuses its pane.
`r2.sh ls` lists owned and handed panes. `r2.sh done S02_review` removes that job's
pane at acceptance. Closing a jobs pane also closes what runs in it; a watched
headless worker launched separately continues in its harness background task.
The jobs shell remains available when all watched jobs have been removed.

## Read and write

The owner owns all panes. The helper writes to panes it created and panes the
owner hands over in chat. A window name alone does not grant write access.
It refuses writes into the invocation pane and into a handed pane the owner is
currently viewing. Use `hand TARGET` after the owner hands over a pane and
`unhand TARGET` when returning it.

```bash
"$skill_dir/scripts/r2.sh" peek '%12' 40
"$skill_dir/scripts/r2.sh" hand '%12'
```

Read the tail needed to answer the question. Visible credentials enter the
reader's context too. Coordinate before sending input: pasting while the owner
is typing interleaves keystrokes. Full-screen TUIs capture as snapshots; shell
and REPL output are easier to inspect.

## Share a REPL

```bash
"$skill_dir/scripts/r2.sh" repl r2-inspect python  # or: repl r2-r r
"$skill_dir/scripts/r2.sh" run '%12' 600 <<'PY'
adata = sc.read_h5ad("03_results/objects/lung.h5ad")
print(adata)
PY
```

`run` pastes a block and a separate completion signal. A timeout exits 124 while
the computation continues. The REPL retains its state for both participants.
Pane input executes in that shell or kernel, outside the sending harness's
per-command review; keep it within the authorized task.

## Attend compute

```bash
SCIO_STREAM=annotation "$skill_dir/scripts/r2.sh" stage 30_scvi /workspaces/project 7200 \
  <<<'python 02_analysis/stages/30_scvi.py'
```

A milestone stage runs on a terminal, rendered by weight: tagged milestones in
bold cyan, errors in red, progress bars updated in place, repeated warnings
folded. The full plain log is kept under `logs/`. Announce the job, expected
runtime, and signals worth watching before launching. Run the helper as a harness
background task with sufficient timeout. It returns the tail, `STAGE=`, `PANE=`,
exit code and log path. Read the pane before answering questions about progress.
`run` also renders a one-line `CMD 2>&1 | tee LOG` through the stage renderer.

## Watch and communicate

`watch` follows a unit's recorded runs, waits if the first has not started, and
shows subsequent runs in the same pane. Launch headless workers separately using
`delegate-cli`. A recorded-output pane accepts no conversation; use the worker's
supported follow-up/resume mechanism. An interactive harness pane accepts direct
conversation. Label the mode accurately.

For agent messages, verify the actual destination pane and use the existing
project transport. Record consequential agreements in the existing ticket or
working note, then send a short pointer. A background listener does not guarantee
that an idle harness wakes; reconcile the record when resuming. Remote peers stay
in their own terminals and use the project's established transport.

Terminal scrollback is scratch. Logs, artifacts and accepted decisions supply
recovery after disconnect or context loss. A tmux server exit ends its processes;
records support recovery, not automatic process resurrection.
