---
name: delegate-cli
description: >-
  Choose, brief and verify a subagent in Anton's devcontainers: Claude Code
  agents, codex, agy, or local pi on ollama/qwen3.6:35b. Use before any
  hand-off, when Anton names a tool, or when a skill needs fan-out. Easy,
  verifiable, context-heavy work goes to pi; references hold each worker's
  flags, costs and container traps.
license: MIT
---

# Delegate to a subagent

A subagent is a worker that receives one prompt and returns one report. This body settles three
questions in order: whether to delegate, which worker takes the task, and how to brief and accept the
work. Each worker's mechanics live in its reference. Read that reference before the first hand-off to
that worker in a session.

| Worker | Runs as | Reference |
|---|---|---|
| Claude Code agents | the harness's Agent tool | `references/claude-code.md` |
| codex | `assets/launch.sh` around `codex exec` | `references/codex.md` |
| agy | `agy -p` headless print mode | `references/agy.md` |
| pi on qwen3.6:35b | `pi -p` against the host's Ollama, on the local GPU | `references/pi-ollama.md` |
| the container itself | devcontainer, raw terminal, tmux | `references/devcontainer.md` |

## Decide whether to delegate

Do the work yourself when it fits in a handful of tool calls, when you know the target, or when it is
a check you would run anyway. Delegate when one of these holds:

- the units are independent and can run in parallel;
- the answer requires reading across many files, and you need only the conclusion;
- a review must come from a fresh reader, so the reviewer receives the code and forms its own verdict;
- a side quest would otherwise block the main thread.

A hand-off has two costs: the worker's run and your verification. The worker's run is the larger. A
Claude agent writes 25–32k tokens to cache before its first file read, and your prompt is about 1% of
that. Dispatching and reading the report back costs you about a cent. A pi run costs local GPU time
alone, so its whole price is your verification.

## Choose the worker

A worker the user names takes the task. Otherwise the task decides. Two properties move work to a
cheaper worker: the result is easy to verify, and the task consumes a large amount of context, as
mapping a codebase or sweeping many files does. pi fits that work best, because its tokens cost local
GPU time alone. Judgement, diagnosis and claims that are expensive to check move work to a stronger
worker.

| Task | First choice | Stronger worker | Accept by |
|---|---|---|---|
| Locate code, list callers, map a blast radius | pi | Explore or Sonnet agent, when the answer goes out unchecked | grep each path it names |
| Scoped mechanical refactor: rename, extract a helper, apply one pattern | pi | Sonnet agent | your grader plus the test run |
| Complex code implementation | codex on `gpt-6.1-sol`, effort `medium` | codex on `gpt-6-astra` | tests plus a read of the diff |
| Heavy consult, architectural code, code review | codex on `gpt-6-astra` | Opus agent as a second reader | re-check each finding yourself |
| Diagnose an environment or an ambiguous failure | Opus agent, or yourself | — | reproduce the diagnosis |
| Web research, very large-context synthesis | agy | — | open the cited sources |
| Brainstorm, broad world knowledge | codex on `gpt-5.5` | — | judgement |

A three-way benchmark ran one exploration task and one four-file refactor on pi, a Sonnet agent and
an Opus agent. All three produced a correct refactor, passing 162 of 162 tests. On exploration pi
found the core answer, with a few wrong path prefixes and one false hit. Sonnet cost $0.18–0.40 per
task, Opus $0.48–0.80 and pi zero, at 1.5–2× Sonnet's run time. The reports differed most: Opus and
Sonnet proved their claims, and pi asserted one it had left unchecked. The numbers are in
`references/pi-ollama.md`.

Unit size follows the worker. pi and smaller models take one tight unit with verification between
hops; Opus and codex on `gpt-6-astra` hold a broader multi-part unit.

pi has two limits of its own. The GPU serves one pi request at a time, so pi units run in sequence,
and parallel units go to the other workers. pi also depends on the host's Ollama holding the model:
check it before the hand-off with the command in `references/pi-ollama.md`. When the model is
missing, stop and ask the user to load the weights onto the GPU and set up the container's Ollama
passthrough. Another worker takes the task only on the user's word.

## Bound the fan-out

A fan-out holds two or three independent units. Units are independent when both conditions hold:
each unit's inputs exclude every output another unit may create or modify, and their write scopes are
disjoint. A unit that reads what another is writing has a dependency edge, whatever its write scope.
Each writing unit gets its own worktree, or delivers a patch when exclusive paths are unavailable.
Network access, workspace writes and unsandboxed execution are three separate authorizations.

## Brief the worker

The worker knows only its prompt. Write a file-backed prompt that states:

- the task and the exact deliverable;
- the absolute working directory and the files in scope. A Claude agent starts in your directory, so
  its first line names its worktree;
- the permission boundaries: the edits allowed, and the git writes, installs and network use reserved
  to you;
- the acceptance commands and their expected results;
- the output path of every material artifact;
- the reply shape and a length cap.

Run every acceptance command yourself before delegating it, so every failure that predates the
worker is known in advance. Three rules bind every implementer:

1. Exact numeric targets go in the prompt. The worker reports any deviation and leaves the artifact
   as computed.
2. Tests stay intact. The worker reports any blocking test by name.
3. A claim that a failure predates the change carries its proof: the same command run with the change
   stashed.

Write the grader before the launch: a short script that checks the diff's scope, the references that
must change, the text that must survive and the test summary. Predict its output on the unchanged
tree, and confirm that prediction before trusting its verdict on the worker's tree.

## Accept from disk

**Trust the diff; read the report as the worker's account.** Acceptance rests on repository state.

1. Inspect every touched file and expected artifact on disk, including ignored directories.
2. Re-run the scoped tests and acceptance commands, and report any count that differs from the
   worker's.
3. Check git state in every reachable repository. A submodule is its own repository: when git writes
   were forbidden, inspect its HEAD, reflog and worktree separately.
4. Open rendered outputs whenever text, row counts, labels or layout changed.
5. Spot-check an exploration report's distinctive claims: each path exists, each importer imports.
6. Arrange an independent review for consequential work, then re-run these checks on the result.
7. Relay the worker and model used, the changed artifacts, the verification evidence and any open
   deviation.

Runtime prompts, logs and worktrees are temporary. A durable decision or outcome goes into the
project's memory structure.
