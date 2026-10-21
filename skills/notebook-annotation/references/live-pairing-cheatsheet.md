# Live Pairing Cheatsheet for Annotation Notebooks

Use these exact commands when pairing with the user on a served marimo annotation notebook (e.g., port `2782` for `14782-DM`, `2716` for `14616-DM`, `2719` for `14761-DM`).

## 1. Inspect Clusters or the User's Live Selection in One Command (~1–2s In-RAM)

Run `scripts/inspect_selection.py` with `--live-port 2782`. It executes directly inside the live marimo kernel's scratchpad against the already-loaded `nuclei`, `expr_matrix` (130 MB CSC sidecar), and `query_atlas` in **1–2 seconds** with zero disk reload:

```bash
# Inspect the selection the user just lassoed in the live browser session (~2s):
/opt/venvs/base/bin/python /workspaces/Meta-Aging/01_modules/scio/skills/notebook-annotation/scripts/inspect_selection.py \
  --live-port 2782

# Inspect specific clusters in-RAM inside the live kernel (~2s):
/opt/venvs/base/bin/python /workspaces/Meta-Aging/01_modules/scio/skills/notebook-annotation/scripts/inspect_selection.py \
  --live-port 2782 --column leiden_scvi_0.8 --values 10,11,13,14,15
```

## 2. Read or Drive the Live Marimo Kernel (`marimo-pair`)

Always include `/opt/venvs/base/bin` in `PATH` and pass `MARIMO_TOKEN` from `~/.config/marimo-tokens/<PORT>`:

```bash
PORT=2782
MARIMO_TOKEN="$(cat ~/.config/marimo-tokens/$PORT)" \
PATH="/opt/venvs/base/bin:$PATH" \
bash /workspaces/Meta-Aging/.agents/skills/marimo-pair/scripts/execute-code.sh \
  --url "http://127.0.0.1:$PORT" -c "
sel_now = get_selection()
print('round:', round_picker.value, 'lens:', dataset_key, 'space:', lasso_space.value, 'preset:', preset_picker.value)
print('selected cells:', len(sel_now.barcodes), 'steps:', len(sel_now.steps))
"
```

### Highlight a Cluster or Barcode Set on the User's Screen

To highlight a set of cells on all 6 UMAP panels in the user's open browser tab without waiting for them to lasso:

```bash
PORT=2782
MARIMO_TOKEN="$(cat ~/.config/marimo-tokens/$PORT)" \
PATH="/opt/venvs/base/bin:$PATH" \
bash /workspaces/Meta-Aging/.agents/skills/marimo-pair/scripts/execute-code.sh \
  --url "http://127.0.0.1:$PORT" -c "
target_bc = frozenset(nuclei.loc[nuclei['leiden_scvi_0.8'].astype(str).isin(['10', '11']), 'barcode'].astype(str))
step = sel.Step(op='replace', writer='rule', panel='rule', lens=dataset_key, space_drawn='rule',
                round=str(round_picker.value), n_in=len(target_bc), n_after=len(target_bc))
new_sel = sel.Selection(barcodes=target_bc, steps=(step,))
selection_history.record(new_sel)
set_selection(new_sel)
for name, p in panels.items():
    idx = np.flatnonzero(p['index'].isin(target_bc)).astype(np.uint32)
    p['widget'].selection = idx
print('highlighted', len(target_bc), 'cells across', len(panels), 'panels')
"
```

## 3. Save a Selection and Refresh the Live `Current + saved` Overlay

Use `scripts/save_selection.py` to write the selection CSV, `_provenance/` CSV, `_history/` backup, and `selections_manifest.csv` row, and bump `set_registry_version` in the live kernel so `saved_fine` / `saved_parent` / `saved_action` repaint immediately:

```bash
# Save a drop selection by cluster rule:
/opt/venvs/base/bin/python /workspaces/Meta-Aging/01_modules/scio/skills/notebook-annotation/scripts/save_selection.py \
  --repo /workspaces/Meta-Aging/14782-DM --round 3 --lens endothelial --live-port 2782 \
  --name immune-doublets-round3 --action drop --priority 1000 \
  --column leiden_scvi_0.8 --values 10,11 \
  --rationale "heterotypic immune and endothelial doublets in leiden_scvi_0.8 clusters 10 and 11: high doublet_score and solo_prob, coexpressing Pecam1, Cdh5 with Ptprc, Dock2."

# Save the user's current live lasso as a relabel, trimming spillover clusters 10,11 in one ~1s call:
/opt/venvs/base/bin/python /workspaces/Meta-Aging/01_modules/scio/skills/notebook-annotation/scripts/save_selection.py \
  --live-port 2782 --from-live-lasso \
  --exclude-column leiden_scvi_0.8 --exclude-values 10,11 \
  --name arterial-ec-round3 --action relabel --level fine --new-label "Arterial EC" \
  --new-state Unresolved --priority 200 \
  --rationale "arterial endothelial cells in leiden_scvi_0.8 cluster 13: high Gja5, Bmx, Dkk2, Efnb2, Sox17, Hey1, Vwf with Pecam1, Cdh5."
```

## 4. Read-Only Visual Check with Playwright (`?kiosk=true`)

Always append `&kiosk=true` so Playwright joins as a read-only viewer and never takes over the user's editor session, and pass `--disable-dev-shm-usage` so Chromium stays out of the 64 MB `/dev/shm`:

```python
from pathlib import Path
from playwright.sync_api import sync_playwright

port = 2782
token = Path(f"/home/devuser/.config/marimo-tokens/{port}").read_text().strip()
url = f"http://127.0.0.1:{port}/?access_token={token}&kiosk=true"

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, args=["--disable-dev-shm-usage"])
    page = browser.new_page(viewport={"width": 1680, "height": 1100})
    page.goto(url, wait_until="domcontentloaded", timeout=30000)
    page.wait_for_timeout(3000)
    page.screenshot(path="/tmp/marimo_kiosk.png", full_page=False)
    browser.close()
```
