# kimi

kimi runs headlessly through `assets/kimi.sh`, with the same `_delegations` run directory, `status.tsv`,
depth guard and final-message record as `agy.sh`. The default model is `kimi-code/k3.1-pro`.

## Launch

```bash
"$skill_dir/assets/kimi.sh" --unit "$unit" --prompt "$prompt"
"$skill_dir/assets/kimi.sh" --unit "$unit" --prompt "$prompt" --mode research
"$skill_dir/assets/kimi.sh" --unit "$unit" --prompt "$prompt" --mode workspace --workdir "$dir" --effort low
```

`consult` and `research` use an empty scratch directory and open the prompt with the same no-tools or
web-search line as agy. `workspace` runs in `--workdir`. The launcher prints the `KEY=VALUE` head,
`THREAD=`, one `USAGE` line and the answer after `--- FINAL MESSAGE ---`.

`--model` takes a model alias. `--effort low|high|max` rides `KIMI_MODEL_THINKING_EFFORT` and defaults
to `low`. `--timeout` takes a duration accepted by `timeout(1)`, defaulting to 10m for a consult and
25m otherwise.

The launcher finds `kimi` on `PATH`, then falls back to `/home/devuser/.kimi-code/bin/kimi`. It runs
`kimi -p PROMPT -m MODEL --output-format stream-json` with stdin closed. Prompt mode permits edits
and cannot combine with `--auto`. Each stream line carries `role`: `assistant`, `tool` or `meta`.
The last assistant content is the answer; the last meta record's `session.resume_hint.session_id` is
saved as the thread. `--resume` passes that id to `kimi -r` for a follow-up turn.

A run with no answer exits 30. A quota or authentication error in stderr exits 36; nested delegation
exits 34.
