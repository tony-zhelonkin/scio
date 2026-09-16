#!/usr/bin/env bash
# Skill-local test entry point, auto-discovered by the toolkit's tests/run-all.sh sweep.
# Tests scripts/make_samplesheet.sh on synthetic fixtures (empty FASTQ files named per each
# supported convention). Skips GRACEFULLY (exit 0 with a notice) if a required tool is
# missing, so the bash CI never blocks on an un-bootstrapped machine.
#
# Part A covers the original Illumina-with-lane contract, assertion for assertion.
# Part B covers the three real conventions the generator was extended for: Illumina with no
# lane field plus AppleDouble litter, Novogene _1/_2.fq.gz, and bare single-end stems.
# Part C covers the refusals — the cases where emitting a plausible sheet would be worse
# than failing, above all a truncated transfer that dropped every mate.
set -euo pipefail

SKILL="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$SKILL/scripts/make_samplesheet.sh"

# Graceful skip if a needed tool is absent (mirrors the mllmcelltype pattern).
for tool in bash sed sort basename mktemp; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP [nfcore-rnaseq-execution]: '$tool' not on PATH"; exit 0
  fi
done
if [ ! -x "$GEN" ] && [ ! -f "$GEN" ]; then
  echo "SKIP [nfcore-rnaseq-execution]: $GEN absent"; exit 0
fi
# The generator needs bash 4.4+ for associative arrays and safe empty-array expansion.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ] ||
   { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 4 ]; }; then
  echo "SKIP [nfcore-rnaseq-execution]: bash 4.4+ required (found ${BASH_VERSION:-unknown})"; exit 0
fi

