# Changelog

All notable changes to the Scio project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [5.2.0] - 2026-09-10

### Changed

- **Delegations run on `gpt-6-astra`.** `launch.sh` passes `-m gpt-6-astra` when
  given no `--model`, rather than deferring to whatever `~/.codex/config.toml`
  holds — a fan-out should not change model because it ran on a different
  machine. `gpt-5.6-sol` is the fallback where the installed codex is too old;
  `gpt-5.5` still serves brainstorming.

### Added

- **Exit 33: the model outran the CLI.** The server serves a new model only to a
  recent enough codex and refuses an older one *by name* after launch, which
  reads as a generic 400. `launch.sh` now classifies that message, prints the
  installed version, and names the remedy. Measured 2026-09-10: `gpt-6-astra`
  accepted on codex-cli 0.154.0, refused on 0.149.1, exit 1 either way.

  The probe already reports `CODEX_VERSION`, which is the fact that decides
  this; the skill now says to read it before a large fan-out, because
  discovering the gap once is cheap and discovering it per worker is not.

## [5.1.0] - 2026-09-10

### Changed

- **`container-port-tunnel` now yields a URL that survives a restart.** The
  token is pinned to a file under `~/.config/marimo-tokens/<PORT>` rather than
  taken from marimo's banner, which rotates per launch and does not flush
  reliably into a redirected log. Tokens stay on: an unauthenticated edit server
  is code execution for anyone who can reach the docker bridge. A `curl` check
  must pass before a URL is handed over — 200 with the token, `/auth/login`
  without.
- **A long-lived notebook keeps one standing port**, so bookmarks and tunnel
  commands stay valid. Which port serves which dataset is recorded by the
  project, in its own `AGENTS.md` or a note under `docs/_internal/`; the skill
  carries the convention and the table's shape, not one project's numbers.
- **Changing a notebook someone is looking at prefers in-kernel cell edits**,
  which keep the user's lassos and widget values. `marimo-pair` drives that and
  is installed per project rather than shipped in this catalog, so its absence
  is a question for the user rather than a silent fallback. A direct `.py`
  refactor kills the server first, because a running kernel autosaves over disk
  edits.

## [5.0.1] - 2026-09-09

### Fixed

- The rendered-flavor template keeps its name, `assets/notebook.qmd`. v5.0.0
  renamed it to `review.qmd` for symmetry with `explorer.qmd`, which bought
  nothing and broke the name anyone reaching for it already knew.

## [5.0.0] - 2026-09-09

Three notebook skills become two, and the pipeline decision gate stops being a
house pattern.

### Removed — breaking

- **The `decisions.<stage>` gate is no longer taught.** `decision-gate-notebook`
  moves to `_attic/`. The catalog no longer prescribes recording a verdict in
  `analysis_config.yaml`, nor a downstream stage that refuses to run until
  `status: APPROVED`. Exploration informs a judgement; it latches nothing and
  blocks nothing, and the reading reached goes to a topic note under
  `docs/_internal/<stage-stem>/`.

  Projects that already carry a `decisions:` block keep working — this removes a
  pattern from the catalog, not a key from anyone's config. Nothing in the
  toolkit ever enforced the gate, so no mechanism is lost.

### Changed — breaking

- **`interactive-breakpoint-explorer` and `decision-gate-notebook` merge into
  `notebook-exploration`**, one skill with two flavors: a live-kernel Python
  notebook brushing jscatter panels, and a rendered read-only Quarto/R notebook.
  Both are read-only; both send their conclusion to a topic note. All seven
  assets and both reference documents carry over under their existing names; the
  gate's config snippet does not.
- **`decision-notebook` becomes `notebook-annotation`.** It was named for
  routing while its substance was one instrument, and it sat one word away from
  `decision-gate-notebook` in a catalog matched on name and description. It now
  says what it is: the marimo multi-round annotation campaign.
- **Both skills ask the user before scaffolding.** `notebook-exploration` asks
  what needs to be seen and whether Python or Quarto; `notebook-annotation` asks
  what is being relabelled and which round. Routing stays contextual — each
  skill's own decision tree and `analysis-code-conventions` — rather than
  concentrating in a switchboard an agent has to know to consult.

## [4.2.0] - 2026-09-09

### Changed

- **A project may keep its own skills in `.claude/skills/`.** When a category
  directory holds an entry the toolkit does not own, `link` preserves it and
  binds the catalog as one symlink per entry beside it, where before it refused
  the directory and left the category unbound. Three consumers had been sitting
  in exactly that state since they migrated, reaching zero catalog skills
  through either door.

  The single category symlink remains the default and the better binding, but
  it makes the mount point resolve into the toolkit checkout: a skill installer
  pointed at `.claude/skills/` writes into the vendored submodule, where the
  result is untracked and the next `git checkout` there deletes it. That is how
  `decision-notebook` came to live inside one project's submodule. A project
  entry named like a catalog entry keeps loading and is reported on every run;
  removing the last project entry converges the category back to one symlink.

## [4.1.0] - 2026-09-09

Two skills that were living in one project's local catalog become part of the
toolkit, so every consumer gets them and there is one copy to maintain.

### Added

- **`decision-notebook`** — router for live analysis notebooks. It picks the
  flavor a decision calls for (annotation campaign, gate sign-off, one live look,
  freestyle EDA) and fully specifies the heaviest one: a marimo + jscatter
  campaign instrument with a selection manifest, rounds, in-kernel DE, and a
  deterministic path from saved selections to a cleaned roster. `decision-gate-notebook`
  and `interactive-breakpoint-explorer` are the two flavors it routes on to;
  `analysis-code-conventions` now names the router rather than the leaves.
- **`container-port-tunnel`** — reach a server running inside the devcontainer
  from a laptop. The compose template ships `ports:` commented out, so the
  container publishes nothing and a `-L PORT:localhost:PORT` tunnel lands on a
  host loopback with no listener; the tunnel has to target the container's bridge
  IP. Carries the listener probe that works in an image with no `ss`, `netstat`
  or `lsof`.

## [4.0.0] - 2026-08-26

The toolkit is `scio`, in name and on disk. Breaking for consumers: the vendored
directory moves from `01_modules/SciAgent-toolkit/` to `01_modules/scio/`, the
GitHub repository is renamed (the old URL redirects), and project memory becomes
a repository of its own.

### Changed — breaking

