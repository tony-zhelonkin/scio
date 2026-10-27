#!/usr/bin/env python3
"""Inspect clusters, labels, or the live marimo selection in an annotation campaign lens.

Fast path (--live-port <PORT>, ~1 second): runs directly inside the live marimo kernel's scratchpad
against the already-in-RAM `nuclei`, `expr_matrix`, `expr_genes`, and `expr_barcodes` (zero disk I/O).
Works for both the user's active browser lasso and named `--column` / `--values` clusters.

Offline fallback (when --live-port is omitted): reads the lens parquet and CSC sidecar from disk.

Usage examples:
  # 1) Inspect the user's currently lassoed selection in the live kernel (~1s):
  /opt/venvs/base/bin/python inspect_selection.py --live-port 2782

  # 2) Inspect specific clusters using the live kernel's in-RAM matrices (~1s):
  /opt/venvs/base/bin/python inspect_selection.py --live-port 2782 \
    --column leiden_scvi_0.8 --values 10,11,13,14,15

  # 3) Offline inspection when marimo is stopped:
  /opt/venvs/base/bin/python inspect_selection.py \
    --repo /workspaces/Meta-Aging/14782-DM --round 3 --lens endothelial \
    --column leiden_scvi_0.8 --values 10,11,13,14,15
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

IN_KERNEL_SCRIPT = r"""
import numpy as _np
import pandas as _pd
from scipy import stats as _stats
from sklearn.cluster import DBSCAN as _DBSCAN

_col = __COLUMN__
_vals_raw = __VALUES__
_hist_raw = __HISTORY_NODES__
_highlight = __HIGHLIGHT__
_top_n = __TOP_N__
_no_de = __NO_DE__

_df = nuclei
_all_bc = set(_df["barcode"].astype(str))
_groups = []

if _vals_raw:
    if _vals_raw.upper() == "ALL":
        _vals = sorted(_df[_col].astype(str).unique(), key=lambda x: (float(x) if x.replace(".", "", 1).isdigit() else 9999, x))
    else:
        _vals = [v.strip() for v in _vals_raw.split(",") if v.strip()]
    for _v in _vals:
        _groups.append((f"{_col}={_v}", set(_df.loc[_df[_col].astype(str) == _v, "barcode"].astype(str))))

if _hist_raw and "selection_history" in globals():
    for _h in [h.strip().lstrip("#") for h in _hist_raw.split(",") if h.strip()]:
        _hi = int(_h)
        if 0 <= _hi < len(selection_history.nodes):
            _nd = selection_history.nodes[_hi]
            _groups.append((f"history_#{_hi}", set(_nd.selection.barcodes) & _all_bc))

if not _groups:
    _sel = get_selection()
    _groups = [("live_selection", set(_sel.barcodes) & _all_bc)]

if _highlight and _groups and "panels" in globals():
    _hl_bc = frozenset().union(*(g[1] for g in _groups))
    _step = sel.Step(op="replace", writer="rule", panel="rule", lens=str(dataset_key), space_drawn="rule",
                     round=str(round_picker.value), n_in=len(_hl_bc), n_after=len(_hl_bc))
    _new_sel = sel.Selection(barcodes=_hl_bc, steps=(_step,))
    selection_history.record(_new_sel)
    set_selection(_new_sel)
    for _p in panels.values():
        _p["widget"].selection = _np.flatnonzero(_p["index"].isin(_hl_bc)).astype(_np.uint32)

