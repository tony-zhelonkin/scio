# pi on ollama/qwen3.6:35b

pi is a coding agent with read, bash, edit and write tools. Here it drives one model:
`ollama/qwen3.6:35b`, served by the host's Ollama and reached through `$OLLAMA_HOST`
(`http://172.17.0.1:11434`). A run costs local GPU time and zero tokens. pi's catalog also lists
OpenRouter and other Ollama models, so every call pins the model.

## Run

```bash
"$skill_dir/assets/pi.sh" --unit "$unit" --workdir "$workdir" --prompt "$prompt" \
  --tools read,grep,find,ls
```

`pi.sh` is the pi counterpart of `launch.sh`. It checks that the model is on the GPU, runs pi in the
workdir with stdin closed, and records the run in `_delegations/<unit>/<run_id>/` beside the codex
runs: `prompt.md`, `stream.jsonl`, `final.md`, `stderr.log` and a `status.tsv` that `status.sh` reads
(`worker=pi`; `codex_exit` carries pi's exit). It prints the run's paths, a `USAGE` line (turns, tool
calls, peak context, output tokens) and the final message after `--- FINAL MESSAGE ---`. Run it as a
harness background task and wait for the notification. `stream.jsonl` holds pi's events; `view.sh
"$unit"` renders them in the codex layout, with each tool call as one `$` line and the usage as the
footer, and `view.sh --follow` is the `-log` window's command.

| Exit | Means |
|---|---|
| 0 | pi finished and wrote a final message |
| 30 | pi exited 0 with an empty final message |
| 34 | the call came from inside a delegation; the worker does the task itself |
| 40 | `qwen3.6:35b` is missing from the GPU |

**On exit 40, stop and ask the user** to load `qwen3.6:35b` onto the GPU and to check the
container's Ollama passthrough (`$OLLAMA_HOST`). Both live on the host and belong to the user.
Another worker takes the task on the user's word. The check by hand:

```bash
curl -s --max-time 5 "$OLLAMA_HOST/api/ps" | grep -q '"name":"qwen3.6:35b"' && echo READY || echo MISSING
```

pi loads the workdir's `AGENTS.md`, so it reads CRAFT and the one-level rule. `--no-session` keeps
the run ephemeral and `--offline` skips startup network calls; `pi.sh` passes both. With stdin open
and stdout on a file, pi waits on stdin and writes nothing, which is why `pi.sh` closes it.

The tool allowlist follows the task:

| Task | `--tools` |
|---|---|
| Exploration, blast radius | `read,grep,find,ls` (the default) |
| Refactor with a test run | `read,edit,write,bash,grep,find,ls` |

bash also gives pi git, so the prompt reserves git writes to you, and you check `git status` and
`git log` afterwards.

## What it is good for

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

**pi takes** code location and blast-radius sweeps whose paths you grep anyway, and mechanical
refactors with an exact spec, a test suite and a grader you wrote.

**A stronger worker takes** the task when its paths will be quoted unchecked, when the task is
diagnosing the environment, or when the worker must establish that a failure predates its change.

## Accept

pi's report is the weakest of the workers'. Accept on three checks you run yourself:

1. a grader that checks the diff's scope, the references that must change and the text that must
   survive, run first on the unchanged tree to confirm its baseline;
2. the test command, in a tree that holds every gitignored link the tests import;
3. `git status` and `git log -1`, confirming the HEAD is unchanged.

## GPU

The RTX 5000 Ada has 32 GB. The weights take 27–28 GB and the context cache takes the rest; Ollama
reports 29.3 GB resident with an indefinite keep-alive. The GPU serves one request at a time: Ollama
accepts parallel pi runs and serves them in sequence, so a fan-out of pi units takes the sum of their
run times. pi takes the serial, context-heavy share of the work, and parallel units go to the other
workers.

GPU training (scVI, scANVI, peakVI, multiVI and the rest) gets the whole card. Before any training
run, ask the user to unload the model entirely. Ollama is a host service shared by every container
that uses it, so the unload is the user's call. The command is:

```bash
curl -s "$OLLAMA_HOST/api/generate" -d '{"model": "qwen3.6:35b", "keep_alive": 0}'
```

After training, pi work resumes once the user reloads the model and the check above reads `READY`.
