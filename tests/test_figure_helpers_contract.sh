#!/usr/bin/env bash
# tests/test_figure_helpers_contract.sh — the figure-style contract (lib/figure-style/).
#
# Validates the cross-language figure-style contract WITHOUT a plotting toolchain:
#   (a) Parity check (static): every contract function name is present in BOTH
#       figure_helpers.R and figure_helpers.py (fail if any missing from either).
#   (b) Python dependency-free execution: in a tmpdir with a minimal analysis_config.yaml,
#       python3 imports the module (proves no top-level heavy imports), then exercises
#       overview_path/contrast_path (dirs created with _overview/by_contrast names),
#       write_caption x2 for the same file (idempotent: exactly ONE section; has a
#       "How to read" heading + the Script/Function/Config/Input table),
#       append_master_table x2 for the same database (rows REPLACED, not duplicated),
#       and round_numeric_cols (9-sig rounding).
#   (c) Graceful skip: if matplotlib is absent, the real plotting paths are NOT executed
#       (validated structurally only) and the test still passes on this bare box.
set -u
. "$(dirname "$0")/_lib.sh"

LIB="$TOOLKIT_ROOT/lib/figure-style"
R_FILE="$LIB/figure_helpers.R"
PY_FILE="$LIB/figure_helpers.py"

assert_file_exists "$R_FILE" "R helper missing"
assert_file_exists "$PY_FILE" "Python helper missing"

# ---------------------------------------------------------------------------
# (a) PARITY CHECK (static, no toolchain): every contract name in BOTH files.
# ---------------------------------------------------------------------------
CONTRACT_NAMES=(
    project_theme set_paper_style save_figure save_overview
    contrast_path overview_path style_series purge_figures
    write_caption append_master_table round_numeric_cols direction_cue
    rasterize_axes
)

for name in "${CONTRACT_NAMES[@]}"; do
    # R: `name <- function(` ; Python: `def name(`  — accept either definition form so the
    # same name list checks both files. Word-boundary anchored to avoid substring matches.
    if ! grep -Eq "(^|[^A-Za-z0-9_.])${name}[[:space:]]*(<-|=)[[:space:]]*function" "$R_FILE"; then
        echo "FAIL [$_TEST_NAME] parity: '$name' not defined in figure_helpers.R" >&2
        exit 1
    fi
    if ! grep -Eq "^[[:space:]]*def[[:space:]]+${name}[[:space:]]*\(" "$PY_FILE"; then
        echo "FAIL [$_TEST_NAME] parity: '$name' not defined in figure_helpers.py" >&2
        exit 1
    fi
done
echo "  parity: all ${#CONTRACT_NAMES[@]} contract names present in BOTH R and Python"

# ---------------------------------------------------------------------------
# Fixture: a tmpdir with a minimal analysis_config.yaml (figures + stages + paths).
# ---------------------------------------------------------------------------
setup_tmpdir
cp "$PY_FILE" "$TMPDIR_TEST/figure_helpers.py"

cat > "$TMPDIR_TEST/analysis_config.yaml" <<'EOF'
figures:
  base_size: 14
  caption_wrap_column: 70
  by_contrast_dir: "by_contrast"
  overview_dir: "_overview"
  formats: [pdf, png]
stages:
  - id: "04_gsea"
paths:
  results: "03_results/"
  master: "03_results/master/"
  stage_tables_subdir: "tables"
  stage_figures_subdir: "figures"
EOF

# Sanity: python3 + pyyaml available (the only hard dep). If pyyaml is somehow absent,
# skip gracefully rather than fail the bare-box suite.
if ! python3 -c "import yaml" 2>/dev/null; then
    echo "SKIP: pyyaml absent — figure-style Python execution not exercised"
    pass
    exit 0
fi

