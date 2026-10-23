---
name: notebook-annotation
description: "The annotation campaign instrument: one marimo + jscatter notebook serving many rounds of lasso, rule and marker selections over per-lineage re-embeddings, with a selection manifest, in-kernel evidence, and a deterministic path from saved selections to a cleaned roster. Ask the user what the campaign is for before scaffolding."
license: MIT
allowed-tools: Bash(/opt/venvs/base/bin/python **/notebook-annotation/scripts/inspect_selection.py *), Bash(/opt/venvs/base/bin/python **/notebook-annotation/scripts/save_selection.py *), Bash(bash **/marimo-pair/scripts/execute-code.sh *), Read
---

# Notebook Annotation

## Overview

Relabelling a dataset is a campaign, not a sitting. The label space evolves, selections
accumulate across sessions and rebuilds, and every ruling has to survive the next
re-embedding. This skill is the instrument for that: one marimo notebook driving rounds of
selection over per-lineage re-embeddings, a manifest that records every call with its
rationale, and a deterministic path from saved selections to a cleaned, relabelled roster.

## Ask before you scaffold

**Do not infer the campaign from context. Ask the user.** Before creating anything:

1. **What is being relabelled, and against what label space?** A fine-grained roster being
   cleaned, a coarse compartment split, doublet and debris removal, or a fresh annotation from
   markers — the lens set and the cleaning ladder differ.
2. **Is this a campaign, or one look?** If it is one sitting with nothing to carry forward, use
   `notebook-exploration` instead; the manifest machinery here is overhead you will not repay.
3. **Which round is this, and what roster does it start from?**

## The instrument

One marimo notebook serves an entire campaign: rounds of lasso, rule, and marker selections
over per-lineage re-embeddings, rationale captured at save time, in-kernel evidence on
demand, and a deterministic path from saved selections to a cleaned, relabelled roster.

Distilled from one snMultiome campaign that ran it end to end: a lens compute and export
stage, a selection resolution stage, and a roster cleaning stage, plus the explorer notebook
they feed. That tree is history, not a path to open; everything below is the
dataset-agnostic contract.

### Data plane

- A compute stage owns every artifact the notebook reads. The notebook renders and selects;
  it computes embeddings for nobody.
- Per lens, per round: one explorer parquet, one row per cell. Columns: barcode, lens
  de-novo UMAP x/y, frozen-integration coordinates for cross-reference, cluster ids at
  ~3 leiden resolutions, label_fine + label_coarse, condition/sample keys, QC
  (genes, counts, mito), doublet fields, a small `expr_<gene>` marker panel, and per-cell
  activity scores (signed regulon AUCs, motif deviations) joined by barcode.
- Sidecars for runtime streaming: the full matrix as CSC npz plus an index json
  (`{"barcodes": [...], "genes": [...]}`), one per modality (RNA log1p CP10K; ATAC gene
  activity where paired). Stage-exported, guarded so reruns skip the export.
- Rounds live in config: `rounds."N"` declares a roster (null means full) and the explorer
  parquet per lens. A `ROUND` env var selects. Round refresh recipe: resolution stage,
  cleaning stage, then the lens stage with `FORCE=1`.
- Every path comes from `analysis_config.yaml`. The notebook holds zero literals.

### Panel architecture

- One creator cell builds all scatter panels; selection observers attach to the raw widgets
  and mutate traits directly, so overlay updates leave the grid unrendered and lasso stays
  fluid.
- Grid semantics: the A row shows the active lens frame on its de-novo sub-embedding, the
  B row shows the whole roster on the round's global re-embedding, and one panel shows the
  frozen integration embedding with membership opacity, so a selection reads in all three
  coordinate systems at once.
- Every panel carries an identity header rendered in HTML above the canvas: panel id, frame
  and embedding, nucleus count, active color channel, and the color key (swatches or a
  colorbar). The widget's own legend draws over the canvas; the header replaces it.
- Colors resolve from config `colors.cell_types`: label-keyed hex, one hue per coarse
  family, fine states as shades within the family, colorblind-safe anchors (Okabe-Ito,
  Tol). The same label carries the same color in every lens, full or zoomed. Categoricals
  outside the map (cluster ids, condition) cycle a fallback palette.
