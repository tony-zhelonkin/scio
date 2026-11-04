---
name: delegate-cli
description: >-
  Choose, brief and verify a subagent in Anton's devcontainers: Claude Code
  agents, codex, kimi, agy, or local pi on ollama/qwen3.6:35b. Use before any
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
| agy | `assets/agy.sh` around `agy -p`, in an empty scratch directory for a consult | `references/agy.md` |
| kimi | `assets/kimi.sh` around `kimi -p`, with configurable thinking effort | `references/kimi.md` |
| pi on qwen3.6:35b | `assets/pi.sh` around `pi -p`, against the host's Ollama on the local GPU | `references/pi-ollama.md` |
| the container itself | devcontainer, raw terminal, tmux | `references/devcontainer.md` |

## Decide whether to delegate

Do the work yourself when it fits in a handful of tool calls, when you know the target, or when it is
a check you would run anyway. Delegate when one of these holds:

- the units are independent and can run in parallel;
- the answer requires reading across many files, and you need only the conclusion;
- a review must come from a fresh reader, so the reviewer receives the code and forms its own verdict;
- a side quest would otherwise block the main thread.

## Map before implementation fan-out

Before splitting nontrivial implementation across agents, obtain a task-scoped
map of the code topology and each worker's responsibility surface. Prefer one
read-only pi run on local `ollama/qwen3.6:35b` when the CLI, loaded model and local
compute are available. This spends local inference on discovery once and gives
implementers a compact starting map. It reduces repeated cloud context; it still
uses local tokens, GPU time and orchestrator verification.

Reuse a verified map when the relevant files and interfaces are unchanged. Skip
a separate mapper for a tiny, already-understood edit. If pi is absent, unloaded,
unreachable or contending with higher-priority compute, map directly or choose an
available worker from the grid. State the reason briefly. Do not load or unload
the shared model automatically. A user-specified worker or budget takes priority.

Ask the mapper for a concise handoff covering:

- entry points, call/data flow and the files that own each responsibility;
- exact paths and symbols, with evidence for callers and dependencies;
- each proposed worker's read scope, write scope and exclusions;
- shared files, downstream consumers and dependencies that prevent parallel work;
- existing tests, verification commands and explicitly unresolved questions.

Start with the relevant directories and bounded searches. Save the mapping brief
and report beside the plan's existing briefs/reports. The orchestrator verifies
paths, consequential dependency edges and test locations before assigning work.
Each implementer receives the relevant map slice, source revision and acceptance
criteria, reads the actual code it will change, and investigates any gap. Broad
rediscovery is warranted when the map is stale or contradicted by the code.

Run local pi mapping units sequentially. Split an oversized mapping question
before it spends its context on unrelated files. `references/pi-ollama.md` supplies
the read-only invocation and availability checks.

## Choose the worker

These are starting choices for the installed harnesses, not a mandatory sequence
or a ranking of every model. The orchestrator chooses by uncertainty, scope,
verification cost, latency, available capacity and the owner's preference. Record
the chosen model and effort in the brief/run. Explicitly pass a recommended effort;
a launcher's model default does not guarantee its effort. Check current harness
availability before substituting a model. Raise effort or use a stronger reviewer
when evidence warrants it; preserve useful context when resuming a thread.

| Work | Starting harness / model | Effort and flexibility | Accept through |
|---|---|---|---|
| Code topology, callers, blast radius; pre-implementation map | pi / `ollama/qwen3.6:35b` | Read-only tools; one scoped map at a time. Fall back to direct inspection or an available Sonnet/Codex mapper. | Verify paths, dependency edges and proposed write boundaries. |
| Mechanical change with an exact specification | pi / `ollama/qwen3.6:35b`, or Codex / `gpt-6.1-sol` | Pi only when grading is cheap; Codex `low` for a narrow edit. | Scope diff and focused tests. |
| Bounded implementation | Codex / `gpt-6.1-sol` | Start `medium`; `low` for straightforward work. Kimi / `kimi-code/k3.1-pro` at `low` or an available Sonnet worker are alternatives. | Verified map slice, diff and acceptance tests. |
| Architecture, ambiguous diagnosis, consequential reasoning | Codex / `gpt-6-astra` | Start `medium`, raise to `high` when useful. Kimi / `kimi-code/k3.1-pro` at `high` or an available Opus worker are alternatives. | Check premises and reproduce consequential claims. |
| Independent review | A fresh Codex / `gpt-6-astra`, Kimi / `kimi-code/k3.1-pro`, or Opus worker | Match effort to risk; choose a fresh reader. A simpler scoped review can use Sol or Sonnet. | Re-check findings against code and tests. |
| Knowledge consult or web research | agy / `gemini-3.8-flash-medium` | `consult` for knowledge-only; `research` for web evidence. Use another available research-capable worker when appropriate. | Verify consequential claims and open cited sources. |

The exact model IDs above match the local launcher defaults or established
explicit selections. Claude model aliases depend on the orchestrator's Agent
tool; a generic Claude CLI adapter is not supplied here. See each worker's
reference for supported flags and limits. Kimi's launcher supports `low|high|max`
and defaults to `low`; Codex's launcher defaults its model to Sol and inherits
effort unless `--effort` is supplied.