- **`01_modules/SciAgent-toolkit/` becomes `01_modules/scio/`** (ADR-D9). Both
  names are accepted during the migration: discovery, legacy-mount ownership, the
  freshness check, the vendor-path predicate and the two executable templates all
  read one list, `lib/scio/common.sh::_SCIO_TOOLKIT_DIRS`. Evidence outranks the
  name — a path declared in `.gitmodules` beats a same-named directory found
  elsewhere, and a candidate must carry `bin/scio` or `craft.yaml` to count. A
  project reaching the toolkit by path needs a symlink at the old name or its own
  references updated.
- **`docs/_internal/` is its own Git repository, always** (ADR-D10). `session.md`
  is the live record and always carries that name; what it supersedes moves to
  `session-history/<UTC timestamp>.md`, so sorting the directory reads it in
  order.
- **codex runs unsandboxed.** `launch.sh` passes `-s danger-full-access` unless
  `--sandbox` says otherwise. An enforced sandbox cannot open files in these
  containers — bwrap fails to create a namespace, every file tool fails, and
  codex exits 0 having written about a repository it never read. The container is
  the boundary and `--workdir` is what scopes the worker.
- **`--bg` is removed** from `launch.sh` and refused by name. Background the
  attached launcher through the caller's own task facility.

### Added

- `status.sh` — a read-only reader for a delegation run, by unit or by file, with
  `--wait`. One `SUMMARY` line and one `ARTIFACT` line per file. It reports
  quantities and never a phase, a percentage or an ETA.
- `launch.sh` writes an atomic status snapshot before spawning, on a two-second
  heartbeat while the child runs, and once on the reaped status — so an in-flight
  question has an answer.
- A run whose stream shows the sandbox blocking file access **cannot be reported
  as a success**: exit 32, `state=failed`, `codex_exit` preserved.
- `lint` checks: skill self-citations, one door to the catalog, scaffold residue,
  the attic holding only retired skills, delegate-cli's assets, and the memory
  topology.
- `analysis-code-conventions` gains a language-level reference for R and Python
  house idiom.
- `/handoff` as a command written by the session that lived the work.

### Removed

- `add-figure-variant` and `interpret-storm` commands; the `handoff` agent.
- `_attic/guidelines/`, which called itself the source of truth for coding
  conventions while sitting outside every mount.
- The decision-gate audit-trail keys that no reader consumed.


The catalog now binds through one directory symlink per harness category.

### Changed

- **The six category links are relative again when the toolkit is vendored
  inside the project.** `_link_category` wrote `$SCIO_TOOLKIT/<category>`
  verbatim, so every link named an absolute path: written from the host they
  resolved only on the host, written in a container only in the container, and
  the last `link` run won. Measured in the field on 2026-08-21 — a project
  pinned at the current tip had all six pointing at `/workspaces/<name>/…`,
  reachable from inside its container and dangling from outside. One
  `_link_symlink_target` helper now serves the category links and the
  `02_analysis/helpers` libs: relative while the source is inside the project,
  absolute for a global install, where a relative chain would break the moment
  the project moves. That also retires the helper path's unreachable fallback,
  since `realpath --relative-to` always succeeded. The idempotency test compares
  the *written* target rather than where it resolves — a resolution test reads an
  absolute link as current and would have left all 25 bound copies unrepaired.
  A re-run reports each repair. New `lint --check harness-links` fails a mount
  that does not resolve or that names an absolute path inside the project, so the
  regression cannot return silently; an absolute target outside the project is
  the global-install channel and stays quiet.
- **Scio now ships as the three-verb `link`, `craft`, and `lint`
  toolkit.** The demolition series removed role activation and stack state,
  deactivation, status/list, project scaffolding, update and provisioning,
  standalone validation, per-entry symlink and manifest machinery, and the
  retired role files. `lib/scio/` decreased from 7,382 to 2,555 lines.
- **The CLI, library namespace, and runtime environment use `scio`.** `scio`
  replaces `sciagent` across `bin/scio`, `lib/scio/`, and the `SCIO_*`
  environment variables with no compatibility shim. Managed markers are now
  `SCIO:CRAFT` and `SCIO:GITIGNORE`; legacy-aware migration recognizes
  `SCIAGENT:CRAFT`, `SCIAGENT:ROLES`, `SCIAGENT:GITIGNORE`, and `.sciagent/`
  state so no consumer context or hook ownership record is orphaned during
  re-pin. The distinct name avoids confusion with several unrelated tools that
  now carry the sciagent name.
- **`scio link` converges projects on six whole-tree catalog links.** It
  sweeps legacy toolkit-owned child mounts, dangling container paths, retired
  output styles, and helper-library links; preserves real files and
  outside-pointing links; refuses populated category directories with an entry
  listing; and materializes the two guardrail hooks through the existing
  hash-and-cede ownership discipline.
- **Project teardown is an explicit manual operation.** Removing the six
  category links is one shell line; managed blocks are removed from
  `AGENTS.md` as a second operation.

### Removed

- The activation stack, deactivation, update, status/list, project scaffolding,
  per-entry symlink machinery, and manifest-backed state model.