- One dot-size rule lives inside the single panel-creator function, scaled by point count
  so sparse zoomed panels carry the same visual weight as the dense full view.

### Selection machinery

- Selection state is a frozen `Selection(barcodes, steps)` with a branching `SelectionHistory`
  tree; every panel draws the same `get_selection().barcodes`. Origin is lasso, rule, or marker;
  scope is lens or global; both persist in `_provenance/<id>.csv` and `source_brush`.
- Rule selection picks a categorical column and level set, so a whole cluster or a boolean
  flag selects in one click.
- Four-level label hierarchy (`Lineage → Parent → Fine` plus `State`): every relabel names its
  target `level` (`lineage`, `parent`, `fine`, or `state`) and `new_label` (plus optional
  `new_state`), validated against `03_results/interactive/selections/label_vocabulary.csv`. Unannotated
  levels carry `Unresolved`.
- Live Save & Overlay (`Current + saved`): `overlay_saved()` paints active selections of the
  current round onto `saved_fine`, `saved_parent`, `saved_lineage`, `saved_state`, `saved_action`,
  and `saved_source` reactively on `get_registry_version()`, marking dropped cells `"Dropped"`
  (`#919191`) while keeping `label_*` intact as the round's starting baseline.
- Saving writes a per-selection CSV under `03_results/interactive/selections/`, provenance steps
  under `_provenance/`, and a manifest row: `selection_id`, `lens`, `action` (`drop | relabel | keep`),
  `level`, `new_label`, `new_state`, `priority`, `rationale`, `n_cells`, `saved_at_utc`, `notebook`,
  `source_brush`, `status`, `round`, `lasso_space`.
- Saves append by default (union on barcode), Replace is an explicit mode, every touch
  snapshots the prior CSV into `_history/`, and deletion is its own panel. A same-name save
  leaves earlier work recoverable.
- Rationale style: write brief, affirmative prose stating what the cells are or why they are
  dropped, using only `,`, `.`, or `:` (never `—`, `–`, or `·`).
- Priority follows specificity: the smaller selection outranks the larger one it nests
  inside; at ties, severity orders `drop > relabel > keep`.
- Labels key to barcodes alone. Cluster ids renumber on every rebuild (membership shifts,
  HVGs shift, the graph re-forms), so a cluster-keyed rule relabels the wrong cells after
  one rebuild.

## Live pairing with the explorer

When the user is working in a served annotation notebook (e.g., port `2782`, `2716`, `2719`) and
asks you to inspect clusters, evaluate their current lasso, or save selections, use the bundled
CLI scripts in `scripts/` and the recipes in
[live-pairing-cheatsheet.md](references/live-pairing-cheatsheet.md). Both scripts run **in-RAM
inside the live marimo kernel** when `--live-port <PORT>` is active (~1–2 seconds, zero disk reload
of the 130 MB CSC expression sidecar or reference parquets):

1. **Invoke `inspect_selection.py` and `save_selection.py` directly with `/opt/venvs/base/bin/python` (prefix-matchable, deadlock-free)**:
   - Both scripts are standalone CLI wrappers that call `marimo-pair/scripts/execute-code.sh` internally with a 25-second timeout. Run them directly from bash; passing either script as the payload into `execute-code.sh` executes the wrapper inside the kernel and deadlocks on recursive `subprocess.run`.
   - Start every command directly with `/opt/venvs/base/bin/python <script_path>` or `bash /workspaces/Meta-Aging/.agents/skills/marimo-pair/scripts/execute-code.sh` as a single literal command (omit `export`, `$(...)`, `$VAR`, `timeout` wrappers, and `&&` chains). `execute-code.sh` auto-resolves `/opt/venvs/base/bin` on `PATH` and reads `~/.config/marimo-tokens/<PORT>` from `--url`, keeping every call prefix-matchable for one-click **"Always Allow"** in Antigravity and `permissions.allow` in Claude Code.
