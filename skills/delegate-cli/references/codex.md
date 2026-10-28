# codex

codex is the implementer, reviewer and heavy-consult CLI. Three assets own its mechanics; resolve
them relative to the skill's `SKILL.md` as `$skill_dir/assets/`:

| Asset | Owns |
|---|---|
| `probe.sh` | the installed version, the configured model, and whether web and file reads work |
| `launch.sh` | flag spelling, stdin delivery, final-message capture, stream logs, run directories, status records, locks |
| `status.sh` | a run's state, read from disk |

`launch.sh --help` lists every option.

## Launch

```bash
"$skill_dir/assets/launch.sh" --unit "$unit" --workdir "$workdir" --prompt "$prompt" \
  --model gpt-6.1-sol --effort medium
```

That is the normal path for an implementation: **write a prompt, launch, read the final message.**
The launcher runs in the foreground, returns when the worker finishes, and prints the final message
after a `--- FINAL MESSAGE ---` marker. The `KEY=VALUE` head before that marker carries the run's
paths.

Each run writes to `<outermost working tree>/_delegations/<unit>/<run_id>/`. A linked worktree
resolves to its main checkout and a submodule to its superproject, so every run in the umbrella lands
in `/workspaces/Meta-Aging/_delegations`. `SCIO_DELEGATIONS` overrides the root, and a workdir outside
any repository falls back to `$TMPDIR/scio-delegate`. Locks stay in `$TMPDIR/scio-delegate/locks`,
because they key on live process ids. `status.sh --unit` follows a scratch pointer the launcher
leaves, and after a restart reads the durable root of the current directory.

The worker runs with `SCIO_DELEGATION_RUN=<unit>/<run_id>` in its environment, and a launcher started
where that variable is set exits 34: delegation is one level deep (`SKILL.md`). A live
`gpt-6.1-sol` run confirmed that the variable reaches codex's shell and that the nested launch
refuses.

Two options carry judgement:

- `--parallel-ok` **affirms independence** as `SKILL.md` defines it: each unit's inputs exclude the
  other's outputs, and the write scopes are disjoint. Pass it when both hold; the launcher's
  live-unit check serializes every other launch.
- `--bypass` also disables the approval path. `codex exec` already runs with `approval: never`, and
  the default already removes the sandbox, so reserve `--bypass` for a stated reason.

Give each unit a stable, specific name. A repeated active unit signals overlapping work; resolve the
overlap before relaunching.

## Models

Each run names its model on purpose:

| Model | Effort | For |
|---|---|---|
| `gpt-6.1-sol` | `medium` | complex code implementation |
| `gpt-6-astra` | the config's level | heavy consults, deep reasoning, architectural code, code review; the launcher's default |
| `gpt-5.6-sol` | the config's level | the fallback where the installed codex predates astra |
| `gpt-5.5` | the config's level | brainstorming and broad world knowledge |

An implementation launch passes `--model gpt-6.1-sol --effort medium`. A launch that omits `--model`
runs on `gpt-6-astra`, because `launch.sh` passes `-m gpt-6-astra` itself. A fan-out therefore keeps
its model on every machine, whatever `~/.codex/config.toml` holds. codex-cli 0.163.0 serves both.

**A model can outrun the CLI.** The server serves a new model to a recent enough codex and refuses an
older one by name after launch, with exit 1: `The 'gpt-6-astra' model requires a newer version of
Codex`. Measured 2026-09-10: codex-cli 0.154.0 ran astra, and 0.149.1 was refused. `launch.sh`
classifies that refusal as **exit 33** and prints the installed version with the remedy.

**Effort and web search ride config overrides.** The launcher's `--effort LEVEL` maps to
`-c model_reasoning_effort=LEVEL`, and its `--web` maps to `-c tools.web_search=true --enable
web_search_request`, which the probe reports as `WEB_MODE=config_enable`. Leave `--effort` off when
the config already sets the level you want. A reusable combination lives in
`$CODEX_HOME/<name>.config.toml` and loads with `codex -p <name>`.

## Probe

```bash
"$skill_dir/assets/probe.sh" --workdir "$workdir" --sandbox "$sandbox"
```

The probe is a diagnostic. Run it after a launch fails in an unfamiliar way, before a
large fan-out, and before web-dependent work.

- `CODEX_VERSION` decides the model gap above. Read it once before a fan-out, so the gap surfaces on
  one worker.
- `CODEX_MODEL_CONFIGURED` reports the local config. A `--model` value returns
  `CODEX_MODEL_REQUESTED_VALIDATED=0`: the probe confirms the flag exists, and the server alone judges
  its value.
- `--web` checks the web capability; `--file-read-check` checks the file tools under a sandbox.

