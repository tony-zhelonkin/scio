# agy

agy is the clean-consult and web-research CLI, and the very-large-context reader. `assets/agy.sh`
owns its mechanics the way `launch.sh` owns codex and `pi.sh` owns pi: the same `_delegations`
run directory, `status.tsv`, depth guard and `view.sh` rendering. Verified on agy 1.4.9.

## Launch

```bash
"$skill_dir/assets/agy.sh" --unit "$unit" --prompt "$prompt"                       # consult
"$skill_dir/assets/agy.sh" --unit "$unit" --prompt "$prompt" --mode research       # web research
"$skill_dir/assets/agy.sh" --unit "$unit" --prompt "$prompt" --mode workspace --workdir "$dir"
```

The launcher runs in the foreground, prints the `KEY=VALUE` head, then `THREAD=` (the
conversation id), one `USAGE` line and the answer after `--- FINAL MESSAGE ---`. Run it as a harness
background task like the other launchers.

| Mode | Where agy works | What the launcher adds to the prompt |
|---|---|---|
| `consult` (default) | an empty directory under `$TMPDIR/scio-delegate/agy/`, outside every repository | "Answer from knowledge alone: no tool use, no file reads, no web search." |
| `research` | the same empty directory | "Use web search. Cite the URL of every source you relied on." |
| `workspace` | `--workdir` | nothing; the brief carries its own reading rule |

**The empty directory is the point of a consult.** agy loads the workspace it starts in: the same
120-word question cost 7.7k input tokens from an empty directory and 24.4k from a repository root,
measured on Gemini 3.8 Flash. A consult that needs none of the repository's structure runs where
there is none to load. A question about this code is a `workspace` run, and then the brief says what
to read.

The `USAGE` line names the model, the status, input and cached tokens, output tokens and every tool
step by name (`tool_calls=search_web=14`, or `none`). A consult that shows a tool name did read or
search after being told to answer from knowledge; a research run that shows `none` answered from
memory. Both are acceptance findings.

## Models

`--model` takes a slug from `agy models`; the launcher's default is `gemini-3.8-flash-medium`.

| Slug | For |
|---|---|
| `gemini-3.8-flash-{low,medium,high}` | consults and research; a consult returns in about 15 s |
| `gemini-4-argon-{low,medium,high}` | the deeper reader; on 2026-10-22 it returned `RESOURCE_EXHAUSTED 429, individual quota reached`, so a failed Argon run is checked for that line in `stderr.log` before anything else |
| `claude-*`, `gpt-oss-120b-medium` | listed by `agy models`; use the direct worker instead |

Effort rides the slug suffix. agy 1.4.9 also accepts `--effort low|medium|high|xhigh|max`; the
launcher leaves it to the slug.

## Measured

| Ask | Model | Tools | Input tokens | Wall |
|---|---|---|---|---|
| 120-word methods consult, empty dir | 3.8 Flash medium | none | 7.7k | 15 s |
| the same, without the no-tools line | 3.8 Flash medium | none | 7.7k | 16 s |
| the same, from a repository root | 3.8 Flash medium | none | 24.4k | 16 s |
| PyPI version plus changelog question | 3.8 Flash medium | `search_web` ×14 | 148.8k (72k cached) | 119 s |

Flash reached for no tool on its own in an empty directory. The research answer cited four real URLs
and was one point release behind PyPI on the day of the run, so **open the cited sources** stays the
acceptance rule for research.

## Flags, for a launch by hand

- The prompt is the value of `-p`, and every other flag follows it; a bare prompt starts
  interactive mode, which fails headlessly on `/dev/tty`.
- `--output-format stream-json` writes one event per line: `init` (model, cwd, tool list),
  `step_update` (`agent_response` text deltas, `tool` steps with `tool_name`, `state`
  `ACTIVE`/`DONE` and `duration_seconds`) and `result` (status, response, usage). `json` gives the
  `result` record alone.
- `--print-timeout` takes a Go duration (`10m`, `300s`); the launcher passes 10m for a consult and
  25m otherwise, or `--timeout`.
- Web search needs no permission grant. Shell commands do: a denied command can end a headless run
  with an empty answer, which the launcher reports as exit 30.
- The log `~/.gemini/antigravity-cli/cli.log` names the model as `label=` after the run; each
  invocation repoints that symlink. It also prints the user's whole permission allow-list, so a
  command approved with a token in it lands in every log.

## Fan out

Each unit has its own prompt and its own run; agy sessions are independent. Run each as a harness
background task.