2. **Inspect clusters, history nodes, or the live lasso in one command (`scripts/inspect_selection.py`, ~2s)**:
   - For the selection the user just lassoed or intersected in the browser:
     ```bash
     /opt/venvs/base/bin/python <skill_dir>/scripts/inspect_selection.py --live-port 2782
     ```
   - For clusters or labels named in text (passing 2 values also runs pairwise Mann-Whitney DE between them):
     ```bash
     /opt/venvs/base/bin/python <skill_dir>/scripts/inspect_selection.py --live-port 2782 --column leiden_ccfree_0.8 --values 12,8
     ```
   - For branching selection history nodes (e.g. comparing `#18` vs `#22`):
     ```bash
     /opt/venvs/base/bin/python <skill_dir>/scripts/inspect_selection.py --live-port 2782 --history-nodes 18,22
     ```
   - Add `--highlight` to push the inspected barcodes onto all 6 UMAP panels in the user's open browser tab.
   - Reports cell count, **spatial UMAP island cohesion** (`DBSCAN` island count + `[MULTI-ISLAND]`
     warning when a group splits across disconnected UMAP islands), QC and doublet medians vs the
     rest of the lens, cross-embedding cluster correspondence (`leiden_scvi_*` vs `leiden_sub_*`),
     current/saved labels, stage-43 reference votes, top Mann-Whitney AUC markers, and pairwise DE when 2 groups are given.
3. **Verify spatial and QC hygiene before recommending or saving a call**:
   - Check that a proposed population forms a single coherent manifold region (`1 island`) rather
     than sweeping disconnected UMAP islands under one label. When a cluster or label spans
     separated islands, split and inspect each island before relabelling.
   - Use multi-embedding intersection (`A1` lineage sub-embedding $\cap$ `B1` global embedding out-of-compartment scatter) to catch low-UMI heterotypic doublets that count-based simulators (`Scrublet`/`SOLO`) under-score.
4. **Save selections immediately as new higher-priority manifest rows (`scripts/save_selection.py`, ~1s)**:
   - Call `save_selection.py` directly without inspecting its source first; its CLI contract is fixed.
   - **Prefer a new named selection with a higher `--priority` over appending to or overwriting an earlier row.** Each manifest row records a step in how the biological understanding evolved; higher priority overrides earlier broad selections cleanly at roster resolution:
     - Broad base compartments: `--priority 150`
     - Refined fine populations or state calls: `--priority 200` to `500` (increment as refinements nest)
     - Doublets, debris, and QC drops: `--priority 1000` (or `1100+` for subsequent targeted drop refinements)
   - **Ground `--rationale` in the user's question, the visual/multi-embedding geometry, and the marker/QC facts** in brief, affirmative prose using only `,`, `.`, or `:` (never `—`, `–`, or `·`).
   - Pass `--exclude-column` / `--exclude-values` with `--from-live-lasso` to trim margin spillover clusters in the same 1-second call:
     ```bash
     /opt/venvs/base/bin/python <skill_dir>/scripts/save_selection.py --live-port 2782 --from-live-lasso --exclude-column leiden_scvi_0.8 --exclude-values 10,11 --name lymphatic-ec-round3 --action relabel --level fine --new-label "Lymphatic EC" --new-state Unresolved --priority 200 --rationale "Lymphatic endothelial cells in leiden_scvi_0.8 cluster 15: high Prox1, Ccl21a, Mmrn1, Reln, Flt4 with Pecam1, Cdh5."
     ```
5. **Skip Playwright on routine inspect/save turns**:
   - In-kernel `inspect_selection.py` and `save_selection.py` verify state in ~1–2 seconds; reserve
     headless Chromium (`?kiosk=true` + `--disable-dev-shm-usage`, ~12s startup) strictly for visual
     layout debugging when requested.

### In-kernel evidence

- DE at the moment of doubt: Mann-Whitney AUC with BH correction, both directions, on CSC
  slices; contrasts are selection vs the rest of its lens, group vs group, or an arbitrary
  pair. Seconds, in the kernel, while the lasso is still live.
- Gene streaming: any gene pulls from the sidecar at runtime, joins both frames, and
  becomes a color channel.
- Marker co-detection: two runtime genes on a scatter, each axis RNA or ATAC, a quadrant
  blend (double-positive, two singles, double-negative) painted back onto the embedding,
  and a lasso on the scatter that selects like any other brush.