On a nonzero result, stop and report the emitted facts and exit status. When codex is absent, report
that and stop; substituting a tool or installing software is the user's decision.

## Sandbox

**The sandbox is off, and that decision is settled.** Codex calls bwrap to enforce a sandbox, and
bwrap fails to create a namespace in these containers (`references/devcontainer.md`). Under an
enforced sandbox every file tool fails while codex exits 0, and the worker writes confidently about a
repository it was unable to read.

`launch.sh` therefore passes `-s danger-full-access` by default. **The container is the boundary,**
by the owner's standing decision for every run.

`--workdir` bounds the worker. Workspaces are host mounts, so an unsandboxed worker reaches
everything its workdir contains. Scope the workdir.

Restoring an enforced sandbox requires a fixed container policy (`scbio-docker
docs/ai-integration.md`) and a rebuild. Until then, `--sandbox MODE` opts back in, and
`probe.sh --file-read-check` reports whether reads work under it. Under an enforced sandbox the
launcher marks a run failed (exit 32) when its stream shows the sandbox blocking file access. With
the sandbox off that check is off too, because a `bwrap` in the stream is then file content the
worker read.

A bypass removes the sandbox and requires explicit user authorization. Enforcement comes from the
sandbox alone.

## Reuse a thread

**codex caches per thread.** Measured on codex-cli 0.162.1 with `gpt-6-astra` in 14761-DM: a fresh
thread's first request reuses the ~12k-token codex system prefix and pays full price for the rest
(skills catalog, `AGENTS.md`, the prompt: ~16k tokens), even when another thread sent the same bytes
seconds earlier. A resumed thread pays for its new turn alone: 178 uncached tokens on a 28k-token
context, and 196 after thirty idle minutes. Continuing a thread is what shares context between
requests.

The launcher records each run's thread (`THREAD=` in its output, `thread=` in `status.sh`):

| Situation | Launch |
|---|---|
| Corrections, review findings or a next step for an implementer that already ran | `--resume` on the same unit, with a prompt holding only the delta |
| Two or three independent units | fresh units, each with its own prompt |
| Several workers that need the same expensive reading | prime one unit to read and summarise, then `--fork-from` it per worker |

- `--resume` sends the prompt as a follow-up turn on the unit's thread. Write it as a delta: what to
  change and how to accept it. It refuses `--rules` and a different `--workdir`, because the thread
  already holds the brief.
- `--fork-from UNIT` copies another unit's thread into a new one. The copy pays for the source
  transcript once (~16k tokens measured) and saves the exploration: every worker starts from the same
  reading.
- Keep `--model` and `--effort` constant across a resume; each model has its own cache.
- Every request re-sends the whole thread at the cached rate, so new work starts a fresh unit and
  follow-ups to the same work resume.

Every launch passes `--disable plugins`, which keeps the skills catalog identical between runs;
remote plugin skills load in a race with the first request. A resume or fork carries the sandbox as
`-c sandbox_mode=…`, because `codex exec resume` takes the sandbox through config alone and would
otherwise fall back to the config's `workspace-write` default.

## Keep the launcher attached

**`launch.sh` runs in the foreground. Run the attached launcher as a harness background task.** Disk
state supports polling, and the harness task supplies the wake-up. A detached launcher leaves the
orchestrator files to poll and drops the wake-up.

| Caller | What to run |
|---|---|
| Owner behind `!` | the plain foreground command; timeout promotion supplies the task id |
| Orchestrator launching the work | the same foreground command through the harness's background-task facility, so the harness owns the process and notifies on exit |
| Orchestrator observing someone else's launch | `status.sh --file "$status_file" --wait` as a harness background task |
| Run the owner watches live | an `r2*` window driven by the `tmux-pair` skill |
| Interactive shell | foreground |

The launcher refuses `--bg`: the completion signal belongs to the harness task.

## Read a run's state

```bash
"$skill_dir/assets/status.sh" --unit "$unit"
"$skill_dir/assets/status.sh" --all          # one SUMMARY line per unit in this tree's _delegations
```

It prints one `SUMMARY` line (worker, state, PIDs, elapsed, heartbeat and activity age, stream and final
bytes, `expected_present=n/m`, and the real codex and result exit codes), then one `ARTIFACT` line
per file with current and baseline bytes and mtimes. The `FINAL` and `STREAM` paths hold the output.

**It reports quantities,** because quantities are what the disk holds; phase and progress stay your
judgement. A fresh heartbeat with old activity means the supervisor is alive while codex computes,
blocks or hangs. A stale heartbeat means the writer stopped, so suspicion falls on the launcher, the
host or the filesystem. A terminal state is definitive: the launcher reaped the child and recorded
its status.