def _spatial_islands(df, mask, x_col, y_col):
    if x_col not in df.columns or y_col not in df.columns or mask.sum() < 10:
        return "n/a"
    coords = df.loc[mask, [x_col, y_col]].dropna().to_numpy(dtype=_np.float64)
    if len(coords) < 10:
        return "n/a"
    all_c = df[[x_col, y_col]].dropna().to_numpy(dtype=_np.float64)
    eps = max(_np.ptp(all_c, axis=0).mean() * 0.045, 0.35)
    min_s = max(5, min(25, len(coords) // 40))
    lbl = _DBSCAN(eps=eps, min_samples=min_s).fit_predict(coords)
    valid = lbl[lbl >= 0]
    if len(valid) == 0:
        return "diffuse scatter (0 dense islands)"
    cnt = _pd.Series(valid).value_counts()
    n_isl = int((cnt >= max(10, int(0.03 * len(coords)))).sum())
    top_sh = float(cnt.iloc[0] / len(coords)) * 100.0
    flag = " [MULTI-ISLAND: inspect separately]" if n_isl >= 2 and top_sh < 85.0 else ""
    return f"{n_isl} island(s), main={top_sh:.1f}%{flag}"

def _fast_de(target_bc, rest_bc):
    rng = _np.random.default_rng(0)
    t_idx = expr_barcodes.get_indexer(list(target_bc))
    t_idx = t_idx[t_idx >= 0]
    r_idx = expr_barcodes.get_indexer(list(rest_bc))
    r_idx = r_idx[r_idx >= 0]
    if len(t_idx) > 1500:
        t_idx = _np.sort(rng.choice(t_idx, 1500, replace=False))
    if len(r_idx) > 2500:
        r_idx = _np.sort(rng.choice(r_idx, 2500, replace=False))
    n_tot = expr_matrix.shape[0]
    w_t = _np.zeros(n_tot, dtype=_np.float64)
    w_r = _np.zeros(n_tot, dtype=_np.float64)
    w_t[t_idx] = 1.0 / max(len(t_idx), 1)
    w_r[r_idx] = 1.0 / max(len(r_idx), 1)
    mean_t = _np.asarray(w_t @ expr_matrix).ravel()
    mean_r = _np.asarray(w_r @ expr_matrix).ravel()
    diff = mean_t - mean_r
    cand = _np.flatnonzero(_np.abs(diff) > 0.15)
    if len(cand) > 80:
        cand = cand[_np.argsort(-_np.abs(diff[cand]))[:80]]
    if len(cand) == 0:
        return _pd.DataFrame(), _pd.DataFrame()
    sub_csc = expr_matrix[:, cand]
    X_t = sub_csc[t_idx, :].toarray()
    X_r = sub_csc[r_idx, :].toarray()
    pct_t = (X_t > 0).mean(axis=0) * 100.0
    pct_r = (X_r > 0).mean(axis=0) * 100.0
    rows = []
    n1, n2 = len(t_idx), len(r_idx)
    for j, g in enumerate(cand):
        if pct_t[j] < 5.0 and pct_r[j] < 5.0:
            continue
        u_stat, pval = _stats.mannwhitneyu(X_t[:, j], X_r[:, j], alternative="two-sided")
        rows.append({
            "gene": str(expr_genes[g]),
            "auc": round(float(u_stat / (n1 * n2)), 3),
            "diff": round(float(diff[g]), 2),
            "mean_in": round(float(mean_t[g]), 2),
            "mean_out": round(float(mean_r[g]), 2),
            "pct_in": round(float(pct_t[j]), 1),
            "pct_out": round(float(pct_r[j]), 1),
        })
    df_de = _pd.DataFrame(rows)
    if df_de.empty:
        return df_de, df_de
    return (
        df_de.sort_values(["auc", "diff"], ascending=[False, False]).head(_top_n),
        df_de.sort_values(["auc", "diff"], ascending=[True, True]).head(5),
    )

_qc_cols = [c for c in ("n_genes_by_counts", "total_counts", "pct_counts_mt", "doublet_score", "solo_prob",
                        "immune_content_equivalent", "endothelial_content_equivalent",
                        "epithelial_content_equivalent", "stromal_content_equivalent") if c in _df.columns]

print(f"=== Live Kernel | Round {round_picker.value} | Lens: {dataset_key} ({len(_df):,} cells) | Space: {lasso_space.value} | Preset: {preset_picker.value} ===")
for _name, _tbc in _groups:
    _mask = _df["barcode"].astype(str).isin(_tbc).to_numpy()
    _sub = _df.loc[_mask]
    _rest = _df.loc[~_mask]
    print(f"\n--- {_name} (n = {len(_sub):,} / {len(_df):,}, {100.0 * len(_sub) / max(len(_df), 1):.2f}%) ---")
    if len(_sub) == 0:
        continue
    print(f"Spatial cohesion: scVI UMAP = {_spatial_islands(_df, _mask, 'scvi_x', 'scvi_y')} | de-novo UMAP = {_spatial_islands(_df, _mask, 'x', 'y')}")
    _qc_parts = [f"{c}={_pd.to_numeric(_sub[c], errors='coerce').median():.2f} (rest {_pd.to_numeric(_rest[c], errors='coerce').median():.2f})" for c in _qc_cols]
    print("QC medians: " + " | ".join(_qc_parts))
    if "doublet_class" in _sub.columns:
        _vc = _sub["doublet_class"].astype(str).value_counts()
        print("Doublet class: " + ", ".join(f"{k}: {v} ({100.0*v/len(_sub):.1f}%)" for k, v in _vc.head(4).items()))
    for _c in ("saved_fine", "saved_action", "label_lineage", "label_parent", "label_fine", "label_state",
               "leiden_scvi_0.8", "leiden_scvi_1.2", "leiden_sub_0.8", "leiden_sub_1.2",
               "atlas_vote_fine", "runs_modal_fine"):
        if _c in _sub.columns:
            _vc = _sub[_c].astype(str).value_counts(dropna=False).head(5)
            print(f"  {_c}: " + ", ".join(f"{k}: {v} ({100.0*v/len(_sub):.1f}%)" for k, v in _vc.items()))
    if not _no_de and len(_sub) >= 5 and len(_rest) >= 5:
        _up, _dn = _fast_de(_tbc, _all_bc - _tbc)
        if not _up.empty:
            print("  Top UP markers: " + ", ".join(f"{r.gene} (auc={r.auc:.2f}, in={r.pct_in:.0f}%/{r.mean_in:.2f} vs {r.pct_out:.0f}%/{r.mean_out:.2f})" for r in _up.itertuples(index=False)))
        if not _dn.empty:
            print("  Top DOWN markers: " + ", ".join(f"{r.gene} (auc={r.auc:.2f}, in={r.pct_in:.0f}% vs {r.pct_out:.0f}%)" for r in _dn.itertuples(index=False)))

if not _no_de and len(_groups) == 2 and len(_groups[0][1]) >= 5 and len(_groups[1][1]) >= 5:
    _n0, _b0 = _groups[0]
    _n1, _b1 = _groups[1]
    _up01, _ = _fast_de(_b0, _b1)
    _up10, _ = _fast_de(_b1, _b0)
    print(f"\n=== Pairwise DE: {_n0} vs {_n1} ===")
    if not _up01.empty:
        print(f"  Higher in {_n0}: " + ", ".join(f"{r.gene} (auc={r.auc:.2f}, {r.pct_in:.0f}%/{r.mean_in:.2f} vs {r.pct_out:.0f}%/{r.mean_out:.2f})" for r in _up01.itertuples(index=False)))
    if not _up10.empty:
        print(f"  Higher in {_n1}: " + ", ".join(f"{r.gene} (auc={r.auc:.2f}, {r.pct_in:.0f}%/{r.mean_in:.2f} vs {r.pct_out:.0f}%/{r.mean_out:.2f})" for r in _up10.itertuples(index=False)))
"""


def find_exec_sh(repo: Path) -> Path:
    for candidate in (
        repo / ".agents/skills/marimo-pair/scripts/execute-code.sh",
        repo.parent / ".agents/skills/marimo-pair/scripts/execute-code.sh",
        Path("/workspaces/Meta-Aging/.agents/skills/marimo-pair/scripts/execute-code.sh"),
    ):
        if candidate.exists():
            return candidate
    raise FileNotFoundError("Could not locate marimo-pair/scripts/execute-code.sh")


def run_in_live_kernel(port: int, repo: Path, column: str, values: str, history_nodes: str, highlight: bool, top_n: int, no_de: bool) -> bool:
    """Execute the entire inspection inside the live marimo kernel's RAM (~1 second)."""
    token_file = Path.home() / ".config" / "marimo-tokens" / str(port)
    token = token_file.read_text().strip() if token_file.exists() else os.environ.get("MARIMO_TOKEN", "")
    exec_sh = find_exec_sh(repo)
    code = (
        IN_KERNEL_SCRIPT
        .replace("__COLUMN__", repr(column))
        .replace("__VALUES__", repr(values))
        .replace("__HISTORY_NODES__", repr(history_nodes))
        .replace("__HIGHLIGHT__", repr(bool(highlight)))
        .replace("__TOP_N__", repr(int(top_n)))
        .replace("__NO_DE__", repr(bool(no_de)))
    )
    env = {
        **os.environ,
        "PATH": f"/opt/venvs/base/bin:{os.environ.get('PATH', '/usr/local/bin:/usr/bin:/bin')}",
        "MARIMO_TOKEN": token,
    }
    res = subprocess.run(
        ["bash", str(exec_sh), "--url", f"http://127.0.0.1:{port}", "-"],
        input=code,
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=25,
    )
    if res.returncode == 0 and "=== Live Kernel |" in res.stdout:
        print(res.stdout.strip())
        return True
    return False


def main():
    if "nuclei" in globals() and "get_selection" in globals():
        # Guard against an agent passing this CLI script into execute-code.sh (which would self-deadlock via subprocess)
        code = (
            IN_KERNEL_SCRIPT
            .replace("__COLUMN__", repr("leiden_scvi_0.8"))
            .replace("__VALUES__", repr(""))
            .replace("__HISTORY_NODES__", repr(""))
            .replace("__HIGHLIGHT__", repr(False))
            .replace("__TOP_N__", repr(12))
            .replace("__NO_DE__", repr(False))
        )
        exec(code, globals())
        return
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="Dataset repo root (e.g. /workspaces/Meta-Aging/14782-DM)")
    parser.add_argument("--live-port", type=int, default=2782, help="Marimo port for in-RAM execution (default: 2782; pass 0 for offline disk mode)")
    parser.add_argument("--round", dest="round_id", type=str, default="3", help="Campaign round number (offline fallback)")
    parser.add_argument("--lens", type=str, default="endothelial", help="Lens key (offline fallback)")
    parser.add_argument("--column", type=str, default="leiden_scvi_0.8", help="Column to slice on when --values is given")
    parser.add_argument("--values", type=str, default="", help="Comma-separated values in --column, or 'ALL' (omit to inspect active browser lasso)")
    parser.add_argument("--history-nodes", type=str, default="", help="Comma-separated selection_history node indices (e.g. '18,22') to inspect/compare")
    parser.add_argument("--highlight", action="store_true", help="Highlight the inspected cells across all UMAP panels in the open browser tab")
    parser.add_argument("--top-n", type=int, default=12, help="Number of top upregulated DE markers to report")
    parser.add_argument("--no-de", action="store_true", help="Skip DE marker calculation")
    args = parser.parse_args()

    repo = args.repo.resolve()
    if args.live_port and args.live_port > 0:
        if run_in_live_kernel(args.live_port, repo, args.column, args.values, args.history_nodes, args.highlight, args.top_n, args.no_de):
            return
        if not args.values:
            raise RuntimeError(f"No active marimo session on port {args.live_port} and no --values given for offline fallback.")

    # Offline fallback when marimo server is not running
    import numpy as np
    import pandas as pd
    from scipy import sparse, stats
    from sklearn.cluster import DBSCAN

    os.chdir(repo)
    sys.path.insert(0, str(repo / "02_analysis"))
    from helpers.config import load_config

    cfg = load_config()
    camp = cfg["annotation_campaign"]
    pq_path = repo / camp["explorer_parquet"].format(round=args.round_id, lens=args.lens)
    df = pd.read_parquet(pq_path)
    df["barcode"] = df["barcode"].astype(str)
    q_path = repo / camp["reference_lookup"]["query_out"]
    if q_path.exists():
        q_df = pd.read_parquet(
            q_path,
            columns=["barcode", "atlas_vote_lineage", "atlas_vote_parent", "atlas_vote_fine", "runs_modal_fine", "runs_agree_fine", "atlas_nn_pctl"],
        ).set_index("barcode")
        for c in q_df.columns:
            if c not in df.columns:
                df[c] = q_df[c].reindex(df["barcode"]).to_numpy()

    expr_matrix = expr_barcodes = expr_genes = None
    if not args.no_de:
        npz_path = repo / camp["expr_sidecar_npz"]
        idx_path = repo / camp["expr_sidecar_index"]
        if npz_path.exists() and idx_path.exists():
            idx_data = json.loads(idx_path.read_text())
            expr_genes = pd.Index(idx_data["genes"])
            expr_barcodes = pd.Index(idx_data["barcodes"])
            expr_matrix = sparse.load_npz(npz_path).tocsc()

    ns = {
        "nuclei": df,
        "expr_matrix": expr_matrix,
        "expr_barcodes": expr_barcodes,
        "expr_genes": expr_genes,
        "round_picker": type("Obj", (), {"value": args.round_id})(),
        "dataset_key": args.lens,
        "lasso_space": type("Obj", (), {"value": "offline"})(),
        "preset_picker": type("Obj", (), {"value": "offline"})(),
        "get_selection": lambda: type("Sel", (), {"barcodes": frozenset()})(),
    }
    code = (
        IN_KERNEL_SCRIPT
        .replace("__COLUMN__", repr(args.column))
        .replace("__VALUES__", repr(args.values or "ALL"))
        .replace("__HISTORY_NODES__", repr(""))
        .replace("__HIGHLIGHT__", repr(False))
        .replace("__TOP_N__", repr(int(args.top_n)))
        .replace("__NO_DE__", repr(bool(args.no_de or expr_matrix is None)))
    )
    exec(code, ns)


if __name__ == "__main__":
    main()