- Genomic tracks, paired-ATAC datasets: tabix-indexed merged fragments, per-group Tn5
  cut-site pileups over a chosen gene window, a kb-offset axis anchored at the
  strand-correct TSS, region rails (own atlas, cCREs by class, external OCR sets), and
  lane-packed gene/exon models. RNA-only datasets omit this section and keep the rest.

### Downstream resolution

- A resolution stage turns the manifest into per-barcode verdicts by severity then
  priority, and writes the conflicts table.
- A cleaning stage applies the ladder: owner selections first, then a debris rule with a
  rescue clause, then a doublet rule; then owner relabels; then `label_parents` maps every
  fine label to its coarse compartment, aborting on an unmapped label. Outputs: disposition
  table, summary, roster CSV with label_coarse + label_fine.
- The lens compute stage re-embeds each lens on the new roster with a shared recipe (HVGs
  on counts, PCA, neighbors, leiden at ~3 resolutions, fixed seed) and re-exports parquets.

### Serving

- Headless marimo on the project's assigned port, bound to 0.0.0.0; the SSH tunnel targets
  the container IP, not host loopback (skill: container-port-tunnel). Access token from the
  server log.
- Kill the server before editing the notebook .py: marimo autosave rewrites cells under
  you and patch anchors drift. Patch, syntax-check, relaunch detached (setsid), read the
  fresh token.

### Shared memory in containers

- In edit mode marimo stores each anywidget's JavaScript module as a virtual file in
  `/dev/shm`, and every jscatter panel holds its own ~2 MB copy of the jscatter bundle while
  the widget lives. An eight-panel notebook holds ~17 MB per kernel.
- Docker gives a container 64 MB of `/dev/shm` by default. Three live notebook kernels plus
  the leftovers of one crash fill it.
- A full `/dev/shm` kills the kernel with SIGBUS. The browser only disconnects; the server log
  reads "The kernel was stopped by the operating system (signal 7)". In compute stages the
  same full `/dev/shm` surfaces as `OSError: [Errno 28] No space left on device` from joblib
  (scanpy's neighbour search) while the disk has room.
- A kernel killed by a signal leaves its segments behind; the server's resource tracker frees
  them only when the server exits. Each crash shrinks the room for the next run.
- Fix: `shm_size: "2gb"` (or `ipc: host`) on the compose service, applied at the next
  container rebuild. Until then, delete `/dev/shm/<pid>-*` files whose pid is dead before a
  launch, point compute stages at a large temp dir with `JOBLIB_TEMP_FOLDER`, and check
  `df -h /dev/shm` before a run-all.
- Diagnosing a disconnect: grep the server log for `signal 7`, read `df -h /dev/shm`, and
  compare `md5sum /dev/shm/*.js` with `jscatter/bundle.js`. An `oom_kill` count in the
  cgroup's `memory.events` points to memory instead.

### Traps

- Cluster ids are nonstationary across rebuilds; barcodes are the only stable key.
- A same-name save that overwrites destroys campaign work; append-by-default plus
  `_history/` snapshots is the floor.
- Binary "activity > 0" ATAC gates pass almost everything; use quantitative fractions of a
  panel.
- snRNA-seq detects long intron-rich genes preferentially; check a novel split's markers
  against gene length before believing it.
- The widget legend draws inside the canvas; identity headers in HTML keep the canvas
  clean.
- A run-all that drops the browser connection inside a container is a full `/dev/shm`
  until the server log says otherwise (see Shared memory in containers).

## When not to use

- One sitting with nothing to carry forward — use `notebook-exploration`. The manifest,
  rounds, and cleaning ladder are overhead a single look never repays.
- A stage that writes authoritative state. The campaign's outputs are selections and a roster;
  the pipeline stages own everything downstream reads (skill: `analysis-code-conventions`).
- Nothing here latches a pipeline. The roster is an input a later stage consumes because you
  point it there, not a gate that blocks until signed.

## See also

- `notebook-exploration` — One look at what a stage produced, Python live-kernel or rendered Quarto
- `figure-style` — The styling and saving contract the snapshots plot through
- `analysis-code-conventions` — Narrative stages and authoritative data flow
- `reasoning-trace` — Where the campaign's conclusions become durable, stage-keyed notes
- `container-port-tunnel` — Reaching the marimo server in the devcontainer from a laptop browser
