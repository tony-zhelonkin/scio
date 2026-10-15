#!/usr/bin/env bash
# tests/test_results_master_source.sh — a figure may cite a master table and the
# slice that selects it instead of owning a same-stem table.
#
#   1. A figure whose caption cites an existing master with real slice columns
#      passes strict, with no same-stem table beside it.
#   2. A caption citing a missing file, a slice on a column the master lacks,
#      or no Source line at all each fail, naming the reason.
#   3. In a stage that keeps a master, a table nothing cites is reported.
#   4. A stage still on same-stem tables stays quiet: no master, no orphan rule.
set -u
. "$(dirname "$0")/_lib.sh"

setup_tmpdir
FAKE="$TMPDIR_TEST/fake-toolkit"
build_fake_toolkit "$FAKE"
export SCIO_TOOLKIT="$FAKE"
SCIO="$FAKE/bin/scio"

mkproj() {
    local p="$1"
    mkdir -p "$p/02_analysis/config" "$p/03_results/01_de/figures/_overview" "$p/03_results/01_de/tables"
    cat > "$p/02_analysis/config/analysis_config.yaml" <<'YAML'
figures:
  base_size: 16
stages:
  - id: "01_de"
    title: "DE"
YAML
    printf 'contrast,gene,logFC,padj\nKO_vs_WT,Il6,1.2,0.01\n' > "$p/03_results/01_de/tables/de_master.csv"
    touch "$p/03_results/01_de/figures/_overview/volcano.png"
}
caption() {  # caption <project> <source-line>
    printf '# 01_de\n\n## figures/_overview/volcano.png\n\nF.\n\n**How to read:** x.\n\n%s\n' "$2" \
        > "$1/03_results/01_de/README.md"
}
lint() { "$SCIO" lint --check results-layout --strict --project-dir "$1" 2>&1; }

# 1. a cited master with real columns is a source
P1="$TMPDIR_TEST/ok"; mkproj "$P1"
caption "$P1" '**Source:** `tables/de_master.csv` where contrast == "KO_vs_WT" & padj < 0.05'
out=$(lint "$P1"); rc=$?
[[ "$rc" -eq 0 ]] || { echo "FAIL [$_TEST_NAME] cited master rejected"; printf '%s\n' "$out" >&2; exit 1; }

# 2. each way the pointer can be false
expect_fail() {  # expect_fail <label> <caption-source-line|-> <pattern>
    local p="$TMPDIR_TEST/bad_$1"; mkproj "$p"
    if [[ "$2" == "-" ]]; then caption "$p" ""; else caption "$p" "$2"; fi
    out=$(lint "$p"); rc=$?
    [[ "$rc" -eq 1 ]] || { echo "FAIL [$_TEST_NAME] $1: expected exit 1 got $rc"; printf '%s\n' "$out" >&2; exit 1; }
    printf '%s\n' "$out" | grep -q "$3" || { echo "FAIL [$_TEST_NAME] $1: missing reason '$3'"; printf '%s\n' "$out" >&2; exit 1; }
}
expect_fail nosrc  "-" 'no same-stem table and no \*\*Source:\*\*'
expect_fail nofile '**Source:** `tables/gone.csv` where contrast == "x"' 'does not exist under the stage'
expect_fail nocol  '**Source:** `tables/de_master.csv` where cluster == "3"' "'cluster'.*not a column"

# 3. a master-form stage reports a table nothing reads
P3="$TMPDIR_TEST/orphan"; mkproj "$P3"
caption "$P3" '**Source:** `tables/de_master.csv` where contrast == "KO_vs_WT"'
printf 'a,b\n1,2\n' > "$P3/03_results/01_de/tables/stray.csv"
out=$(lint "$P3"); rc=$?
[[ "$rc" -eq 1 ]] && printf '%s\n' "$out" | grep -q 'nothing reads\|no caption cites' \
    || { echo "FAIL [$_TEST_NAME] orphan table not reported (rc=$rc)"; printf '%s\n' "$out" >&2; exit 1; }

# 4. no master, no orphan rule: an unread same-stem-era table is not reported
P4="$TMPDIR_TEST/legacy"; mkproj "$P4"; rm "$P4/03_results/01_de/tables/de_master.csv"
printf 'a,b\n1,2\n' > "$P4/03_results/01_de/tables/volcano.csv"
printf 'a,b\n1,2\n' > "$P4/03_results/01_de/tables/stray.csv"
out=$(lint "$P4" | grep -c 'no caption cites')
[[ "$out" -eq 0 ]] || { echo "FAIL [$_TEST_NAME] legacy stage was held to the orphan rule"; exit 1; }

echo "PASS [$_TEST_NAME]"