fail=0
note() { echo "  $1"; }
check() { # check <desc> <expected> <actual>
  if [ "$2" = "$3" ]; then note "PASS: $1"; else note "FAIL: $1 (expected [$2], got [$3])"; fail=1; fi
}
refuses() { # refuses <desc> -- <cmd...>   asserts nonzero exit AND empty stdout
  local desc="$1"; shift; [ "$1" = "--" ] && shift
  local out rc=0
  out="$("$@" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    note "FAIL: expected nonzero exit — $desc"; fail=1
  elif [ -n "$out" ]; then
    note "FAIL: wrote to stdout while failing — $desc"; fail=1
  else
    note "PASS: $desc"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FQ="$TMP/data"
mkdir -p "$FQ"

# Fixture: SAMPLEA single lane; SAMPLEB spans two lanes (L005 + L006); SAMPLEC single lane.
touch "$FQ/SAMPLEA_S1_L005_R1_001.fastq.gz" "$FQ/SAMPLEA_S1_L005_R2_001.fastq.gz"
touch "$FQ/SAMPLEB_S2_L005_R1_001.fastq.gz" "$FQ/SAMPLEB_S2_L005_R2_001.fastq.gz"
touch "$FQ/SAMPLEB_S2_L006_R1_001.fastq.gz" "$FQ/SAMPLEB_S2_L006_R2_001.fastq.gz"
touch "$FQ/SAMPLEC_S3_L005_R1_001.fastq.gz" "$FQ/SAMPLEC_S3_L005_R2_001.fastq.gz"

echo "[nfcore-rnaseq-execution] testing make_samplesheet.sh"
echo "-- A. Illumina with lane (original contract)"

OUT="$(bash "$GEN" "$FQ" reverse)"

# 1. Header
header="$(printf '%s\n' "$OUT" | head -n1)"
check "header" "sample,fastq_1,fastq_2,strandedness" "$header"

# 2. Row count: 4 FASTQ-pairs -> 4 data rows (+1 header = 5 lines)
nlines="$(printf '%s\n' "$OUT" | grep -c .)"
check "total lines (header + 4 rows)" "5" "$nlines"

# 3. Sample-name derivation: distinct samples = SAMPLEA, SAMPLEB, SAMPLEC
samples="$(printf '%s\n' "$OUT" | tail -n +2 | cut -d, -f1 | sort -u | paste -sd, -)"
check "distinct samples" "SAMPLEA,SAMPLEB,SAMPLEC" "$samples"

# 4. Multi-lane handling: SAMPLEB appears on TWO rows (one per lane)
b_rows="$(printf '%s\n' "$OUT" | tail -n +2 | cut -d, -f1 | grep -c '^SAMPLEB$')"
check "SAMPLEB row count (per-lane)" "2" "$b_rows"

# 5. R1/R2 pairing on SAMPLEA row: fastq_1 ends R1, fastq_2 ends R2, both absolute
a_row="$(printf '%s\n' "$OUT" | grep '^SAMPLEA,')"
f1="$(printf '%s\n' "$a_row" | cut -d, -f2)"
f2="$(printf '%s\n' "$a_row" | cut -d, -f3)"
case "$f1" in /*_R1_001.fastq.gz) p1=ok;; *) p1=bad;; esac
case "$f2" in /*_R2_001.fastq.gz) p2=ok;; *) p2=bad;; esac
check "fastq_1 absolute & R1" "ok" "$p1"
check "fastq_2 absolute & R2" "ok" "$p2"

# 6. Strandedness column carries the CLI arg
strand="$(printf '%s\n' "$a_row" | cut -d, -f4)"
check "strandedness arg" "reverse" "$strand"

# 7. Default strandedness is `auto`
def_strand="$(bash "$GEN" "$FQ" | grep '^SAMPLEA,' | cut -d, -f4)"
check "default strandedness" "auto" "$def_strand"

# 7b. --seq-platform appends a seq_platform column to header and rows
SP_OUT="$(bash "$GEN" "$FQ" auto --seq-platform ILLUMINA)"
sp_header="$(printf '%s\n' "$SP_OUT" | head -n1)"
check "seq_platform header" "sample,fastq_1,fastq_2,strandedness,seq_platform" "$sp_header"
sp_val="$(printf '%s\n' "$SP_OUT" | grep '^SAMPLEA,' | cut -d, -f5)"
check "seq_platform value" "ILLUMINA" "$sp_val"
# default (no flag) keeps the 4-column header
DEF_OUT="$(bash "$GEN" "$FQ")"
def_header="$(printf '%s\n' "$DEF_OUT" | head -n1)"
check "no seq_platform by default" "sample,fastq_1,fastq_2,strandedness" "$def_header"

# 8. Error on missing R2
ORPH="$TMP/orphan"; mkdir -p "$ORPH"
touch "$ORPH/SAMPLED_S1_L005_R1_001.fastq.gz"  # no R2
if bash "$GEN" "$ORPH" >/dev/null 2>&1; then
  note "FAIL: expected nonzero exit on missing R2"; fail=1
else
  note "PASS: errors on missing R2"
fi

# 9. Error on missing directory
if bash "$GEN" "$TMP/does_not_exist" >/dev/null 2>&1; then
  note "FAIL: expected nonzero exit on missing dir"; fail=1
else
  note "PASS: errors on missing dir"
fi

# 10. The `--seq-platform=PLAT` spelling is equivalent to the two-token form.
eq_val="$(bash "$GEN" "$FQ" auto --seq-platform=ILLUMINA | grep '^SAMPLEA,' | cut -d, -f5)"
check "--seq-platform=PLAT spelling" "ILLUMINA" "$eq_val"

# 11. Byte-identical output across runs, and independent of the caller's locale.
run_a="$(bash "$GEN" "$FQ" auto)"
run_b="$(LC_ALL=en_US.UTF-8 bash "$GEN" "$FQ" auto)"
check "deterministic across runs and locales" "same" "$([ "$run_a" = "$run_b" ] && echo same || echo differs)"

echo "-- B. The three real conventions"

# 12. Illumina WITHOUT a lane field, with AppleDouble litter beside the reads. macOS writes
#     one ._ file per file, and half of them match *_R1_001.fastq.gz.
NOLANE="$TMP/nolane"; mkdir -p "$NOLANE"
for n in 01 02 03; do
  touch "$NOLANE/SAMP-${n}_S${n}_R1_001.fastq.gz" "$NOLANE/SAMP-${n}_S${n}_R2_001.fastq.gz"
  touch "$NOLANE/._SAMP-${n}_S${n}_R1_001.fastq.gz" "$NOLANE/._SAMP-${n}_S${n}_R2_001.fastq.gz"
done
touch "$NOLANE/run_sha256sum.txt" "$NOLANE/._run_sha256sum.txt"   # non-FASTQ sidecars: ignored
NL_OUT="$(bash "$GEN" "$NOLANE" auto 2>/dev/null)"
nl_rows="$(printf '%s\n' "$NL_OUT" | tail -n +2 | grep -c .)"
check "lane-free Illumina row count" "3" "$nl_rows"
nl_samples="$(printf '%s\n' "$NL_OUT" | tail -n +2 | cut -d, -f1 | sort -u | paste -sd, -)"
check "lane-free sample derivation" "SAMP-01,SAMP-02,SAMP-03" "$nl_samples"
nl_ad="$(printf '%s\n' "$NL_OUT" | grep -c '/\._' || true)"
check "no AppleDouble path in the sheet" "0" "$nl_ad"
nl_note="$(bash "$GEN" "$NOLANE" auto 2>&1 >/dev/null | grep -c 'AppleDouble' || true)"
check "AppleDouble exclusion reported on stderr" "1" "$nl_note"

# 13. Novogene: <sample>_1.fq.gz / <sample>_2.fq.gz
NOVO="$TMP/novo"; mkdir -p "$NOVO"
for a in A41 A42; do touch "$NOVO/${a}_1.fq.gz" "$NOVO/${a}_2.fq.gz"; done
NV_OUT="$(bash "$GEN" "$NOVO" reverse --pattern novogene)"
nv_samples="$(printf '%s\n' "$NV_OUT" | tail -n +2 | cut -d, -f1 | sort -u | paste -sd, -)"
check "novogene sample derivation" "A41,A42" "$nv_samples"
nv_f2="$(printf '%s\n' "$NV_OUT" | grep '^A41,' | cut -d, -f3)"
case "$nv_f2" in /*A41_2.fq.gz) nv_p=ok;; *) nv_p=bad;; esac
check "novogene mate 2 pairing" "ok" "$nv_p"

# 14. Bare single-end, using real-shaped <run>_<well>_<index> stems. RUN_1_1 and RUN_16_16
#     are why `bare` strips only the extension: a trailing-_1/_2 heuristic would maul them.
BARE="$TMP/bare"; mkdir -p "$BARE"
touch "$BARE/RUN_1_1.fastq.gz" "$BARE/RUN_2_2.fastq.gz" \
      "$BARE/RUN_16_16.fastq.gz" "$BARE/RUN2_1_49.fastq.gz"
BR_OUT="$(bash "$GEN" "$BARE" unstranded --pattern bare --single-end 2>/dev/null)"
# LC_ALL=C here because the expected order is stated in C collation: '6' (0x36) sorts
# before '_' (0x5F), so RUN_16_16 precedes RUN_1_1. The generator always sorts under
# C; this pins the assertion to the same order instead of the test runner's locale.
br_samples="$(printf '%s\n' "$BR_OUT" | tail -n +2 | cut -d, -f1 | LC_ALL=C sort | paste -sd, -)"
check "bare keeps full stems" "RUN2_1_49,RUN_16_16,RUN_1_1,RUN_2_2" "$br_samples"
br_f2="$(printf '%s\n' "$BR_OUT" | grep '^RUN_1_1,' | cut -d, -f3)"
check "single-end leaves fastq_2 empty" "" "$br_f2"
br_rows="$(printf '%s\n' "$BR_OUT" | tail -n +2 | grep -c .)"
check "bare row count" "4" "$br_rows"
br_note="$(bash "$GEN" "$BARE" auto --pattern bare --single-end 2>&1 >/dev/null | grep -c 'trailing _1/_2' || true)"
check "no spurious mate warning on <run>_<well>_<index> stems" "0" "$br_note"

# 15. Bare mode pointed at a paired directory: warns, since no filename can disprove it.
BAREP="$TMP/bare_paired"; mkdir -p "$BAREP"
touch "$BAREP/A41_1.fq.gz" "$BAREP/A41_2.fq.gz"
bp_note="$(bash "$GEN" "$BAREP" auto --pattern bare --single-end 2>&1 >/dev/null | grep -c 'trailing _1/_2' || true)"
check "bare on a paired dir warns about mates" "1" "$bp_note"

# 16. A directory path containing a space still yields absolute, usable paths.
SPACED="$TMP/with space"; mkdir -p "$SPACED"
touch "$SPACED/S1_S1_R1_001.fastq.gz" "$SPACED/S1_S1_R2_001.fastq.gz"
sp_f1="$(bash "$GEN" "$SPACED" auto | grep '^S1,' | cut -d, -f2)"
case "$sp_f1" in /*"with space"/S1_S1_R1_001.fastq.gz) sp_ok=ok;; *) sp_ok=bad;; esac
check "space in the directory path" "ok" "$sp_ok"

echo "-- C. Refusals"

# 17. THE important one: every mate missing must never be read as single-end. A truncated
#     rsync that dropped all R2s would otherwise produce a clean sheet for a PE experiment.
ALLR2="$TMP/all_r2_gone"; mkdir -p "$ALLR2"
touch "$ALLR2/S1_S1_R1_001.fastq.gz" "$ALLR2/S2_S2_R1_001.fastq.gz"
refuses "every mate missing is not single-end" -- bash "$GEN" "$ALLR2" auto
se_rows="$(bash "$GEN" "$ALLR2" auto --single-end 2>/dev/null | tail -n +2 | grep -c .)"
check "  ...but explicit --single-end emits" "2" "$se_rows"

# 18. Orphan mate 2 — the failure a narrow R1-only glob hides.
ORPH2="$TMP/orphan_r2"; mkdir -p "$ORPH2"
touch "$ORPH2/S1_S1_R1_001.fastq.gz" "$ORPH2/S1_S1_R2_001.fastq.gz" "$ORPH2/S9_S9_R2_001.fastq.gz"
refuses "orphan mate 2 with no mate 1" -- bash "$GEN" "$ORPH2" auto

# 19. --single-end contradicted by a present mate.
SER2="$TMP/se_with_r2"; mkdir -p "$SER2"
touch "$SER2/S1_S1_R1_001.fastq.gz" "$SER2/S1_S1_R2_001.fastq.gz"
refuses "--single-end with a mate present" -- bash "$GEN" "$SER2" auto --single-end

# 20. A second naming convention in the same directory is an error, not an omission.
MIXED="$TMP/mixed"; mkdir -p "$MIXED"
touch "$MIXED/S1_S1_R1_001.fastq.gz" "$MIXED/S1_S1_R2_001.fastq.gz" "$MIXED/A41_1.fq.gz" "$MIXED/A41_2.fq.gz"
refuses "foreign convention in the directory" -- bash "$GEN" "$MIXED" auto

# 21. Nothing to emit.
EMPTYD="$TMP/empty"; mkdir -p "$EMPTYD"
refuses "no FASTQs at all" -- bash "$GEN" "$EMPTYD" auto
ONLYAD="$TMP/only_ad"; mkdir -p "$ONLYAD"; touch "$ONLYAD/._x_S1_R1_001.fastq.gz"
refuses "only AppleDouble files" -- bash "$GEN" "$ONLYAD" auto

# 22. A comma anywhere in an emitted field would corrupt plain CSV.
COMMAD="$TMP/comma,dir"; mkdir -p "$COMMAD"
touch "$COMMAD/S1_S1_R1_001.fastq.gz" "$COMMAD/S1_S1_R2_001.fastq.gz"
refuses "comma in the directory path" -- bash "$GEN" "$COMMAD" auto

# 23. Option and value validation.
OKD="$TMP/ok"; mkdir -p "$OKD"
touch "$OKD/S1_S1_R1_001.fastq.gz" "$OKD/S1_S1_R2_001.fastq.gz"
refuses "unknown --pattern value"        -- bash "$GEN" "$OKD" auto --pattern novagene
refuses "unknown strandedness value"     -- bash "$GEN" "$OKD" backwards
refuses "bare without --single-end"      -- bash "$GEN" "$OKD" auto --pattern bare
refuses "unknown option"                 -- bash "$GEN" "$OKD" auto --recursive
refuses "--pattern given twice"          -- bash "$GEN" "$OKD" auto --pattern illumina --pattern bare
refuses "--seq-platform given twice"     -- bash "$GEN" "$OKD" auto --seq-platform A --seq-platform B
refuses "empty --seq-platform value"     -- bash "$GEN" "$OKD" auto --seq-platform=
refuses "too many positional arguments"  -- bash "$GEN" "$OKD" auto extra

echo
if [ "$fail" -eq 0 ]; then
  echo "[nfcore-rnaseq-execution] ALL TESTS PASS"
  exit 0
else
  echo "[nfcore-rnaseq-execution] TESTS FAILED"
  exit 1
fi
