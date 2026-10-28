# pi on ollama/qwen3.6:35b

pi is a coding agent with read, bash, edit and write tools. Here it drives one model:
`ollama/qwen3.6:35b`, served by the host's Ollama and reached through `$OLLAMA_HOST`
(`http://172.17.0.1:11434`). A run costs local GPU time and zero tokens. pi's catalog also lists
OpenRouter and other Ollama models, so every call pins the model.

## Check that the model is up

```bash
curl -s --max-time 5 "$OLLAMA_HOST/api/ps" | grep -q '"name":"qwen3.6:35b"' && echo READY || echo MISSING
```

`READY` means the weights are on the GPU. On `MISSING`, or when the host stays silent past the
timeout, stop and ask the user to load `qwen3.6:35b` onto the GPU and to set up the container's
Ollama passthrough (`$OLLAMA_HOST`). Both live on the host and belong to the user. Another worker
takes the task only on the user's word.

## Command

```bash
cd "$workdir" && pi -p --mode json --model ollama/qwen3.6:35b --no-session --offline \
  --tools read,grep,find,ls "$(<"$prompt")" </dev/null > "$out.jsonl" 2> "$out.err"
```

- **`</dev/null` is mandatory.** With stdin open and stdout sent to a file, pi waits on stdin and the
  output file stays empty until the timeout. Two runs hung 90 s and 300 s that way; with stdin closed
  the same call finished in 3.5 s.
- pi works in its current directory, so `cd` into the worktree first. It loads that directory's
  `AGENTS.md`; `--no-context-files` skips it.
- `--no-session` keeps the run ephemeral; `--offline` skips startup network calls.
- `--mode json` streams one event per line; plain text mode returns the answer alone.

The tool allowlist follows the task:

| Task | `--tools` |
|---|---|
| Exploration, blast radius | `read,grep,find,ls` |
| Refactor with a test run | `read,edit,write,bash,grep,find,ls` |

bash also gives pi git, so the prompt reserves git writes to you, and you check `git status` and
`git log` afterwards.

Run pi as a harness background task and wait for the notification. A script in the noexec `/tmp`
runs as `bash script.sh` (`references/devcontainer.md`).

## Read the usage

Each assistant turn closes with a `message_end` event whose `usage` holds `input`, `output` and
`totalTokens`; tool calls are the `toolCall` entries in its `content`. Summarize a run:

```bash
python3 -I - "$out.jsonl" <<'EOF'
import json, sys
turns = calls = out = peak = 0; final = ""
for line in open(sys.argv[1]):
    e = json.loads(line)
    if e.get("type") != "message_end" or e["message"].get("role") != "assistant": continue
    m = e["message"]; u = m.get("usage") or {}
    turns += 1; out += u.get("output", 0); peak = max(peak, u.get("input", 0))
    calls += sum(c.get("type") == "toolCall" for c in m["content"])
    final = "\n".join(c["text"] for c in m["content"] if c.get("type") == "text") or final
print(f"turns={turns} tool_calls={calls} peak_context={peak} output_tokens={out}\n{final}")
EOF
```

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
