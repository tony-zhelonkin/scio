# pi on ollama/qwen3.6:35b

pi is a coding agent with read, bash, edit and write tools. Here it drives one model:
`ollama/qwen3.6:35b`, served by the host's Ollama and reached through `$OLLAMA_HOST`
(`http://172.17.0.1:11434`). A run consumes local inference tokens and GPU time, with no metered cloud inference charge. pi's catalog also lists
OpenRouter and other Ollama models, so every call pins the model. `pi.sh` picks it from what Ollama has
loaded: `--model NAME` (or `SCIO_PI_MODEL`) when given, otherwise `qwen3.6:35b` when loaded, otherwise the
one loaded model. It never loads or evicts. A model pi has not registered in `~/.pi/agent/models.json`
fails at pi's own startup.

## Run

```bash
"$skill_dir/assets/pi.sh" --unit "$unit" --workdir "$workdir" --prompt "$prompt" \
  --tools read,grep,find,ls
```

`pi.sh` is the pi counterpart of `launch.sh`. It checks that the model is loaded in Ollama, runs pi in the
workdir with stdin closed, and records the run in `_delegations/<unit>/<run_id>/` beside the codex
runs: `prompt.md`, `stream.jsonl`, `final.md`, `stderr.log` and a `status.tsv` that `status.sh` reads
(`worker=pi`; `codex_exit` carries pi's exit). It prints the run's paths, a `USAGE` line (turns, tool
calls, peak context, output tokens) and the final message after `--- FINAL MESSAGE ---`. Run it as a
harness background task and wait for the notification. `stream.jsonl` holds pi's events; `view.sh
"$unit"` renders them in the codex layout, with each tool call as one `$` line and the usage as the
footer; `r2.sh watch "$unit"` from `tmux-pair` opens a jobs pane that follows it.

| Exit | Means |
|---|---|
| 0 | pi finished and wrote a final message |
| 30 | pi exited 0 with an empty final message |
| 34 | the call came from inside a delegation; the worker does the task itself |
| 40 | `qwen3.6:35b` is not loaded in Ollama |
| 41 | Ollama is unreachable or its readiness response is invalid |

On exit 40 or 41, the orchestrator uses direct inspection or another available
mapper within the task's budget, and notes why. If local-only execution is required,
report the unavailable prerequisite. Loading/unloading the shared model remains an
owner decision. The launcher checks `/api/ps`; it does not start a model.

```bash
curl -fsS --max-time 5 "$OLLAMA_HOST/api/ps"
```

Read the `models` array and match `name` or `model` to `qwen3.6:35b`.

pi loads the workdir's `AGENTS.md`, so it reads CRAFT and the one-level rule. `--no-session` keeps
the run ephemeral and `--offline` skips startup network calls; `pi.sh` passes both. With stdin open
and stdout on a file, pi waits on stdin and writes nothing, which is why `pi.sh` closes it.

The tool allowlist follows the task:

| Task | `--tools` |
|---|---|
| Exploration, blast radius | `read,grep,find,ls` (the default) |
| Any run | `locate` and `lines` are added by `pi.sh` from `assets/pi_lines.ts` |
| Refactor with a test run | `read,edit,write,bash,grep,find,ls` |

**Line numbers come from a tool.** pi's `read` returns text without line numbers, and a local model that
counts lines itself is wrong about one answer in three (measured 2026-11-13 on `qwen3.6:35b` and
`batiai/qwen3.6-27b:iq4`, three scoped questions each). `locate` returns `path:line: text` for a pattern
and `lines` prints a numbered range; `pi.sh` loads both and appends the rule that a cited line must
appear in their output. With them the same questions came back exact. Long lines are clipped at 220
characters, so minified sources stay readable.

bash also gives pi git, so the prompt reserves git writes to you, and you check `git status` and
`git log` afterwards.

## Historical task comparison

One exploration task and one four-file refactor ran on pi, a Sonnet 5.5 agent and an Opus 5.5 agent,
with identical prompts in separate worktrees of 14761-DM:

| | pi / qwen3.6:35b | Sonnet 5.5 | Opus 5.5 |
|---|---|---|---|
| Exploration: time, tool calls | 73 s, 25 | 50 s, 11 | 62 s, 13 |
| Exploration accuracy | core right; 4 path slips, 1 false hit | complete | most complete |
| Refactor: time, tool calls | 109 s, 32 | 47 s, 6 | 114 s, 12 |
| Refactor result | 162/162, exact scope | 162/162, exact scope | 162/162, exact scope |
| Claim that a failure predated the change | asserted | proved by stash | proved in a scratch copy |
| Cost per task | $0 | $0.18–0.40 | $0.48–0.80 |

pi found the right modules, the upstream source, and one test file the Claude agents missed. Its
slips were surface-level: `tests/` written for `helpers/tests/`, a file placed in the wrong package, a
prose line counted as an importer, line numbers off by one or two, and a reply past its 400-word cap.
Its diff was clean. Its report overstated: it headlined "All tests pass" while one test file had
failed to collect.

**pi takes** code location and blast-radius sweeps whose paths you grep anyway, a second map that
corroborates another agent's exploration without metered cloud inference, and mechanical
refactors with an exact spec, a test suite and a grader you wrote.

**A stronger worker takes** the task when its paths will be quoted unchecked, when the task is
diagnosing the environment, or when the worker must establish that a failure predates its change.

## Accept

The benchmark found path slips and an overstated result. Verify each report. For a
read-only map, check the named paths/symbols, dependency edges and tests, and confirm
HEAD and git status are unchanged. For an editing task, accept on these checks:

1. a grader that checks the diff's scope, the references that must change and the text that must
   survive, run first on the unchanged tree to confirm its baseline;
2. the test command, in a tree that holds every gitignored link the tests import;
3. `git status` and `git log -1`, confirming the HEAD is unchanged.

## GPU

The local RTX 5000 Ada has 32 GB. The benchmark observed 29.3 GB resident with
an indefinite keep-alive. Check live `/api/ps` and current workload before
scheduling. Run mapping requests sequentially on the shared GPU; parallel local
requests can contend or queue. Use the verified map to prepare independent
implementation units for other workers.

GPU training (scVI, scANVI, peakVI, multiVI and the rest) gets the whole card. Before any training
run, ask the user to unload the model entirely. Ollama is a host service shared by every container
that uses it, so the unload is the user's call. The command is:

```bash
curl -s "$OLLAMA_HOST/api/generate" -d '{"model": "qwen3.6:35b", "keep_alive": 0}'
```

After training, pi work resumes once the owner reloads the model and `/api/ps` lists it.

## Verified mapping run (2026-11-04)

A live read-only map of this skill used pi 1.3.0 and the already-loaded
`qwen3.6:35b`. It completed in 59 seconds: 7 assistant turns, 17 tool calls,
49,320 peak input tokens and 3,124 output tokens. The observed tool calls were
read/grep/find/ls, and scio HEAD and git status stayed unchanged. These are one
run's measurements, not a cost or latency guarantee.

The map located the launcher, `roots.sh`, status/view consumers and the existing
pi tests. It correctly identified missing readiness edge-case and tool-list tests.
It exceeded the requested 350 words and falsely claimed empty answers were marked
successful; the code already marked them failed. It also proposed an unsupported
`agent_start` entry point. Those claims were excluded from the accepted handoff.
The raw run remains under `_delegations/verify_mapping_20261104/` in Meta-Aging.

The verified implementation boundary was `assets/pi.sh` plus
`tests/test_delegate_pi.sh`; guidance lives in `SKILL.md` and this reference.
`roots.sh`, `status.sh` and `view.sh` consume the existing run contract and needed
no change. The readiness tests exercise whitespace, model-field variants, exact
model identity, unreachable/malformed responses, pinned model/read-only tool
arguments, empty results and the nested-delegation guard. Run:

```bash
bash tests/test_delegate_pi.sh
bash tests/test_delegate_durable_runs.sh
bash tests/test_delegate_view.sh
```

A second live check through the updated launcher restricted the map to `pi.sh`
and `test_delegate_pi.sh`, with reads capped at 120 lines. It completed in 10
seconds using 3 read calls: 13,697 peak input tokens, 496 output tokens, and an
86-word final table. The table matched the code/tests after separating model
absence (40) from service/response failure (41). HEAD, tracked diff, status and
the new test file stayed unchanged. This was a narrower task, not a controlled
speed comparison. Its raw record is `_delegations/verify_mapping_recheck_20261104/`.