Keep stable instructions stable, pass only the relevant map slice and changed
requirements, and resume a suitable existing conversation. Cache reuse is
provider-dependent; avoid treating past benchmark token counts or dollar costs
as current tariffs. The local pi comparison in `references/pi-ollama.md` is
historical evidence for tasks that still need verification. General guidance on
balancing model quality, latency and cost: [OpenAI model selection](https://developers.openai.com/api/docs/guides/model-selection).

## Bound the fan-out

Start with two or three independent units; adjust concurrency to the dependency map and available capacity. Units are independent when both conditions hold:
each unit's inputs exclude every output another unit may create or modify, and their write scopes are
disjoint. A unit that reads what another is writing has a dependency edge, whatever its write scope.
Each writing unit gets its own worktree, or delivers a patch when exclusive paths are unavailable.
Network access, workspace writes and unsandboxed execution are three separate authorizations.

## Delegate one level deep

The agent the owner talks to is the orchestrator. Every worker reads the same CRAFT and the same
skills, and CRAFT states the rule each of them follows: a worker does its brief itself and names any
sub-task worth handing off in its report. The orchestrator then decides whether that sub-task becomes
a run of its own.

Three layers hold the rule, each covering what the one before leaves open:

| Layer | Holds | Covers |
|---|---|---|
| CRAFT and the brief | the intent, read by every worker | every worker, Claude agents included |
| `launch.sh`, `pi.sh`, `agy.sh` and `kimi.sh` | each worker runs with `SCIO_DELEGATION_RUN=<unit>/<run_id>`; every launcher refuses to start where it is set (exit 34) | codex, pi, agy and kimi, and any worker that reaches for a launcher |
| the run log | every launch writes `_delegations/<unit>/<run_id>/`; `status.sh --all` lists the units with their worker | the record you check at acceptance |

A Claude agent runs without the Agent tool and shares your environment, so the brief carries the rule
for it. A worker that calls `codex exec` directly goes around the launchers; its session appears in
`~/.codex/sessions` with the worker's directory as its `cwd`.

## Brief the worker

The worker knows only its prompt. The brief lives where it graduates: `briefs/<unit>.md` beside the
plan's `reports/` under `docs/_internal/`, and that path goes to the launcher, which copies it into
the run. A unit is named by stage and topic (`S02_relations`), and the name serves the run
directory, the watched pane and the brief alike. The brief states:

- its role, as the opening line: "You are a worker: do this brief yourself, and name any sub-task
  worth handing off in your report.";
- how to read: "Read with `rg` and `sed -n` ranges, one file per command; read a file whole when the
  brief names it as required reading." A whole-file `cat` of four files spends the worker's context
  and fills the stream the owner watches;
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
6. Read `status.sh --all`: every unit newer than your launch is one you started.
7. Arrange an independent review for consequential work, then re-run these checks on the result.
8. Relay the worker and model used, the changed artifacts, the verification evidence and any open
   deviation.

## Keep the run, graduate the memory

A delegation leaves two things with different lifetimes.

- **The run** is the rendered prompt, the stream, the status record and the final message. It lives
  in `_delegations/<unit>/<run_id>/` at the outermost working tree, which inside the umbrella is
  `/workspaces/Meta-Aging/_delegations`. The directory ignores itself, survives container restarts,
  and is pruned by hand. `launch.sh`, `pi.sh` and `agy.sh` write there alike; a Claude agent's transcript stays
  in the harness task directory.
- **The memory** is the brief, the worker's report, the review and a run record. It graduates into
  the project's `docs/_internal/` at acceptance. The run record states the worker, model and effort,
  the thread or agent id, the run directory, the duration and the acceptance results you observed.

Inside a verified tmux invocation, use `r2.sh watch <unit>` to observe the run in
the paired jobs session (`tmux-pair`). `SCIO_STREAM` groups related units in a
window and `SCIO_LABEL` names the role, harness and interaction mode. Resumes stay
in the same pane. Outside tmux, keep the ordinary harness workflow. Worktrees
leave once their results are accepted.

## Communicate at decision boundaries

One orchestrator owns integration. Long-lived collaborators own their domains;
workers own bounded assignments. Workers can clarify details directly with a
known peer; scope and shared-interface changes return to the orchestrator's record.
A direction from the owner reaches affected peers through that record.

Use the project's existing desk or working note. Keep one subject per thread.
Send when a question, decision, blocker or result changes the recipient's next
action. State the request or change, point to evidence and name who acts next:

```text
Reviewer → developer · T-0142
Finding: the empty selection hides the filter.
Evidence: var/captures/empty.png; expected behavior in docs/design/filters.md.
Next: developer fixes; reviewer checks the preview.
```

Keep proposals, owner decisions, implementation and verified results distinct.
Reuse relevant conversations and send changed information with precise references.
Avoid repeated full briefings and acknowledgement loops. Cache reuse depends on
the harness/provider; reduced context and fewer unnecessary turns are controllable.

Verify destination identities before delivering into an interactive session.
Coordinate input with the owner. Recorded-output panes are views: continue their
workers through the supported launcher rather than typing into the viewer.
Recover missed messages from the durable thread. Add tickets only when the
project's existing note becomes awkward to coordinate.
