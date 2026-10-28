# Claude Code agents

When the orchestrator is Claude Code, its Agent tool spawns Claude workers inside the session. An
orchestrator that lacks the tool reaches every worker through its CLI.

A Claude worker runs without the Agent tool, and it shares the orchestrator's environment, so the
launchers' depth guard reads it as the orchestrator. The brief's opening line carries the one-level
rule to it (`SKILL.md`, Delegate one level deep).

## Pick the agent type

| `subagent_type` | Tools | Use for |
|---|---|---|
| `Explore` | search, read and shell | sweeping many files when you need the conclusion alone |
| `general-purpose` | all | implementation, refactors, multi-step research |
| `fork` | inherits your context and model | a side task that needs everything you already know |
| `Plan` | search, read and shell | an implementation plan |
| project agents (`code-reviewer`, `opus-reviewer`, `mapper`, …) | per definition | the role their description names |

`model` overrides the definition's model with `sonnet`, `opus`, `haiku` or `fable`; a fork keeps your
model. Set `effort` when the user or a skill asks for a level, and leave it at the default otherwise.

Brief a fresh agent as a peer: the goal, what you already ruled out, the files worth reading, and an
explicit narrow scope. A fork already holds your context, so its prompt states the task alone.

## Run and observe

- Agents run in the background, and the harness notifies on completion. Wait for the notification;
  the result is unknown until it arrives.
- The report reaches you alone. Relay what matters to the user.
- `SendMessage` to an agent's id continues it with its context intact. That is the cheap path for
  corrections and follow-ups; a new Agent call starts cold.
- The `output_file` is the agent's full JSONL transcript. Parse what you need from it with a script;
  a raw read floods your context.
- `Workflow` orchestrates many agents and runs on the user's explicit opt-in.
- A CLI worker runs as a Bash background task (`run_in_background`), and the harness notifies when it
  exits.

## Cost

The completion notification carries `subagent_tokens`, `tool_uses` and `duration_ms`. The transcript
carries the split that prices a run: one `usage` per API message id, with cache writes, cache reads
and output tokens.

```bash
python3 -I - "$output_file" <<'EOF'
import json, sys
seen = {}
for line in open(sys.argv[1]):
    try: m = json.loads(line).get("message")
    except ValueError: continue
    if isinstance(m, dict) and m.get("role") == "assistant" and m.get("usage"):
        seen[m.get("id")] = m["usage"]
keys = ("cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")
print("api_calls", len(seen), {k: sum(u.get(k) or 0 for u in seen.values()) for k in keys})
EOF
```

A run has a fixed shape. The first call writes 25–32k tokens to cache (harness system prompt, tool
schemas, `CLAUDE.md`) before the first file read, and a prompt of a few hundred tokens is about 1% of
that. The rest of the run is mostly cache reads, which grow with every file read. One exploration
task cost $0.30–0.40 on Sonnet 5.5 and $0.58–0.80 on Opus 5.5; one four-file refactor cost
$0.18–0.24 and $0.48–0.63. Each range spans the 5-minute and the 1-hour cache-write price. Check
current list prices before quoting a figure.

## Isolate the writes

`isolation: "worktree"` gives the agent a worktree of the session's repository. A fresh worktree
holds each submodule as an empty directory, so for code inside a submodule, create the worktree in
that submodule yourself and pass its absolute path in the prompt (recipe in
`references/devcontainer.md`).
