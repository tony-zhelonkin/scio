# agy

agy is the web-research and very-large-context CLI. Its surface below was verified on agy 1.1.10,
and the container carries 1.4.9. Run `agy --help` once per session before relying on a flag.

## Run headlessly

The prompt flag consumes the next token, the last prompt flag wins, and the first bare argument ends
flag parsing. Put the prompt as the value of `-p` and every other flag after it:

```bash
agy -p "$(<"$prompt")" \
  --model "$agy_model" \
  --print-timeout 25m \
  > "$output" 2>&1
```

- A bare prompt starts interactive mode, which fails headlessly on `/dev/tty`.
- `--model` takes the display label or the slug printed by `agy models`. An invalid value exits
  before the run. Interactive sessions may rewrite the configured default.
- agy encodes effort in its model names and rejects `--effort`.
- `--print-timeout` takes a Go duration with a unit, such as `25m` or `300s`.
- Print mode buffers output until completion, so capture stdout with redirection. A prompt that asks
  agy to write the output path switches it into agentic file-write mode.
- Headless tool calls need permission authorization. With `--dangerously-skip-permissions`, confirm
  the log records that permissions were auto-approved.
- A denied shell command can end a headless run early with an empty answer. Grant the command
  prefixes the task needs, and those alone.

## Confirm the model

Grep `label=` in `~/.gemini/antigravity-cli/cli.log` **after** the run. Each invocation repoints that
log, so a read before the run reports the previous session.

## Fan out

Give each unit its own prompt and output path and an independent session. Run each as a harness
background task, or capture its PID at launch and wait on that PID or on the expected output file.
