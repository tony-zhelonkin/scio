# Live Pairing Cheatsheet for Annotation Notebooks

Use these exact single-command patterns when pairing with the user on a served marimo annotation notebook (`2782` for `14782-DM`, `2716` for `14616-DM`, `2719` for `14761-DM`).

## 0. Execution & Auto-Approval Contract (Mandatory)

1. **Direct CLI invocation (prevents kernel self-deadlock)**:
   - `inspect_selection.py` and `save_selection.py` are standalone Python CLI wrappers that call `marimo-pair/scripts/execute-code.sh` internally with a 25-second timeout.
   - Run them directly with `/opt/venvs/base/bin/python <script> --live-port <PORT>`.
   - Passing `inspect_selection.py` or `save_selection.py` *into* `execute-code.sh` runs the CLI wrapper inside the marimo kernel, which then spawns a subprocess calling `execute-code.sh` back on the same kernel and deadlocks. Both scripts and `execute-code.sh` enforce guards against this.
2. **Prefix-matchable command shapes for default auto-approval**:
   - `execute-code.sh`, `inspect_selection.py`, and `save_selection.py` automatically prepend `/opt/venvs/base/bin` to `PATH` and read `~/.config/marimo-tokens/<PORT>` from the port number.
   - Start every command directly with `/opt/venvs/base/bin/python` or `bash /workspaces/Meta-Aging/.agents/skills/marimo-pair/scripts/execute-code.sh` as a single command without `export`, `$(...)`, `$VAR`, `timeout` wrappers, heredocs, or `&&` / `;` chains.
   - **Antigravity IDE / CLI**: Granting **"Always Allow"** once on `/opt/venvs/base/bin/python` and once on `bash /workspaces/Meta-Aging/.agents/skills/marimo-pair/scripts/execute-code.sh` auto-approves all subsequent inspect, save, and scratchpad calls via prefix matching.
   - **Claude Code (`~/.claude/settings.json`)**: Pre-populated under `permissions.allow` with `Bash(/opt/venvs/base/bin/python *)` and `Bash(bash */marimo-pair/scripts/execute-code.sh *)`.

## 1. Inspect Clusters, History Nodes, or the Live Selection (~1–2s In-RAM)

`scripts/inspect_selection.py` executes inside the live marimo kernel's scratchpad against in-RAM `nuclei`, `expr_matrix` (130 MB CSC sidecar), and `selection_history` in **1–2 seconds** with zero disk reload:

```bash
# 1a) Inspect the selection the user just lassoed or intersected in the browser (~2s):
/opt/venvs/base/bin/python /workspaces/Meta-Aging/01_modules/scio/skills/notebook-annotation/scripts/inspect_selection.py --live-port 2782

# 1b) Inspect specific clusters in-RAM (passing 2 values also runs pairwise Mann-Whitney DE between them):
/opt/venvs/base/bin/python /workspaces/Meta-Aging/01_modules/scio/skills/notebook-annotation/scripts/inspect_selection.py --live-port 2782 --column leiden_ccfree_0.8 --values 12,8

# 1c) Compare two selection_history nodes in-RAM with pairwise DE (~2s):
/opt/venvs/base/bin/python /workspaces/Meta-Aging/01_modules/scio/skills/notebook-annotation/scripts/inspect_selection.py --live-port 2782 --history-nodes 18,22

# 1d) Highlight a cluster across all 6 UMAP panels in the user's open browser tab:
/opt/venvs/base/bin/python /workspaces/Meta-Aging/01_modules/scio/skills/notebook-annotation/scripts/inspect_selection.py --live-port 2782 --column leiden_scvi_0.8 --values 10,11 --highlight --no-de
```

## 2. Save a Selection and Refresh the Live `Current + saved` Overlay (~1s In-RAM)

`scripts/save_selection.py` writes the selection CSV, `_provenance/` CSV, `_history/` backup, and `selections_manifest.csv` row, and bumps `set_registry_version` in the live kernel so `saved_fine` / `saved_parent` / `saved_action` repaint immediately:

```bash
# 2a) Save the user's current live lasso/intersection as a drop selection:
/opt/venvs/base/bin/python /workspaces/Meta-Aging/01_modules/scio/skills/notebook-annotation/scripts/save_selection.py --live-port 2782 --from-live-lasso --name low-umi-immune-doublets-round3 --action drop --priority 1000 --rationale "Low-UMI endothelial and immune doublets in leiden_scvi_0.8 cluster 6 co-expressing endothelial markers with Lyz2, Tmsb4x, Wfdc17, and Ptprc, identified via multi-embedding view where a tail of the main A1 endothelial sub-embedding projects into non-endothelial clusters on the B1 global embedding and was isolated by selection intersection."

# 2b) Save the user's current live lasso as a relabel, trimming spillover clusters 10,11 in one call:
/opt/venvs/base/bin/python /workspaces/Meta-Aging/01_modules/scio/skills/notebook-annotation/scripts/save_selection.py --live-port 2782 --from-live-lasso --exclude-column leiden_scvi_0.8 --exclude-values 10,11 --name lymphatic-ec-round3 --action relabel --level fine --new-label "Lymphatic EC" --new-state Unresolved --priority 200 --rationale "Lymphatic endothelial cells in leiden_scvi_0.8 cluster 15: high Prox1, Ccl21a, Mmrn1, Reln, Flt4 with Pecam1, Cdh5."

# 2c) Save a cluster rule selection:
/opt/venvs/base/bin/python /workspaces/Meta-Aging/01_modules/scio/skills/notebook-annotation/scripts/save_selection.py --live-port 2782 --name immune-doublets-round3 --action drop --priority 1000 --column leiden_scvi_0.8 --values 10,11 --rationale "Heterotypic immune and endothelial doublets in leiden_scvi_0.8 clusters 10 and 11: high doublet_score and solo_prob, coexpressing Pecam1, Cdh5 with Ptprc, Dock2."
```

## 3. Ad-Hoc One-Liners in the Live Marimo Kernel (`marimo-pair`)

When you need a custom query beyond `inspect_selection.py`, invoke `execute-code.sh` directly with `--url http://127.0.0.1:2782 -c "..."` (token and `PATH` resolve automatically):

```bash
bash /workspaces/Meta-Aging/.agents/skills/marimo-pair/scripts/execute-code.sh --url http://127.0.0.1:2782 -c "print(nuclei.groupby(['saved_action', 'saved_fine']).size().to_dict())"
```

## 4. Read-Only Visual Check with Playwright (`?kiosk=true`)

Reserve headless Chromium strictly for visual layout checks when requested. Always append `&kiosk=true` so Playwright joins as a read-only viewer and pass `--disable-dev-shm-usage` so Chromium stays out of the 64 MB `/dev/shm`:

```bash
/opt/venvs/base/bin/python -c "from pathlib import Path; from playwright.sync_api import sync_playwright; port=2782; token=Path(f'/home/devuser/.config/marimo-tokens/{port}').read_text().strip(); p=sync_playwright().start(); b=p.chromium.launch(headless=True, args=['--disable-dev-shm-usage']); page=b.new_page(viewport={'width':1680,'height':1100}); page.goto(f'http://127.0.0.1:{port}/?access_token={token}&kiosk=true', wait_until='domcontentloaded', timeout=30000); page.wait_for_timeout(3000); page.screenshot(path='/tmp/marimo_kiosk.png'); b.close(); p.stop()"
```