# ---------------------------------------------------------------------------
# (b) PYTHON DEPENDENCY-FREE EXECUTION: import + call the no-backend functions.
# Run inside the tmpdir so relative results paths resolve there.
# ---------------------------------------------------------------------------
set +e
PY_OUT=$(cd "$TMPDIR_TEST" && python3 - <<'PYEOF' 2>&1
import sys
sys.path.insert(0, ".")
import figure_helpers as fh          # MUST import with stdlib + pyyaml only (no heavy top-level)

cfg = fh.load_figure_config("analysis_config.yaml")

# --- paths: dirs created with _overview / by_contrast names -----------------
op = fh.overview_path("04_gsea", "figures", config=cfg)
cp = fh.contrast_path("04_gsea", "Treatment_vs_Control", "tables", config=cfg)
assert op.is_dir() and op.name == "_overview", f"overview_path wrong: {op}"
assert cp.is_dir() and "by_contrast" in str(cp) and cp.name == "Treatment_vs_Control", f"contrast_path wrong: {cp}"

# --- write_caption x2 same file: idempotent (ONE section) -------------------
fname = "figures/_overview/gsea_hallmark_heatmap.png"
for _ in range(2):
    rm = fh.write_caption(
        "04_gsea", fname,
        finding="Hallmark IFN-alpha and IFN-gamma dominate the response.",
        script="02_analysis/stages/11_gsea_viz.py", fn="save_overview",
        config_kv="figures.nes_cap = 3.5", input="03_results/objects/gsea.rds",
        how_to_read="Color = NES (orange up / blue down); arrows mark direction.",
        config=cfg)
txt = rm.read_text()
nsec = txt.count("## " + fname)
assert nsec == 1, f"caption not idempotent: {nsec} sections for {fname}"
assert "How to read" in txt, "caption missing 'How to read' section"
assert "| Script | Function | Config | Input |" in txt, "caption missing Script/Function/Config/Input table"

# a DIFFERENT file must not clobber the first
fh.write_caption("04_gsea", "figures/_overview/other.png", finding="Second artifact.",
                 script="s.py", fn="f", config_kv="k=v", input="i", how_to_read="hr", config=cfg)
txt = rm.read_text()
assert txt.count("## " + fname) == 1, "first caption lost after writing a second"
assert txt.count("## figures/_overview/other.png") == 1, "second caption missing"

# --- write_caption with a master source: a **Source:** line, no table copy ---
rm = fh.write_caption("04_gsea", "figures/_overview/vs_master.png", finding="Third artifact.",
                      script="s.py", fn="f", config_kv="k=v", input="i", how_to_read="hr",
                      config=cfg, source="tables/gsea_master.csv",
                      slice='contrast == "KO_vs_WT" & padj < 0.05')
txt = rm.read_text()
assert '**Source:** `tables/gsea_master.csv` where contrast == "KO_vs_WT" & padj < 0.05' in txt, \
    "caption missing the **Source:** line for a master-sliced figure"
fh.write_caption("04_gsea", "figures/_overview/vs_master.png", finding="Third artifact.",
                 script="s.py", fn="f", config_kv="k=v", input="i", how_to_read="hr", config=cfg)
assert "**Source:**" not in rm.read_text().split("## figures/_overview/vs_master.png")[1], \
    "a caption written without source= must not keep a stale Source line"

# --- append_master_table x2 same database: rows REPLACED not duplicated -----
fh.append_master_table([{"pathway": "A", "nes": 1.5}, {"pathway": "B", "nes": -2.0}],
                       database="Hallmark", stage="04_gsea", name="master_gsea", config=cfg)
fh.append_master_table([{"pathway": "C", "nes": 3.0}],
                       database="Hallmark", stage="04_gsea", name="master_gsea", config=cfg)
import csv
with open("03_results/master/master_gsea.csv") as f:
    rows = list(csv.DictReader(f))
paths = [r["pathway"] for r in rows]
assert paths == ["C"], f"master rows not REPLACED on re-run for same database: {paths}"
# a second database accumulates (not clobbered)
fh.append_master_table([{"pathway": "K", "nes": 1.0}],
                       database="KEGG", stage="04_gsea", name="master_gsea", config=cfg)
with open("03_results/master/master_gsea.csv") as f:
    rows = list(csv.DictReader(f))
dbs = sorted({r["database"] for r in rows})
assert dbs == ["Hallmark", "KEGG"], f"second database not accumulated: {dbs}"

# --- round_numeric_cols: 9 significant digits ------------------------------
r = fh.round_numeric_cols([{"v": 1.23456789012, "s": "keepme"}], sig=9)
assert r[0]["v"] == 1.23456789, f"9-sig rounding wrong: {r[0]['v']}"
assert r[0]["s"] == "keepme", "non-numeric column should pass through unchanged"

# --- direction_cue: unambiguous, never a bare '*' --------------------------
assert fh.direction_cue(2.0).startswith("↑"), "positive cue should be an up arrow"
assert fh.direction_cue(-1.0).startswith("↓"), "negative cue should be a down arrow"
assert "*" not in fh.direction_cue(1.0), "direction cue must not be a bare '*'"

print("PY_CONTRACT_OK")
PYEOF
)
PY_RC=$?
set -e

if [[ "$PY_RC" -ne 0 ]] || ! printf '%s\n' "$PY_OUT" | grep -q 'PY_CONTRACT_OK'; then
    echo "FAIL [$_TEST_NAME] python dependency-free execution failed:" >&2
    printf '%s\n' "$PY_OUT" >&2
    exit 1
fi
echo "  python: import + path/caption/master/round/cue execution OK (no heavy deps)"

# ---------------------------------------------------------------------------
# (c) GRACEFUL SKIP: real plotting paths only validated structurally on a bare box.
# ---------------------------------------------------------------------------
if ! python3 -c "import matplotlib" 2>/dev/null; then
    echo "SKIP: matplotlib absent — plotting paths not executed (validated structurally only)"
fi

pass
