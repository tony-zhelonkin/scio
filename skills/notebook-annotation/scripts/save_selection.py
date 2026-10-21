#!/usr/bin/env python3
"""Save a selection into the campaign manifest, CSVs, and provenance, and refresh the live marimo overlay.

Fast path (--live-port <PORT>, ~1 second): executes directly inside the live marimo kernel using
its in-RAM `nuclei`, `persist_selection`, `resolve_claim`, and `set_registry_version` (zero disk reload).
Supports `--from-live-lasso` (with optional `--exclude-column` / `--exclude-values` to trim spillover
clusters before saving) as well as `--column` / `--values` rule selections.

Usage examples:
  # 1) Save the user's current live lasso on port 2782, trimming spillover clusters 10,11 (~1s):
  /opt/venvs/base/bin/python save_selection.py --live-port 2782 --from-live-lasso \
    --exclude-column leiden_scvi_0.8 --exclude-values 10,11 \
    --name lymphatic-ec-round3 --action relabel --level fine --new-label "Lymphatic EC" \
    --new-state Unresolved --priority 200 \
    --rationale "lymphatic endothelial cells in leiden_scvi_0.8 cluster 15: high Prox1, Ccl21a, Mmrn1, Reln, Flt4 with endothelial Pecam1, Cdh5."

  # 2) Save a drop selection by cluster rule in the live kernel (~1s):
  /opt/venvs/base/bin/python save_selection.py --live-port 2782 \
    --name immune-doublets-round3 --action drop --priority 1000 \
    --column leiden_scvi_0.8 --values 10,11 \
    --rationale "heterotypic immune and endothelial doublets in leiden_scvi_0.8 clusters 10 and 11: high doublet_score and solo_prob, coexpressing Pecam1, Cdh5 with Ptprc, Dock2."
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

BANNED_PUNCTUATION = ("—", "–", "·")

IN_KERNEL_SAVE_SCRIPT = r"""
_from_lasso = __FROM_LASSO__
_col = __COLUMN__
_vals = [v.strip() for v in __VALUES__.split(",") if v.strip()]
_ex_col = __EX_COLUMN__
_ex_vals = [v.strip() for v in __EX_VALUES__.split(",") if v.strip()]
_name = __NAME__
_action = __ACTION__
_level = __LEVEL__
_new_label = __NEW_LABEL__
_new_state = __NEW_STATE__
_parent = __PARENT__
_prio = int(__PRIORITY__)
_mode = __MODE__
_rationale = __RATIONALE__

if _from_lasso:
    _base_sel = get_selection()
    _bc = set(_base_sel.barcodes) & set(nuclei["barcode"].astype(str))
    if _ex_col and _ex_vals and _ex_col in nuclei.columns:
        _drop_bc = set(nuclei.loc[nuclei[_ex_col].astype(str).isin(_ex_vals), "barcode"].astype(str))
        _bc = _bc - _drop_bc
    _bc_f = frozenset(_bc)
    _steps = _base_sel.steps if (_base_sel.steps and len(_bc_f) == len(_base_sel.barcodes)) else (
        sel.Step(op="replace", writer="lasso", panel="A1", lens=str(dataset_key),
                 space_drawn=str(lasso_space.value), round=str(round_picker.value),
                 n_in=len(_bc_f), n_after=len(_bc_f)),
    )
    _sel_obj = sel.Selection(barcodes=_bc_f, steps=_steps)
else:
    _bc_f = frozenset(nuclei.loc[nuclei[_col].astype(str).isin(_vals), "barcode"].astype(str))
    if _ex_col and _ex_vals and _ex_col in nuclei.columns:
        _drop_bc = set(nuclei.loc[nuclei[_ex_col].astype(str).isin(_ex_vals), "barcode"].astype(str))
        _bc_f = frozenset(_bc_f - _drop_bc)
    _step = sel.Step(op="replace", writer="rule", panel="rule", lens=str(dataset_key),
                     space_drawn="rule", round=str(round_picker.value),
                     n_in=len(_bc_f), n_after=len(_bc_f))
    _sel_obj = sel.Selection(barcodes=_bc_f, steps=(_step,))

