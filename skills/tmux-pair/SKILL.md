---
name: tmux-pair
description: >-
  Share Anton's tmux session as one cockpit: read any pane he names, run code
  in a shared IPython or R REPL whose state you both keep, and run commands in
  r2 windows he can watch and steer. Use when he says "look at pane N", asks to
  share a REPL, or wants a run he can see.
license: MIT
---

# Share the tmux session

The orchestrator runs inside the pilot's tmux session (`$TMUX` is set, `$TMUX_PANE` names its own
pane). Every pane in that session is one shared environment: the pilot sees and types into it, and
the agent reads it and writes to the windows it owns. `scripts/r2.sh` is the agent's half; resolve it
relative to this `SKILL.md`.

## Roles

| | Pilot | Agent (R2) |
|---|---|---|
| Owns | every window, by default | windows named `r2*` |
| Reads | everything | any pane, when the pilot names it or the task needs it |
| Writes | everywhere | `r2*` windows, plus panes the pilot hands over in chat |

The pilot hands over a pane by saying so in the conversation; the agent then runs
`r2.sh hand TARGET` and writes to it. `r2.sh unhand TARGET` returns it. The script's guard catches
slips: it writes to `r2*` windows and handed panes, and refuses the agent's own pane and a handed
pane the pilot is focused on. Consent itself lives in the chat.

## Read a pane

```bash
"$skill_dir/scripts/r2.sh" peek main:2.4 60
```

"Look at pane 2" replaces copy-pasting a traceback or a log. `peek` prints the last lines of the pane
as plain text, with wrapped lines joined. Take the tail the question needs: every line read enters
the context. Anything visible in the pane, a token included, enters it too.

Targets use tmux syntax: `main:2` is window 2's active pane, `main:2.4` is pane 4 of window 2, and
`main:r2` is the window named `r2`.

## Share a REPL

```bash
"$skill_dir/scripts/r2.sh" repl r2 python          # or: repl r2-r r
"$skill_dir/scripts/r2.sh" run main:r2 600 <<'EOF'
adata = sc.read_h5ad("03_results/objects/lung.h5ad")
print(adata)
EOF
```

`run` pastes the block as one bracketed paste, then sends a second cell that signals a tmux wait-for
channel. It returns when the signal arrives and prints only the lines the block produced. A block
that raises still signals, because the signal is its own cell. A heavy object loaded once serves
both of you: the pilot types `adata.obs.head()` in the same window, and the agent's next block sees
whatever the pilot defined.

On timeout `run` exits 124 and prints what the pane holds so far; the block keeps running. Take turns
in a shared window: a block sent while the pilot is mid-line interleaves with the pilot's keystrokes.

## Attend a milestone stage

A milestone compute stage is one whose details the pilot wants to follow as they happen: SCENIC+,
scVI or scANVI training, a deep-learning loop, a long peak or motif scan. It runs in a watched window
by default, so the pilot can ask about specifics while they are on screen and shape the run.

```bash
"$skill_dir/scripts/r2.sh" sh r2-30_scvi /workspaces/Meta-Aging/14782-DM
"$skill_dir/scripts/r2.sh" run main:r2-30_scvi 7200 <<<'python 02_analysis/stages/30_scvi.py 2>&1 | tee logs/30_scvi.log'
```

1. Before the launch, tell the pilot the window name, what the stage computes, the run length you
   expect, and the signals worth watching: loss and ELBO per epoch, module counts, peak counts,
   memory.
2. Run `run` as a harness background task with a timeout longer than the stage, so the harness
   notifies when the signal arrives.
3. When the pilot asks about the run, `peek` the window first and answer from what it shows: the
   epoch, the current loss, the warning on screen.
4. The pilot interrupts with Ctrl-C or types into the window; a changed parameter starts a new run.
5. Every stage `tee`s its output to a log file, so the record outlives the window.

Delegated workers follow the same pattern: an `r2-<stage>` window runs the launcher, and an
`r2-<stage>-log` window runs `tail -f` on the stream path the launcher prints (`delegate-cli`).

## Scratch and memory

A window, its scrollback and the wait-for channels are scratch, and they close with the run. The log
file, the stage's outputs and the reading the pilot and agent reach together are the record: the
reading goes into the stage-keyed note under `docs/_internal/`, and delegated runs keep their streams
in `_delegations/`.

## What the shared session gives, and its limits

- The agent perceives on its own turns. Between turns it rests until a `run` signal or a harness
  task wakes it.
- Full-screen programs (nvim, pi's TUI, htop) capture as a redrawn snapshot and read poorly. REPLs,
  shells and logs read cleanly.
- A block sent into a pane executes in the pilot's shell or kernel, outside the per-command review
  that the agent's own tool calls receive. Show the block in the tool call, keep it to what the task
  needs, and treat it with the care of a direct command.
- `r2.sh ls` lists the agent's windows and the handed panes. Close an agent window when its work is
  done: `tmux kill-window -t main:r2-train`.
