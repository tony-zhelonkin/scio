#!/usr/bin/env bash
# tests/test_validate_results_layout.sh — opt-in `--check results-layout`.
#
# Tests:
#   1. CONFORMANT project (stage-based figure + sibling table) → exit 0
#      default AND under --strict.
#   2. VIOLATION project (artifact at results root; unknown stage; figure with
#      no same-stem table neighbor) → default exit 0 with WARNs on stderr;
#      --strict exit 1.
#   3. No-false-positive: `--check all` on conformant → exit 0.
#   4. Empty 03_results / absent 03_results → clean no-op (exit 0).
set -u
. "$(dirname "$0")/_lib.sh"

setup_tmpdir
FAKE="$TMPDIR_TEST/fake-toolkit"
build_fake_toolkit "$FAKE"
export SCIO_TOOLKIT="$FAKE"
SCIO="$FAKE/bin/scio"

write_config() {
    local p="$1"
    mkdir -p "$p/02_analysis/config"
    cat > "$p/02_analysis/config/analysis_config.yaml" <<'YAML'
figures:
  base_size: 16
  overview_dir: "_overview"
stages:
  - id: "01_qc"
    title: "QC"
paths:
  results: "03_results/"
YAML
}

# ---------------------------------------------------------------------------
# Test 1: conformant.
# ---------------------------------------------------------------------------
CONF="$TMPDIR_TEST/conf"
write_config "$CONF"
mkdir -p "$CONF/03_results/01_qc/figures/_overview" "$CONF/03_results/01_qc/tables/_overview"
touch "$CONF/03_results/01_qc/figures/_overview/qc_counts.screen.png"
touch "$CONF/03_results/01_qc/tables/_overview/qc_counts.csv"
# Sanctioned roots that must NOT be flagged.
mkdir -p "$CONF/03_results/objects" "$CONF/03_results/master" "$CONF/03_results/_scratch"
touch "$CONF/03_results/objects/qc.h5ad"
touch "$CONF/03_results/master/de.csv"
touch "$CONF/03_results/_scratch/scratch.png"   # exempt ephemeral zone

set +e
out=$("$SCIO" lint --check results-layout --strict --project-dir "$CONF" 2>&1); rc=$?
set -e
[[ "$rc" -eq 0 ]] || { echo "FAIL [$_TEST_NAME] test1: conformant strict exit $rc"; printf '%s\n' "$out" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Test 2: violation — root artifact, unknown stage, figure w/o table.
# ---------------------------------------------------------------------------
VIOL="$TMPDIR_TEST/viol"
write_config "$VIOL"
mkdir -p "$VIOL/03_results/01_qc/figures/_overview" "$VIOL/03_results/99_bad/figures"
touch "$VIOL/03_results/loose.png"                                  # at results root
touch "$VIOL/03_results/99_bad/figures/x.png"                       # unknown stage + no table
touch "$VIOL/03_results/01_qc/figures/_overview/orphan.screen.png"  # no sibling table

set +e
out=$("$SCIO" lint --check results-layout --project-dir "$VIOL" 2>&1); rc=$?
set -e
[[ "$rc" -eq 0 ]] || { echo "FAIL [$_TEST_NAME] test2: violation default expected 0 got $rc"; printf '%s\n' "$out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q 'WARN results-layout:.*artifact at 03_results/ root: loose.png' \
    || { echo "FAIL [$_TEST_NAME] test2: expected root-artifact WARN"; printf '%s\n' "$out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "WARN results-layout:.*unknown stage '99_bad'" \
    || { echo "FAIL [$_TEST_NAME] test2: expected unknown-stage WARN"; printf '%s\n' "$out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q 'WARN results-layout:.*figure without a source table.*orphan' \
    || { echo "FAIL [$_TEST_NAME] test2: expected orphan-figure WARN"; printf '%s\n' "$out" >&2; exit 1; }

# WARNs must be on stderr.
set +e
serr=$("$SCIO" lint --check results-layout --project-dir "$VIOL" 2>&1 1>/dev/null)
set -e
printf '%s\n' "$serr" | grep -q 'WARN results-layout:' \
    || { echo "FAIL [$_TEST_NAME] test2: WARN must be on stderr"; printf '%s\n' "$serr" >&2; exit 1; }

set +e
out=$("$SCIO" lint --check results-layout --strict --project-dir "$VIOL" 2>&1); rc=$?
set -e
[[ "$rc" -eq 1 ]] || { echo "FAIL [$_TEST_NAME] test2: violation strict expected 1 got $rc"; printf '%s\n' "$out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q 'ERROR results-layout:' \
    || { echo "FAIL [$_TEST_NAME] test2: expected ERROR under strict"; printf '%s\n' "$out" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Test 3: no-false-positive — `--check all` on conformant.
# ---------------------------------------------------------------------------
# Add captions so the captions check also passes cleanly under --check all.
cat > "$CONF/03_results/01_qc/README.md" <<'MD'
# 01_qc

## figures/_overview/qc_counts.screen.png

F.

**How to read:** x.

| Script | Function | Config | Input |
|---|---|---|---|
| `02_analysis/scripts/10_qc_viz.py` | `f` | `c` | `i` |

## tables/_overview/qc_counts.csv

T.

**How to read:** x.

| Script | Function | Config | Input |
|---|---|---|---|
| `02_analysis/scripts/10_qc_viz.py` | `f` | `c` | `i` |
MD
mkdir -p "$CONF/02_analysis/scripts"
echo "print('viz')" > "$CONF/02_analysis/scripts/10_qc_viz.py"
# Compute sibling: doc 09 §3.3 rule 3 (orphan viz) requires a same-number,
# same-stem compute stage. Without it this fixture is itself non-conformant.
echo "print('qc')" > "$CONF/02_analysis/scripts/10_qc.py"
git -C "$CONF" init -q
git -C "$CONF" config user.email t@e.com
git -C "$CONF" config user.name T
git -C "$CONF" add -A
git -C "$CONF" commit -qm init

set +e
out=$("$SCIO" lint --check all --strict --project-dir "$CONF" 2>&1); rc=$?
set -e
[[ "$rc" -eq 0 ]] || { echo "FAIL [$_TEST_NAME] test3: --check all conformant exit $rc"; printf '%s\n' "$out" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Test 4: absent / empty 03_results → clean no-op.
# ---------------------------------------------------------------------------
EMPTY="$TMPDIR_TEST/empty"
mkdir -p "$EMPTY"
set +e
out=$("$SCIO" lint --check results-layout --strict --project-dir "$EMPTY" 2>&1); rc=$?
set -e
[[ "$rc" -eq 0 ]] || { echo "FAIL [$_TEST_NAME] test4: empty project exit $rc"; printf '%s\n' "$out" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Test 5: the new `scio lint --check` surface covers the same ground.
# ---------------------------------------------------------------------------
set +e
out=$("$SCIO" lint --check results-layout --strict --project-dir "$VIOL" 2>&1); rc=$?
set -e
[[ "$rc" -eq 1 ]] || { echo "FAIL [$_TEST_NAME] test5: lint --check results-layout strict expected 1 got $rc"; printf '%s\n' "$out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q 'ERROR results-layout:' \
    || { echo "FAIL [$_TEST_NAME] test5: expected ERROR from lint --check under strict"; printf '%s\n' "$out" >&2; exit 1; }

pass