if not len(_sel_obj.barcodes):
    raise ValueError("Selection holds 0 cells after filtering; refusing to save.")

_claim = {"level": _level, "label": _new_label, "state": _new_state, "text": f"{_level} = {_new_label}" + (f" · state = {_new_state}" if _new_state else ""), "error": None, "new_rows": []}
if _action == "relabel":
    _vocab = read_vocabulary(VOCAB_PATH)
    _known = set(_vocab.loc[_vocab["level"].eq(_level), "label"]) | {UNRESOLVED}
    if _new_label not in _known:
        if _level in ("parent", "fine") and not _parent:
            raise ValueError(f"{_level}={_new_label!r} is absent from vocabulary; pass --parent to add it.")
        _claim["new_rows"].append({"level": _level, "label": _new_label, "parent": _parent})

_frame_sub = nuclei.loc[nuclei["barcode"].astype(str).isin(_sel_obj.barcodes)]
_csv_path, _err, _summary, _warn = persist_selection(
    _frame_sub, _name, str(dataset_key), _sel_obj, SELECTION_DIR, MANIFEST_PATH,
    _action, _claim, _prio, _rationale, SELECTION_ACTIONS, _mode, round_picker.value, VOCAB_PATH,
)
if _err:
    raise RuntimeError(_err)
