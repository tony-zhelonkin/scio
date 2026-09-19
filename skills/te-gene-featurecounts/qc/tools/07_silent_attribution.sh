#!/usr/bin/env bash
# 07_silent_attribution.sh — -O target-revealer s0 re-run (the silent-pile diagnostic).
#
# Generalized from green_close/rO/RUN_PROVENANCE.txt (the -O CORE re-run). Re-runs the s0 pass
# KERNEL-IDENTICAL to 04 EXCEPT it adds -O, so every default-ambiguous fragment becomes
# Assigned-to-all with its comma-separated candidate GeneID list emitted. -O is a TARGET-REVEALER
# ONLY — it does NOT redefine the silent set (that stays fixed by the default-kernel s0/s2/s1
# statuses from 04) and must NEVER be used on the production count matrix. Operationalizes
# lesson 5 (A7). Then 07_silent_attribution.py does the identify + lookup.
#
# Outputs (into --outdir):
#   sO/<sample>.bam.featureCounts[.gz]   the -O CORE (target lists for every ambiguous fragment)
#   sO/te_<sample>_s0O.counts.txt[.summary]   provenance
#
# docker + te-fc:2.0.2 + samtools REQUIRED. SKIPS GRACEFULLY (exit 0) when any is absent.
# If the SAF uses unprefixed chrom names (e.g. "1") but the BAM uses "chr1", pass --reheader to
# rename the BAM SQ lines (chr1 -> 1) before the run (SQ lines only; RNAME indices unchanged).
#
# Usage:
#   07_silent_attribution.sh --bam <BAM> --saf <SAF> --outdir <OUT> \
#     [--image te-fc:2.0.2] [--threads 12] [--reheader] [--samtools samtools]
set -u

NAME="07_silent_attribution.sh"
IMAGE="te-fc:2.0.2"
THREADS=12
SAMTOOLS="samtools"
BAM=""; SAF=""; OUT=""; REHEADER=0

LAYOUT="${LAYOUT:-pe}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bam)       BAM="$2"; shift 2 ;;
    --saf)       SAF="$2"; shift 2 ;;
    --outdir)    OUT="$2"; shift 2 ;;
    --image)     IMAGE="$2"; shift 2 ;;
    --threads)   THREADS="$2"; shift 2 ;;
    --layout)  LAYOUT="$2"; shift 2 ;;
    --reheader)  REHEADER=1; shift ;;
    --samtools)  SAMTOOLS="$2"; shift 2 ;;
    -h|--help)   grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "[$NAME] unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Single-end reads have no mate to pair, no pair to require and no chimeric pair to exclude,
# so `--layout se` drops the three pairing flags and leaves the rest of the kernel intact.
[[ "$LAYOUT" =~ ^(pe|se)$ ]] || { echo "[$NAME] --layout must be pe|se" >&2; exit 2; }
if [[ "$LAYOUT" == "pe" ]]; then PAIR_FLAGS="-p --countReadPairs -B -C"; else PAIR_FLAGS=""; fi

[[ -n "$BAM" && -n "$SAF" && -n "$OUT" ]] || {
  echo "[$NAME] need --bam --saf --outdir" >&2; exit 2; }
command -v docker >/dev/null 2>&1 || {
  echo "SKIP [$NAME] docker not on PATH — skipping -O target-revealer"; exit 0; }
docker image inspect "$IMAGE" >/dev/null 2>&1 || {
  echo "SKIP [$NAME] image '$IMAGE' not built — run env/build.sh"; exit 0; }
[[ -f "$BAM" ]] || { echo "SKIP [$NAME] BAM not found: $BAM"; exit 0; }
[[ -f "$SAF" ]] || { echo "SKIP [$NAME] SAF not found: $SAF"; exit 0; }

mkdir -p "$OUT"
sample="$(basename "$BAM")"; sample="${sample%.markdup.sorted.bam}"; sample="${sample%.bam}"
WD="$OUT/sO"; mkdir -p "$WD"
OUT_ABS="$(cd "$OUT" && pwd)"
SAF_DIR="$(cd "$(dirname "$SAF")" && pwd)"
uid="$(id -u)"; gid="$(id -g)"

RUNBAM="$BAM"
if [[ "$REHEADER" -eq 1 ]]; then
  command -v "$SAMTOOLS" >/dev/null 2>&1 || {
    echo "SKIP [$NAME] --reheader requested but samtools ('$SAMTOOLS') not on PATH"; exit 0; }
  echo "[$NAME] reheader BAM SQ lines (chr1 -> 1) ..." >&2
  "$SAMTOOLS" view -H "$BAM" | sed 's/\tSN:chr/\tSN:/' > "$WD/newhdr.sam"
  "$SAMTOOLS" reheader "$WD/newhdr.sam" "$BAM" > "$WD/${sample}.reheader.bam"
  RUNBAM="$WD/${sample}.reheader.bam"
fi
RUNBAM_DIR="$(cd "$(dirname "$RUNBAM")" && pwd)"

mounts=(-v "$OUT_ABS":"$OUT_ABS" -v "$RUNBAM_DIR":"$RUNBAM_DIR":ro -v "$SAF_DIR":"$SAF_DIR":ro)

echo "[$NAME] featureCounts -s 0 -M -O -R CORE (target-revealer; kernel-identical to s0 + -O) ..." >&2
docker run --rm -u "${uid}:${gid}" "${mounts[@]}" "$IMAGE" \
  featureCounts -M -O -F SAF -a "$SAF" \
    -o "$WD/te_${sample}_s0O.counts.txt" \
    -s 0 $PAIR_FLAGS \
    -R CORE --Rpath "$WD" -T "$THREADS" "$RUNBAM" \
  > "$WD/fc_s0O.log" 2>&1 || { echo "VERDICT [RED] [$NAME] -O FC failed; see $WD/fc_s0O.log"; exit 1; }

# drop the (large) reheadered BAM if we made one
[[ "$REHEADER" -eq 1 ]] && rm -f "$RUNBAM"

coreO="$WD/$(basename "$RUNBAM").featureCounts"
[[ -f "$coreO" ]] || coreO="${coreO}.gz"
[[ -f "$coreO" ]] || { echo "VERDICT [RED] [$NAME] -O CORE not found in $WD"; exit 1; }

echo
echo "VERDICT [GREEN] [$NAME] -O target-revealer CORE written: $coreO" \
     "(-O is a target-revealer ONLY; the silent set stays fixed by the default-kernel statuses)." \
     "Now run 07_silent_attribution.py with --s0-core/--s2-core/--s1-core (from 04) and --sO-core $coreO"
exit 0