### Added
- **The CRAFT body's line budget is now a check instead of a comment.** `craft.yaml` declared its own cap in prose — "keep the rendered block terse (<=25 lines)" — which made the toolkit's only always-on text the one asset with a stated budget and no predicate behind it, against the rule that `lint.sh` owns every convention it can measure. The number now lives in `craft.yaml` as `max_lines:`, beside the body it governs, and `scio lint --check toolkit` hard-fails when the rendered body exceeds it; `craft_max_lines()` in `craft.sh` reads it exactly as `craft_version()` reads `version:`, and falls back to the documented 25 so a `craft.yaml` predating the key is still bounded. The check measures the **rendered** body, after `{{token}}` substitution, because that is what lands in a consumer's `AGENTS.md`; it is silent when there is no `craft.yaml`, matching `craft_render_and_write`, so a toolkit with no craft SSOT is unaffected. It lives in the `toolkit` check rather than the project checks — the subject is this repo's own asset, and no consumer's `lint` run gains a finding. The shipped body is 17 lines against the cap. New `tests/test_craft_block_budget.sh` covers under, over, and exactly-at (the boundary is inclusive), asserts a **non-default** declared cap is honoured so the number cannot quietly migrate back into the shell, and checks the shipped `craft.yaml` against its own budget. One thing this deliberately does not measure: those 17 lines are 4,658 characters, and the longest single bullet is 693 — a line cap bounds the shape of the block, not its token weight, and the way this block actually grows is bullets getting longer rather than more numerous. A character or per-bullet budget would bind that, and setting one is a call about the owner's own standing text rather than a defect to fix.
- **Offline distribution: `scripts/build-release.sh` + `install.sh`.** Implements `docs/proposals/2026-08-11-offline-distribution/10_packaging_contracts.md` and ADR-D1/D2/D3/D7 — no npm, no registry, no marketplace, and no installer that can reach the network. **The builder** takes an explicit ref (an implicit "whatever is checked out" is refused, as is a dirty tree), runs `scio lint --check toolkit` and `tests/run-all.sh` **against the exported tree** rather than the working tree — the working tree may sit at another commit and carries untracked residue the artifact will not — and only then emits three files: `scio-<version>-<short-sha>.tar.gz`, its `.sha256`, and sidecar metadata carrying the **full 40-char** SHA. Bytes come from `git archive --format=tar <sha> | gzip -n`; the working checkout is 180 MB against 5.6 MB tracked (171 MB of it one skill's `.venv`), so `git archive` is a correctness requirement, not tidiness. The metadata deliberately carries **no build timestamp**, so the whole triple — not just the archive — is reproducible. Naming resolves the one place the plan documents disagree: ADR-D7's `scio` stem wins over §1's `sciagent-`, but §1's short SHA is **kept** against ADR-D7's example, because without it two releases of different commits at one version are indistinguishable on disk. ADR-D7 initially limited the rename to the artifact; the subsequent rebrand makes the installed executable, `$SCIO_TOOLKIT`, the `si` alias and `_guard_toolkit_locality` use `scio`. **The installer** takes local files only — there is no code path that accepts a URL, and a URL-shaped argument is refused with the reason rather than fetched — verifies the checksum **before** extracting anything, extracts into staging on the destination filesystem and renames into `<prefix>/share/scio/versions/<full-sha>/` so two versions coexist by construction and an interrupted install leaves no half-tree, links **only** `<prefix>/bin/scio`, and writes a receipt sufficient for an exact uninstall (a link is removed only if it still points where the receipt says — otherwise it is reported and left alone, exit 3, the same "cannot verify → do not touch" rule as teardown). It performs no harness detection and writes no `settings.json`/`AGENTS.md`/skill mounts: installation and project binding are different verbs on different layers (ADR-D3, `00_INDEX.md` §2). **Fleet precedence is unchanged** and now has an end-to-end test: a global install cannot mutate a project that ships its own toolkit. Eight new tests (`test_build_release_{determinism,contents,refusals}.sh`, `test_install_{verify_and_dryrun,atomic,coexist_uninstall,invariants,locality_precedence}.sh`) plus `tests/_release_lib.sh`. They build **throwaway fixture repos** rather than this one — since the builder runs the suite, a test that built this repo would re-enter it. That is why there is deliberately **no `--skip-checks` flag**: an escape hatch on a release gate eventually gets used for a real release, whereas fixture repos with one-line gate stubs exercise both the passing and failing gate paths in milliseconds and make recursion impossible by construction. Correction to `00_INDEX.md` §5 recorded here rather than silently: on this host (git 2.34.1, GNU gzip 1.10) `--format=tar.gz` and a bare `| gzip` are **also** byte-stable, because gzip embeds an mtime only for a *named file* and git's built-in filter is already `gzip -cn`. `-n` and the explicit pipe are kept anyway, for the reason that survives the correction — `tar.tar.gz.command` is user-configurable, so `--format=tar.gz` inherits its determinism from the builder's `~/.gitconfig`.
- **`activate` and `status` gained `-h`/`--help` before their retirement.** They were the last two verbs without it: `-h` fell through `cmd_activate`'s positional loop and came back as "role not found: -h", and hit `cmd_status`'s unknown-flag arm with exit 1. Both branches returned before any mutation or state load, and `bin/sciagent`'s top-level `-h|--help|help` was unaffected. `tests/test_verb_help.sh` asserted all ten verbs answered both flags, that the help text named its verb, and — the assertion that mattered — that a help invocation left the project directory byte-for-byte empty (a `--help` that still mounted was worse than no `--help`). `list` remained without a `-h` branch; that was a separate change.

### Changed
- **Project settings contain only the two Scio guardrail registrations.** Claude Code resolves project settings by replacement rather than merging them with user settings (permission rules are the exception), so the former project backfill overrode the owner's editor, effort, model, memory, attribution, thinking, and statusline preferences across consumer repositories. `claude_settings.sh` now has one responsibility: materialize, register, and tear down `no_ephemeral.sh` and `caption_sweep.sh`. User defaults, statusline support, and user-global provisioning are handed off under `docs/_internal/handoff/dev-env/`.
- **`.sciagent/manifest.json` reached schema v2 before the manifest-backed state model was deleted.** The write-only `block_hash` field was removed because `activate` wrote it and nothing ever read it back — the drift guard read the hash from the `AGENTS.md` BEGIN marker via `block_hash_check` (`status.sh`, `craft_verb.sh`). Dead data in a state file is worse than no data, because nothing about a stale value looks stale. `manifest_finalize` consequently took no argument. Both readers were key-targeted (`manifest_stack` → `.stack`, `manifest_symlinks` → `.symlinks[]`), so the v1 manifests the fleet held remained readable and the next `activate` rewrote them wholesale. `version` was bumped because `version: 1` was the only way to tell a manifest that *might* carry `block_hash` from one that could not. `tests/test_activate_solo.sh` asserted the field's **absence**; `tests/test_manifest_schema_v2.sh` covered the v1-on-disk read, teardown, and in-place upgrade paths.

### Fixed
- **`install.sh --uninstall` reported an anomaly for the ordinary case of pruning a version that is not the current one.** With two releases installed — the situation content-addressing exists to allow — `--uninstall <old>` removed that version's tree and receipt correctly and then exited **3** with "another install owns it now", because the link-ownership test compared `readlink <prefix>/bin/scio` against the departing receipt's target and read every mismatch as unprovable. The status that means "cannot verify → do not touch" therefore fired on a link whose ownership *is* provable: it points into `<prefix>/share/scio/versions/<sha>/bin/scio` for a `<sha>` whose receipt sits in the same `receipts/` directory. Scripted housekeeping (`--uninstall <old> && …`) broke on it, and the message read as damage where the prefix was intact. Uninstall now resolves the link's target to a 40-char sha and requires that receipt to exist before deciding: a live sibling version keeps the link and the status stays 0; a foreign target, or a versions path whose receipt is gone, is still reported and left alone at exit 3 — the shape of the path alone licenses nothing. `tests/test_install_coexist_uninstall.sh` missed this by ordering: its coexistence section uninstalls the version installed **last**, which is the one owning the link, so the clean-exit branch was the only one the fixture could reach. It now prunes the non-current version first and asserts exit 0 with the sibling's link and tree intact, then restores both installs in their original order so the receipt-driven section that follows sees the state it assumes. Surfaced by exercising the offline channel end-to-end for the first time — build, verify, install, bind a project, prune, uninstall — against a real toolkit commit rather than a fixture repo.
- **The `02_analysis/helpers` shim modules never reached an already-provisioned project — `activate` materialized no shim at all.** `figure_style.py`, `figure_style.R` and `interactive_style.py` were written **only** by `new.sh`'s generic `_render_tree`, which ran once at scaffold time; `sciagent activate` created the two *hyphenated* contract-lib mounts (`02_analysis/helpers/{figure-style,interactive-style}`) and nothing importable beside them. Consequently, `figure-style`, `interactive-breakpoint-explorer`, and `decision-gate-notebook` were satisfiable only in a freshly scaffolded repo. This was the **third instance of one blind spot**, after the hook bodies and the status line: content written at scaffold time only, never reaching the field. `activate` then materialized all three (gated on `02_analysis/` existing, exactly like `symlink_create_helper_lib`, so a coordination or software repo was untouched — no shim, no `helpers/` directory), and `deactivate` reversed them, ownership records and ceded markers included. The three templates joined the `MANAGED` set in `tools/gen-template-provenance.sh`, so a stale copy in the field was recognised by its bytes and refreshed rather than ceded. **The ownership machinery moved out of `claude_settings.sh` into a new `lib/sciagent/ownership.sh`** (`ownership_ensure_body` / `ownership_teardown_body` / `ownership_template_hash_known`): an R helper module was not a Claude artifact, and calling a `claude_settings_*` function to write one would have entrenched a misnaming. Both callers — `claude_settings.sh` (hooks, statusline) and `symlinks.sh` (the shims, which sat next to the mounts it already owned) — depended on that module, which was listed in the `VERB_MODULES` closure of **every** verb that loaded either caller (`activate`, `deactivate`, `status`, `update`, `provision`), not merely the verbs whose code path reached a call: the closure was over the modules loaded, not the branches taken, which was the lesson of `4b291b2`. The refactor also unified the two hand-rolled teardown loops on one reverse (`ownership_teardown_body`), and gained an explicit exec-bit mode — `exec` for the hooks and status line, `plain` for the imported shims. `tests/test_helper_shim_propagation.sh` covered all of it, including the fleet's state at the time (a stale shim with **no** ownership record was refreshed; with the manifest hidden the same file was left alone, proving the refresh was licensed by the manifest), the byte-identity precondition (what `new project` rendered equaled what `activate` copied), and a structural guard on the module closure above. `tests/test_template_provenance.sh` derived its managed set from the shim directory too, so the `{{PLACEHOLDER}}` check covered the shims automatically.
- **`block_write` reported success when the write failed.** The create branch (target file absent) ended in an unconditional `return 0`, so a failed redirect — read-only directory, a directory sitting where `AGENTS.md` should be, ENOSPC — printed bash's own "Permission denied" to stderr and then reported success: `sciagent craft --project-dir <read-only dir>` said "added SCIAGENT:CRAFT block to: \<path\>" and exited **0** with no file at that path at all. The append branch in the same function propagated its failure all along, but only incidentally (its `printf` happens to be the function's last command), so the two write paths disagreed about whether an I/O error is an error. Found while trying to reproduce a reported "craft/provision can leave a 0-byte `AGENTS.md`": that claim does **not** reproduce — every craft/provision path either writes the complete block or writes nothing (verified against a missing template, an empty template, a 0-byte target, an unwritable target, a target whose parent does not exist, and a directory in the target's place) — but "writes nothing and calls it success" did. New `tests/test_block_write_io_failure.sh`.
- **`interactive-breakpoint-explorer` could not import its own helper lib in ANY project — the `interactive_style` shim was never written.** `symlink_create_helper_lib` mounts *hyphenated* directories (`02_analysis/helpers/{figure-style,interactive-style}`), which are not legal Python package names; the house design pairs each with an *underscored* shim module that projects actually import. `figure-style` had `figure_style.{py,R}`; `interactive-style` had nothing, and every import site spelled `helpers.interactive_style.interactive_helpers` — unresolvable no matter how fully the project was activated. Adds `templates/project/analysis/02_analysis/helpers/interactive_style.py.template` (materialized by `new.sh`'s `_render_tree`, same path as its figure-style sibling) and rewrites the three import sites to the flat `from helpers.interactive_style import …`. **Deliberately fails loudly** (ImportError at import time) where `figure_style.py` falls back to no-op stubs: a mis-styled figure is still a figure, but a stubbed explorer cannot brush, select, or persist barcodes, so it would produce a silently empty record. New `tests/test_helper_shim_coherence.sh` derives the mount list from `symlinks.sh` and the shim set from the template tree and cross-checks both against every `helpers.<mod>` import site in the repo — the check that would have caught this at commit time.
- **`explorer.qmd`'s compartment-root walk hung instead of erroring.** `Path("/").parent == Path("/")`, so the loop spun forever when the sentinel `02_analysis/config/analysis_config.yaml` was missing above the launch directory. Ported the guard its R twin (`decision-gate-notebook/assets/notebook.qmd`) has always had, with the same message quality (names the sentinel, the start directory, and the remedy). `tests/test_root_walk_guard.sh` scans every Python walk-up in the repo for the fixed-point guard and executes the real chunk under `timeout`, so a regression fails the suite rather than hanging it.
- **`peak-atlas-multiome` resolved its sibling skill's primitives against `getwd()`, and a miss only warned.** `call_peaks_multistrategy.R`'s default `../../peak-atlas-framework/scripts` was correct only if the user happened to `cd` into this skill's own `scripts/`; the default is now derived from the script's own location (`ofile` / `sys.source`'s `file` / `--file=`), which is right from any cwd under both `Rscript` and `source()`. `PEAK_ATLAS_FRAMEWORK_SCRIPTS` still overrides. A missing framework script is now **fatal** instead of a `warning()` that deferred the failure to a far-away "could not find function `clusterGRanges`"; the one legitimate reason to continue (primitives already sourced by hand) is detected explicitly and downgraded to a message. `tests/test_peak_atlas_framework_resolution.sh` runs the real resolution block from a foreign cwd (skips gracefully without `Rscript`).
- **`sciagent activate` reliably materialized `.claude/statusline.sh` (chmod +x) and `.claude/settings.json` before its retirement.** The files had previously been rendered only by `sciagent new project`, so projects that merely vendored the toolkit received no status line. `claude_settings_ensure_statusline` and `claude_settings_ensure_project_defaults` in `lib/sciagent/claude_settings.sh` were called from `cmd_activate` and therefore from `sciagent update`; they preserved existing settings values while filling missing defaults. `_new_project` also restored the executable bit after rendering `statusline.sh.template`.
- **Skill/agent/command symlinks are now RELATIVE when the toolkit lives inside the project tree.** `symlink_create_dual` (used by `activate`) and the `inject` symlink sites previously wrote every `.claude/*`/`.agents/*` link as an absolute path into whatever `$SCIAGENT_TOOLKIT` happened to be at activation time — breaking portability across host/container/machine and escaping the submodule pin. A new `symlink_target_for` helper (mirroring `symlink_create_helper_lib`) relativizes each link to its own directory via `realpath -ms --relative-to` when the toolkit is at/below the activation CWD, and falls back to the absolute path for external/global checkouts (where a relative `../../../…` chain would be fragile). Applies to all three namespaces (skills, agents, commands) and both mirrors (`.claude` and `.agents`); the manifest still records link *paths*, so `deactivate` teardown round-trips unchanged.

### Added
- **`cleanupPeriodDays: 90` added to the user + project `settings.json` templates.** Claude Code owns the session transcripts (`~/.claude/projects/<cwd>/<uuid>.jsonl`) and deletes them once older than `cleanupPeriodDays` (its default 30). 90 keeps a longer resume history and makes retention one of the sane defaults seeded consistently on the workstation and injected into analysis devcontainers (the same non-clobbering `provision`/`activate` jq-backfill as the other gold defaults). Note: this widens retention only — it does not address the separate upstream 2.1.x transcript-probe/concurrent-cleanup race (CHANGELOG v2.1.181, v2.1.196) that can truncate open sessions when multiple CLI processes run at once; that is a CLI-version + single-instance concern, out of scope for the toolkit.
- **New `delegate-cli` skill, wired into the `science-architect` role.** Documents how to hand off or consult work to the local `codex` (OpenAI GPT-5.x) and `agy` (Gemini 3.x) CLIs in headless mode: the exact flags, the mandatory `-m gpt-5.5` (every `-codex` variant 400s on a ChatGPT account, incl. the config default), `--skip-git-repo-check`, the sandbox modes and their verified constraints (no git/network/kernel-probe writes under `workspace-write`; the devcontainer bwrap failure needing `--security-opt seccomp=unconfined`), the `agy -p` prompt-before-`--add-dir` ordering quirk, and a task→command quick map. Adding it to `roles/science-architect.yaml` made the retired `sciagent activate base science-architect` surface it. Tool-by-strength: implementation/review → codex, web-research/large-context → agy.
- **Toolkit-locality guard for mutating verbs.** The retired `activate`/`inject`/`eject` verbs refused to run when the project shipped its own `./01_modules/SciAgent-toolkit` but the resolved `$SCIAGENT_TOOLKIT` was a different toolkit, protecting the pinned copy from a global `sciagent`. The current `scio link` guard carries that protection through `$SCIO_TOOLKIT` and recognizes the legacy vendor path `./01_modules/SciAgent-toolkit` until the fleet migrates to `./01_modules/scio`. `deactivate` remained unguarded because it removed only state owned by its manifest. New tests: `tests/test_relative_symlinks.sh`, `tests/test_toolkit_locality_guard.sh`.

Unified figure style: the figure-style contract drops the dual print/screen
variant model in favor of ONE legible tier emitted in BOTH formats. Promoted
from the in-project Wave-0 prototype that proved it across a full results tree.

### Changed
- **`lib/figure-style/figure_helpers.R` — unified single-variant, dual-format contract.** `project_theme()` is now ONE legible tier (no per-variant font floors; plain non-bold axis titles, bold title/legend-title/strip, right legend with inter-row air, `axis.line` 0.4, `plot.title.position` "plot", config-driven margins) read from the `figures:` block. `save_figure()` emits exactly `<name>.pdf` (cairo, Unicode glyphs) + `<name>.png` (no `.print`/`.screen` suffix), shares ONE geometry, purges stale same-stem files, and NEVER re-themes (the caller owns all theming); `name` may carry a subdir. `save_overview()` keys its README caption on `<name>.png`. `style_series()` is the alignment-safe running-sum normalizer (via the `grs_restyle` closure: ES-clamp, single top-justified right legend, bottom-only xticks, config `running_sum_heights`), with `style_running_sum` as an alias. The `variant` parameter is retained on `project_theme`/`set_paper_style`/`save_figure` but IGNORED (drop-in compat); `void=TRUE` borderless-panel behavior preserved.
- **`lib/figure-style/figure_helpers.py` — contract parity.** `set_paper_style()`/`project_theme()` single tier (plain axis titles, `variant` accepted-but-ignored); `save_figure()` emits `<name>.pdf` + `<name>.png` (no suffix), one shared geometry (`wide`/`width`/`height` overrides), purges stale same-stem files; `save_overview()` keys the caption on `<name>.png`. Removed the per-variant font-bump/geometry/normalize helpers.
- **`analysis_config.yaml:figures` template + `figure_style.{R,py}` shim templates** rewritten to the unified keys (`base_size` 14, `title_size`, `subtitle_size`, `axis_title_size`, `axis_text_size`, `strip_size`, `legend_text_size`, `caption_size`, `label_size`, `cue_size`, `line_width`, `point_size`, `width`/`height`, `width_wide`/`width_narrow`, `dpi`, `formats: [pdf, png]`, `top_n`, `running_sum_ylim`/`running_sum_top`/`running_sum_heights`, `nes_cap`, `caption_wrap_column`, sub-layout dirs). Dropped `base_size_column`/`width_column`/`height_column`/`variants`.
- **`validate --check figure-style`** base-font floor lowered 16 → 14 to match the unified single tier (the new template default no longer trips the toolkit's own guardrail).
- **`skills/figure-style/SKILL.md`** rewritten for the unified single-variant, dual-format style (removed `.print`/`.screen` language).
- **`craft.yaml` (`SCIO:CRAFT` single source)** — the always-on Figures craft standard rendered into every repo's `AGENTS.md` now states ONE legible tier: `figure_base_size` floor 16 → 14, the `figure_print_base_size` floor removed, and the body line reworded to "one legible tier, base >= 14pt; emit a vector PDF + raster PNG from one plot object" (no print/screen split). Propagated via `sciagent update`.
- **Craft / contract prose swept to the unified model** — the `figure-audit` and `captions` agents, the `add-figure-variant` and `interpret-storm` commands, the plan + project `AGENTS.md` templates, `_attic/guidelines/visualization.md`, and the `base` role comment now reference `<stem>.pdf` + `<stem>.png` (no `.print`/`.screen`), a single 14 pt tier, and `save_figure()`/`save_overview()` (dropped `save_figure(variant="both")`, `base_size_column`, dual-variant language).
- **`tests/test_validate_figure_style.sh`** conformant fixture uses the unified `<name>.png` naming.

### Added
- **Okabe-Ito palette helpers**: `scale_color_okabe()`/`scale_fill_okabe()` (R) and `okabe_palette()` (Python), sourced from `colors.okabe_ito` with a canonical 8-colour fallback.

## [3.3.0] - 2026-06-24

Skill lifecycle: a natural, judgment-driven path from `experimental` through
`stable` and `deprecated` to a reference-only attic — surfaced softly, never
enforced. No hooks, no fail-closed `validate` check; the toolkit only shows the
state and leaves the call to a human during practice.

### Added
- **`metadata.status:` skill field** (`experimental | stable | deprecated`, default `stable`). Absent/empty means `stable`, so only non-stable skills carry the field. `sciagent list skills` tags non-stable skills `[status]` (stable shown plain); a deprecated *active* skill earns a one-line migrate-off nudge in the `status` Notes section. Soft convention — `validate` does not hard-fail on it.
- **`_attic/` convention** for retired skills: reference-only, outside the active `skills/<name>/` resolver path, and listed in a separate "Attic" section of `list skills`. `_attic/README.md` documents revival.
- `docs/skill-lifecycle.md` (the lifecycle, the field, the attic, retire/revive recipes); CONTRIBUTING "Skill lifecycle" subsection; `tests/test_skill_lifecycle.sh` asserting attic exclusion, soft status surfacing, and that `validate` ignores the attic.

### Changed
- At that release, skill walkers skipped every underscore-prefixed holding directory.
- `architecture-treemap` status normalized `probationary` → `experimental` (documented vocabulary).

### Removed
- `shinymultiome-uio-host` retired to `_attic/` and dropped from `roles/base.yaml` — reference-only; revive per the attic README.

## [3.2.0] - 2026-06-23

Reproducible agentic science: centralize, inject, and enforce the owner's five
standing conventions (figure legibility, results placement, README adjacency,
planning decomposition, reproducibility) so a dropped-in agent follows them
without hand-steering. Three-layer model — centralized rule (CRAFT block),
capability (skill/helper/agent/command), guardrail (validate check + hook).

### Added
- **`SCIAGENT:CRAFT` managed block.** `block.sh` is parameterized by block id; `craft.yaml` is the single source of truth for the five-convention craft text + numeric floors; `lib/sciagent/craft.sh` renders it into AGENTS.md alongside `SCIAGENT:ROLES` on `activate`/`inject`/`eject`, SHA1 drift-detected and idempotently re-rendered. ROLES bytes unchanged.
- **Cross-language figure-style contract.** `lib/figure-style/figure_helpers.{R,py}` (parity-checked): `project_theme`/`set_paper_style`, `save_figure(variant="both")` (print+screen from one plot), `save_overview` (atomic figure+table+caption), `contrast_path`/`overview_path`, `style_series`, `purge_figures`, `write_caption`, `append_master_table`, `round_numeric_cols`, `direction_cue`. Symlinked into analysis repos by `activate` (relative, portable) with a per-project shim + fallback. `analysis_config.yaml:figures` carries dual-context floors (base ≥16 screen / ≥9 print). New `figure-style` skill + `figure-audit` agent.
- **Opt-in `sciagent validate --check` guardrails** (soft-warn default, `--strict` hard-fail): `figure-style`, `results-layout`, `captions`, `provenance`, `freshness` (CRAFT hash staleness + submodule-commit ancestry). `_scratch/`/`$TMPDIR` always exempt; default + activate-internal behavior unchanged.
- **Claude Code hooks** (scaffolded, project-scoped): PreToolUse no-ephemeral + figure-save nudge; Stop caption-sweep. `SCIAGENT_STRICT` toggles warn→block.
- **`sciagent update`** — re-pin the toolkit submodule + re-activate (re-render both blocks, re-link helpers) + report.
- **Planning suite:** gold-standard plan templates (`templates/plan/{00_INDEX,NN_slug}.md.template`); `reasoning-trace` skill; `science-architect` overlay role; orchestration commands `/pipeline-plan`, `/explore-and-plan`, `/add-figure-variant`, `/interpret-storm`.
- New tags `figure`, `provenance`, `planning`.

### Changed
- `scrna-pipeline-conventions` rewritten to the stage-based `03_results/<stage>/{figures,tables}/` layout (flat `plots/`/`checkpoints/` layout removed) and defers to the figure-style contract.
- `captions`, `doc-curator` (C3 path-qualified + C4 committed-script provenance), `handoff` (scripts/artifacts/decisions), `bio-interpreter`/`insight-explorer` (persist before returning) extended.
- Analysis `AGENTS.md.template` references the CRAFT block, figure-style shim, and `docs/_internal/plans/` namespace.

### Fixed
- `sciagent new project --type software` no longer creates an `analysis`-only `research/` namespace.

### Removed
- `_attic/guidelines/visualization.md` `base_size=12`/`theme_publication` dead-end superseded by the figure-style contract (redirect retired with the mechanical guidelines).

## [3.1.0] - 2026-06-02

### Changed
- Project type `software-tool` renamed to `software`; `--type software` now suggests activating `architect` (the software-design lane). No dedicated software role exists.

### Removed
- `roles/software-tool.yaml` removed; the `architect` role owns the software-design lane. No replacement software role — use `sciagent activate architect` in software projects.

### Fixed
- **`inject` resolves the requires-closure.** `sciagent inject <skill>` now walks the skill's transitive `requires:` graph and mounts any missing dependency (recorded with `via="requires:<root>"`), matching what `activate` does for role skills — injecting an orchestrator skill pulls its leaves. A skill already supplied by the active requires-closure is refused (`nothing to inject`) instead of creating a spurious manifest row.
- **`eject` no longer destroys shared dependencies.** Ejecting a closure root now prunes closure deps no longer needed by any other root, and direct eject of an auto-mounted dependency is refused (pointing you to eject the root instead).
- **`status` surfaces requires-inherited skills in all outputs.** Inherited skills now appear in text, `--effective`, `--json`, and `--source` — previously only the default text view. `--effective` now exits 0 on success (was 1).
- **`status` warns on stack drift.** When the manifest pins a role no longer in the catalog, the text view adds a `Notes:` line naming it and pointing at `sciagent deactivate`; `--json` gains a `stale_roles` array.

### Removed
- **`sciagent roster` command removed.** The verb and its module (`lib/sciagent/roster.sh`) have been deleted. Agent-metadata functionality (domain, description) is now served by:
  - `sciagent status` (text mode) — Sub-agents section now shows `domain[0]` and the first 60 chars of description for each activated agent.
  - `sciagent status --json` — each agent object now carries `"domain"` and `"description_brief"` fields.
  - `sciagent list roles` — roles listing now shows skill/agent/command counts per role.
  - `sciagent list role <name>` — new subcommand; prints role description, skills, agents, and commands in detail.
- Deleted 6 redundant roles that bloated the UI and duplicated coverage: `planning`, `annotator`, `scrna-atlas`, `multiome-analysis`, `multiome-grn`, `dc-dictionary`. The clean framework is now 4 roles: `base` (general scRNA foundation), `scatac-regulatory` (chromatin/ATAC overlay), `pathway-signature` (pathway/functional overlay), `architect` (software architecture, standalone).
- Updated `scatac-regulatory` and `pathway-signature` "Do NOT use when" comments to reference the surviving role names (`base`, `scatac-regulatory`) instead of the deleted ones.

### Added
- **`lib/sciagent/frontmatter.sh`** — new leaf module (no sciagent deps) with a pure bash YAML frontmatter parser. Exports `_fm_extract`, `_fm_scalar`, `_fm_list`, `_fm_nested_scalar`, `_fm_description`. Replaces the identical private functions that were baked into `roster.sh`.
- **`sciagent list role <name>`** — new subcommand; prints a detailed RPG-hero view of a role (description, skill list with count, agent list with count, command list with count). Returns exit 1 if the role does not exist.
- **`sciagent list roles`** — enhanced output now shows per-role skill/agent/command counts alongside the description.

## [3.0.0] - 2026-05-31

### Added
- `templates/GEMINI.md.template`: one-line `@AGENTS.md` shim — Gemini provider now has a canonical single-source shim matching the Claude pattern
- `templates/AGENTS.md.template`: appended `## Docs architecture` section with full taxonomy (`docs/stages/`, `docs/reference/`, `docs/_internal/{reasoning,research,plans,reports,handoffs}`), naming rules (YYYYMMDD_HHMMSS snake_case), archive convention (`_archive/YYYYMMDD/`), and boundary rules (no `.md` in `03_results/`)
- `sciagent gitignore [<path>]`: new verb that writes a `SCIAGENT:GITIGNORE` BEGIN/END managed block into `.gitignore`; idempotent; covers `docs/_internal/`, `.claude/`, `.agents/`, `.gemini/`, `.sciagent/`, `.mcp.json`, `.env`, `.env.*`
- `sciagent new project`: now scaffolds full `docs/` tree including `docs/_internal/{reasoning,research,plans,reports,handoffs}` with `.gitkeep` sentinels; writes `docs/README.md`; applies managed `.gitignore` block via `sciagent gitignore`
- `sciagent validate --project-dir <dir>`: six-check docs-layout linter — checks for `docs/`, `docs/_internal/`, hard-fails if `docs/_internal/` exists but is ungitignored, warns on `.md` files in `03_results/`, warns on coexisting archive-style dirs, warns on malformed root handoffs
- `templates/pre-commit.template`: pre-commit hook scaffold that runs `sciagent validate --project-dir` on every commit
- `tests/test_validate_docs_layout.sh`: 5 subtests covering all docs-layout linter checks

### Removed
- `mcp_servers/pal` venv and `deprecated/` harness installers (`install_claude.sh`, `install_codex.sh`, `install_gemini.sh`)

### Changed
- Reorganized `commands/` and `agents/` by role family. The resolver in `lib/sciagent/symlinks.sh` (`resolve_canonical`) preserves flat consumer names. Basename uniqueness is enforced by `tests/test_no_duplicate_basenames.sh`.
  - `agents/*.md` — 12 architect-pipeline agents
  - `agents/*.md` — 7 base-role helper agents
  - 14 architect commands and the shared `commit` command
- Renamed role `pathway-signature-agent` → `pathway-signature` to drop the misleading `-agent` suffix (roles live in `roles/`, LLM agents live in `agents/`). Fixed phantom skill references in this role's skills list — replaced 7 deleted skills with the consolidated triad `bulk-rnaseq-gsea`, `bulk-rnaseq-activity-inference`, `bulk-rnaseq-pathway-explorer`.
- Added `muon-multimodal-analysis` (originally added under its old name) to `roles/multiome-grn.yaml` to fill the Python-side 10x ATAC preprocessing / MuData / differential accessibility gap. Subsequently reverted; see below.
- Canonicalised all role-file docstrings (Purpose / Use when / Do NOT use when / optional Composes-with / optional Pipeline) for consistency and brevity.

### Added
- New role `multiome-analysis` (`roles/multiome-analysis.yaml`) for paired RNA+ATAC ingestion, preprocessing, integration, and differential accessibility — without GRN inference. Composes with `multiome-grn` for the downstream regulatory step.

### Changed
- Renamed skill `python-multimodal-10x` → `muon-multimodal-analysis`. The previous name conflated language with purpose; the new name aligns with the audit's namespace convention (defining library = muon/MuData). Directory, frontmatter `name:`, and all cross-references updated; history preserved via `git mv`.

### Reverted
- Dropped `muon-multimodal-analysis` (formerly `python-multimodal-10x`) from `roles/multiome-grn.yaml`. The skill belongs in the new `multiome-analysis` role; `multiome-grn` reverts to its original GRN-inference-only scope. Compose with `multiome-analysis` for preprocessing.

### Deferred (ADR-0002 placeholder)
- Skill-content dissection for the monolithic multimodal skills (`muon-multimodal-analysis`, `seurat-multimodal-analysis`, `multimodal-anndata-mudata`, `cellranger-arc-multiome`) is deferred to ADR-0002. The current role topology bundles these as-is; future work may split each skill into focused sub-skills (e.g. ATAC preprocessing vs. WNN integration vs. peak-gene linkage) without further role changes.

### Removed
- `roles/min.yaml` — unused minimal role.
- `docker/` — CI test scaffolding that was no longer wired into the test suite.

### Migration
After upgrade, projects that have an active sciagent stack must re-activate to refresh symlinks against the new source layout:

```
sciagent deactivate
sciagent activate <base> [overlay]
```

### Changed (prior)
- Removed MCP infrastructure (ToolUniverse, Serena, PAL, Sequential Thinking, Context7), profile switcher, and harness installers (Claude Code, Gemini CLI, Codex CLI). Toolkit now covers roles, agents, and skills only.
- Deleted obsolete docs: `docs/MCP-CONTEXT-MANAGEMENT.md`, `docs/INSTALLATION.md`, `docs/CONFIGURATION.md`, `docs/FAQ.md`, `docs/QUICKSTART.md`, `docs/ARCHITECTURE.md`, `docs/ARCHITECTURE_REVIEW.md`, `docs/CLI_IMPROVEMENT_PLAN.md`, `docs/ISSUES.md`.
- Stripped MCP/harness/profile sections from `README.md`, `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `docs/agents.md`, `templates/vendor/CLAUDE.md.template`, `templates/vendor/AGENTS.md.template`, `commands/verify.md`, `docs/workflows/architect/`.

### Fixed (historical — MCP addon tool permissions)
- `manage-addon.sh` now reads `tool_permissions` from addon templates and merges them into `settings.local.json` `permissions.allow`. Previously, addon tools were denied in subagents (Task tool) because subagents can't prompt interactively for permission.
  - `manage-addon.sh`: `update_settings_local()` strips stale `mcp__*` entries and rebuilds from enabled addons
  - `switch-mcp-profile.sh`: Settings generation includes addon tool permissions (survives profile switches)
  - `notebook-tools.addon.json`: Added `tool_permissions` array with all 11 tool names
  - `jupyter.addon.json`: Added empty `tool_permissions` array for future use

## [2.0.0] - 2025-12-16

### Added
- **Role System**: New declarative role-based configuration for agents and skills
  - `roles/base.yaml` - Default bioinformatics analysis role
  - `scripts/activate-role.sh` - Role activator script (symlinks agents/skills to `.claude/`)
  - `skills/` directory for custom skills
- **Template System**: Centralized AI context templates in `templates/vendor/`
  - `CLAUDE.md.template` - Claude Code project instructions
  - `GEMINI.md.template` - Gemini CLI project instructions
  - `AGENTS.md.template` - Universal AI rules for all agents
  - `context.md.template` - Scientific project context
  - `analysis_config.yaml.template` - Analysis parameters
- **Enhanced Profile System** (`switch-mcp-profile.sh`):
  - API key substitution (`${GEMINI_API_KEY}`, `${OPENAI_API_KEY}`, `${CONTEXT7_API_KEY}`)
  - `validate_profile()` function for dependency checking
  - Profile validation before switching
- **setup-ai.sh Enhancements**:
  - Template installation with placeholder substitution
  - Automatic role activation (`activate-role.sh base`)
  - Creates `02_analysis/config/analysis_config.yaml`
- **Architecture Tests** (`docker/test/Dockerfile.architecture-test`):
  - Validates role system, templates, profile switching
  - 8 sub-tests covering all modularization changes
- **Gemini CLI Test** (`docker/test/Dockerfile.gemini-test`)
- **Full test suite** now includes 11 tests (up from 10)

### Changed
- **scbio-docker Integration**: Directory renamed from `01_scripts/` to `01_modules/`
- **Template References**: All templates now reference `01_modules` (not `01_scripts`)
- **research-full.mcp.json**: Added explicit `--include-tools` with 14 curated tools to prevent context overflow

### Fixed
- **MCP Configuration**: Fixed incorrect arguments in `full.mcp.json` and `research-full.mcp.json` templates that caused `switch_mcp full` to fail.
  - Removed incorrect `uv` arguments (`--directory`, `run`) that were passed to the direct binary executable.
  - This ensures `tooluniverse` works correctly in `full` and `research-full` profiles, consistent with `research-lite`.
- **Dev Container npm EACCES**: Fixed npm global install failures in dev containers where nvm is installed to a read-only location (e.g., `/opt/nvm/` owned by root).
  - Added `ensure_npm_writable_prefix()` function to detect read-only npm prefix and auto-configure user-local prefix (`~/.npm-global`)
  - Added `ensure_npm_global_path()` function to ensure previously installed npm binaries are in PATH
  - Updated `install_gemini.sh` and `install_codex.sh` to call these functions before npm install
  - PATH updates are now persisted to `~/.bashrc` automatically
- **Prefix Conflict**: Fixed an issue where `nvm` usage was conflicting with a hardcoded `npm` prefix setting in `common.sh`, causing warnings and potential environment issues.
  - Removed `configure_npm_prefix` call from `ensure_nvm` in `scripts/common.sh`.
  - Removed `prefix` setting from `~/.npmrc`.
  - Removed `~/.npm-global/bin` from `~/.bashrc` to prevent shadowing of `nvm` managed binaries.
- **Claude Code Settings**: Fixed invalid permission glob patterns in `.claude/settings.local.json` generation.
  - Updated `scripts/switch-mcp-profile.sh` to use the correct `Bash(for f in :*)` wildcard syntax instead of invalid `Bash(for f in :*.ext)` patterns.
  - This resolves "Invalid Settings" warnings in `claude doctor` and ensures proper file globbing permissions.
- **MCP Profile Switching**: Fixed `switch-mcp-profile.sh` to correctly generate the `permissions` block in `settings.local.json`, ensuring MCP servers load correctly in Claude Code.

### Changed
- **Dependencies**: Updated `scripts/common.sh` to respect `nvm` environment management and avoid forcing global `npm` prefixes when `nvm` is active.