set_registry_version(lambda _v: _v + 1)
print("LIVE_SAVED:" + str(_summary))
"""


def validate_rationale(text: str) -> str:
    clean = " ".join(str(text).split())
    if not clean:
        raise ValueError("Rationale must be non-empty.")
    found = [ch for ch in BANNED_PUNCTUATION if ch in clean]
    if found:
        raise ValueError(
            f"Rationale contains banned punctuation {found}; use only ',', '.', or ':' in affirmative prose."
        )
    return clean


def find_exec_sh(repo: Path) -> Path:
    for candidate in (
        repo / ".agents/skills/marimo-pair/scripts/execute-code.sh",
        repo.parent / ".agents/skills/marimo-pair/scripts/execute-code.sh",
        Path("/workspaces/Meta-Aging/.agents/skills/marimo-pair/scripts/execute-code.sh"),
    ):
        if candidate.exists():
            return candidate
    raise FileNotFoundError("Could not locate marimo-pair/scripts/execute-code.sh")


def save_in_live_kernel(args, repo: Path, rationale: str) -> bool:
    token_file = Path.home() / ".config" / "marimo-tokens" / str(args.live_port)
    token = token_file.read_text().strip() if token_file.exists() else os.environ.get("MARIMO_TOKEN", "")
    exec_sh = find_exec_sh(repo)
    code = (
        IN_KERNEL_SAVE_SCRIPT
        .replace("__FROM_LASSO__", repr(bool(args.from_live_lasso)))
        .replace("__COLUMN__", repr(args.column))
        .replace("__VALUES__", repr(args.values))
        .replace("__EX_COLUMN__", repr(args.exclude_column))
        .replace("__EX_VALUES__", repr(args.exclude_values))
        .replace("__NAME__", repr(args.name))
        .replace("__ACTION__", repr(args.action))
        .replace("__LEVEL__", repr(args.level))
        .replace("__NEW_LABEL__", repr(args.new_label))
        .replace("__NEW_STATE__", repr(args.new_state))
        .replace("__PARENT__", repr(args.parent))
        .replace("__PRIORITY__", repr(int(args.priority)))
        .replace("__MODE__", repr(args.mode))
        .replace("__RATIONALE__", repr(rationale))
    )
    env = {
        **os.environ,
        "PATH": f"/opt/venvs/base/bin:{os.environ.get('PATH', '/usr/local/bin:/usr/bin:/bin')}",
        "MARIMO_TOKEN": token,
    }
    res = subprocess.run(
        ["bash", str(exec_sh), "--url", f"http://127.0.0.1:{args.live_port}", "-"],
        input=code,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode == 0 and "LIVE_SAVED:" in res.stdout:
        for line in res.stdout.splitlines():
            if line.startswith("LIVE_SAVED:"):
                print(line.removeprefix("LIVE_SAVED:"))
        return True
    if res.stderr and "No active sessions" not in res.stderr:
        raise RuntimeError(f"Live kernel save failed:\n{res.stdout}\n{res.stderr}")
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="Dataset repo root")
    parser.add_argument("--live-port", type=int, default=2782, help="Marimo port for in-RAM save + overlay refresh (default: 2782; pass 0 for offline)")
    parser.add_argument("--from-live-lasso", action="store_true", help="Save the user's currently lassoed selection in --live-port")
    parser.add_argument("--exclude-column", type=str, default="", help="Optional column to exclude spillover cells before saving (e.g. leiden_scvi_0.8)")
    parser.add_argument("--exclude-values", type=str, default="", help="Comma-separated values in --exclude-column to exclude before saving (e.g. 10,11)")
    parser.add_argument("--round", dest="round_id", type=str, default="3", help="Campaign round number (offline mode)")
    parser.add_argument("--lens", type=str, default="endothelial", help="Lens scope (offline mode)")
    parser.add_argument("--name", type=str, required=True, help="Selection stem name (saved as <name>_<lens>)")
    parser.add_argument("--action", choices=["drop", "relabel", "keep"], required=True)
    parser.add_argument("--level", choices=["", "lineage", "parent", "fine", "state"], default="")
    parser.add_argument("--new-label", type=str, default="")
    parser.add_argument("--new-state", type=str, default="")
    parser.add_argument("--parent", type=str, default="", help="Parent label if registering a new parent/fine label")
    parser.add_argument("--priority", type=int, default=200)
    parser.add_argument("--mode", choices=["append", "replace"], default="replace")
    parser.add_argument("--column", type=str, default="leiden_scvi_0.8", help="Rule column when not --from-live-lasso")
    parser.add_argument("--values", type=str, default="", help="Comma-separated values in --column")
    parser.add_argument("--rationale", type=str, required=True, help="Affirmative rationale using only ',', '.', or ':'")
    args = parser.parse_args()

    rationale = validate_rationale(args.rationale)
    repo = args.repo.resolve()
    if args.name.endswith(f"_{args.lens}"):
        args.name = args.name[: -len(f"_{args.lens}")]

    if args.live_port and args.live_port > 0:
        if save_in_live_kernel(args, repo, rationale):
            return
        if args.from_live_lasso:
            raise RuntimeError(f"No active marimo session on port {args.live_port} for --from-live-lasso.")

    import pandas as pd

    os.chdir(repo)
    sys.path.insert(0, str(repo / "02_analysis"))
    from helpers import selection as sel
    from helpers.config import load_config
    from helpers.round_roster import MANIFEST_COLUMNS, read_manifest

    cfg = load_config()
    camp = cfg["annotation_campaign"]
    output_dir = repo / camp["selections_dir"]
    manifest_path = repo / camp["selections_manifest"]
    vocab_path = repo / camp["label_vocabulary"]
    round_id, lens = args.round_id, args.lens

    pq_path = repo / camp["explorer_parquet"].format(round=round_id, lens=lens)
    nuclei = pd.read_parquet(pq_path)
    vals = [v.strip() for v in args.values.split(",") if v.strip()]
    if not vals:
        raise ValueError("Provide --values <v1,v2> or --from-live-lasso")
    bc = set(nuclei.loc[nuclei[args.column].astype(str).isin(vals), "barcode"].astype(str))
    if args.exclude_column and args.exclude_values and args.exclude_column in nuclei.columns:
        ex_vals = [v.strip() for v in args.exclude_values.split(",") if v.strip()]
        bc -= set(nuclei.loc[nuclei[args.exclude_column].astype(str).isin(ex_vals), "barcode"].astype(str))
    barcodes_set = frozenset(bc)
    if not barcodes_set:
        raise ValueError("Selection holds 0 cells; refusing to save.")

    if args.action == "relabel":
        if not args.level or not args.new_label:
            raise ValueError("relabel requires --level and --new-label")
        if vocab_path.exists():
            vocab = pd.read_csv(vocab_path, dtype=str, keep_default_na=False)
            known = set(vocab.loc[vocab["level"] == args.level, "label"]) | {camp["vocabulary"]["unresolved"]}
            if args.new_label not in known:
                if not args.parent and args.level in ("parent", "fine"):
                    raise ValueError(f"{args.level}={args.new_label!r} is absent from {vocab_path.name}; pass --parent to add it.")
                added = datetime.now(timezone.utc).isoformat(timespec="seconds")
                new_row = pd.DataFrame([{
                    "level": args.level, "label": args.new_label, "parent": args.parent,
                    "source": f"{args.name}_{lens}", "added_at_utc": added,
                }])
                pd.concat([vocab, new_row], ignore_index=True).to_csv(vocab_path, index=False)

    step = sel.Step(
        op="replace", writer="rule", panel="rule", lens=lens, space_drawn="rule",
        round=str(round_id), n_in=len(barcodes_set), n_after=len(barcodes_set),
    )
    selection_id = f"{args.name}_{lens}"
    selection = sel.Selection(barcodes=barcodes_set, steps=(step,))
    provenance = sel.manifest_provenance(selection)

    preferred = [
        "barcode", "label_lineage", "label_parent", "label_fine", "label_state",
        "leiden_sub_0.8", "leiden_ccfree_0.8", "leiden_scvi_0.8", "condition", "mouse_id",
    ]
    cols = [c for c in preferred if c in nuclei.columns]
    out = nuclei.loc[nuclei["barcode"].astype(str).isin(barcodes_set), cols].copy()
    out["source_brush"] = provenance["source_brush"]
    out["selection_id"] = selection_id
    out = out.sort_values("barcode").reset_index(drop=True)

    output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = output_dir / f"{selection_id}.csv"
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    if csv_path.exists():
        hist_dir = output_dir / "_history"
        hist_dir.mkdir(parents=True, exist_ok=True)
        (hist_dir / f"{selection_id}__{stamp}.csv").write_bytes(csv_path.read_bytes())
        if args.mode == "append":
            prior_df = pd.read_csv(csv_path, dtype=str)
            out = pd.concat([prior_df, out.astype("string")], ignore_index=True).drop_duplicates("barcode", keep="first")
    out.to_csv(csv_path, index=False)

    saved_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    row = {
        "selection_id": selection_id,
        "lens": lens,
        "action": args.action,
        "level": args.level if args.action == "relabel" else "",
        "new_label": args.new_label if args.action == "relabel" else "",
        "new_state": args.new_state if args.action == "relabel" else "",
        "priority": int(args.priority),
        "rationale": rationale,
        "n_cells": len(out),
        "saved_at_utc": saved_at,
        "notebook": "41_annotation_lenses_explore",
        "source_brush": provenance["source_brush"],
        "status": "active",
        "round": str(round_id),
        "lasso_space": provenance["lasso_space"],
    }
    manifest = read_manifest(manifest_path)
    manifest = manifest.loc[manifest["selection_id"].astype(str) != selection_id]
    manifest = pd.concat([manifest[MANIFEST_COLUMNS], pd.DataFrame([row])], ignore_index=True)
    manifest["priority"] = pd.to_numeric(manifest["priority"], errors="coerce").astype("Int64")
    manifest = manifest.sort_values(["priority", "selection_id"], ascending=[False, True])
    manifest.to_csv(manifest_path, index=False)

    steps_path = output_dir / "_provenance" / f"{selection_id}.csv"
    steps_path.parent.mkdir(parents=True, exist_ok=True)
    steps = sel.provenance_rows(selection).astype(str)
    steps.insert(0, "save_mode", args.mode)
    steps.insert(0, "saved_at_utc", saved_at)
    steps.to_csv(steps_path, index=False)
    print(f"[saved] {selection_id}: {len(out):,} cells ({args.action}, priority={args.priority})")


if __name__ == "__main__":
    main()
