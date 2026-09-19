#!/usr/bin/env bash
# 04_core_regime_witness.sh — the -R CORE 3-pass regime witness (the suite's engine).
#
# Generalized from kernel_trace/run_core_0033_s2.sh + ambiguity_audit/rcore_crosstab.py.
# Runs featureCounts 3x on the SAME BAM (-s0 / -s2 / -s1), IDENTICAL kernel
# (-M -F SAF -p --countReadPairs -B -C, no -O, no --fraction) plus -R CORE, inside the locked
# te-fc:2.0.2 image. Then HASH-JOINS the three per-fragment CORE tables BY FRAGMENT ID
# (NEVER a positional paste — read-ID order differs across threaded runs) into a 14-cell
# joint_counts crosstab. Operationalizes lesson 3 (the regime witness + hash-join foot-gun).
#
# Outputs (into --outdir):
#   s0/s2/s1/<sample>.bam.featureCounts[.gz]   the three CORE tables (kept; feed 07/08)
#   joint_counts_<sample>.json                 14-cell (s0,s2,s1) status-triple crosstab
#                                              -> consumed by 05_classify_triples.py / 06_closure_audit.py
#
# docker + the te-fc:2.0.2 image are REQUIRED. SKIPS GRACEFULLY (exit 0) when docker or the image
# is unavailable, mirroring tests/run_regression.sh. The BAM and SAF must live under a path the
# container can bind-mount (default mounts: the BAM's dir, the SAF's dir, and the outdir).
#
# Usage:
#   04_core_regime_witness.sh --bam <BAM> --saf <SAF> --outdir <OUT> \
#     [--image te-fc:2.0.2] [--threads 12]
set -u

NAME="04_core_regime_witness"
IMAGE="te-fc:2.0.2"
THREADS=12
BAM=""; SAF=""; OUT=""

LAYOUT="${LAYOUT:-pe}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bam)     BAM="$2"; shift 2 ;;
    --saf)     SAF="$2"; shift 2 ;;
    --outdir)  OUT="$2"; shift 2 ;;
    --image)   IMAGE="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --layout)  LAYOUT="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
  echo "SKIP [$NAME] docker not on PATH — skipping -R CORE witness"; exit 0; }
docker image inspect "$IMAGE" >/dev/null 2>&1 || {
  echo "SKIP [$NAME] image '$IMAGE' not built — run env/build.sh to enable the -R CORE witness"; exit 0; }
[[ -f "$BAM" ]] || { echo "SKIP [$NAME] BAM not found: $BAM"; exit 0; }
[[ -f "$SAF" ]] || { echo "SKIP [$NAME] SAF not found: $SAF"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP [$NAME] python3 not on PATH"; exit 0; }

mkdir -p "$OUT"
sample="$(basename "$BAM")"; sample="${sample%.markdup.sorted.bam}"; sample="${sample%.bam}"
BAM_DIR="$(cd "$(dirname "$BAM")" && pwd)"
SAF_DIR="$(cd "$(dirname "$SAF")" && pwd)"
OUT_ABS="$(cd "$OUT" && pwd)"
uid="$(id -u)"; gid="$(id -g)"

# identical-path bind mounts so symlinks/paths resolve inside the container
mounts=(-v "$OUT_ABS":"$OUT_ABS" -v "$BAM_DIR":"$BAM_DIR":ro -v "$SAF_DIR":"$SAF_DIR":ro)

run_pass() {
  local s="$1" sub="$2"
  local wd="$OUT_ABS/$sub"
  mkdir -p "$wd"
  echo "[$NAME] featureCounts -s $s -R CORE ($sub) ..." >&2
  docker run --rm -u "${uid}:${gid}" "${mounts[@]}" "$IMAGE" \
    featureCounts -M -F SAF -a "$SAF" \
      -o "$wd/${sample}.counts.txt" \
      -s "$s" $PAIR_FLAGS \
      -R CORE --Rpath "$wd" -T "$THREADS" "$BAM" \
    > "$wd/fc_s${s}.log" 2>&1 || { echo "[$NAME] FC failed for -s $s; see $wd/fc_s${s}.log" >&2; return 1; }
}

run_pass 0 s0 || { echo "VERDICT [RED] [$NAME] s0 pass failed"; exit 1; }
run_pass 2 s2 || { echo "VERDICT [RED] [$NAME] s2 pass failed"; exit 1; }
run_pass 1 s1 || { echo "VERDICT [RED] [$NAME] s1 pass failed"; exit 1; }

# locate the CORE files (featureCounts writes <bam-basename>.featureCounts in --Rpath)
core_path() {
  local sub="$1"
  local f="$OUT_ABS/$sub/$(basename "$BAM").featureCounts"
  [[ -f "$f" ]] || f="${f}.gz"
  echo "$f"
}
F0="$(core_path s0)"; F2="$(core_path s2)"; F1="$(core_path s1)"
for f in "$F0" "$F2" "$F1"; do
  [[ -f "$f" ]] || { echo "VERDICT [RED] [$NAME] CORE file missing: $f"; exit 1; }
done

# HASH-JOIN by fragment ID (NEVER positional paste) -> joint_counts json
python3 - "$F0" "$F2" "$F1" "$OUT_ABS/joint_counts_${sample}.json" "$sample" <<'PY'
import sys, gzip, json, collections
f0, f2, f1, out, sample = sys.argv[1:6]
ST = {"Assigned":"A","Unassigned_Ambiguity":"M","Unassigned_NoFeatures":"N","Unassigned_Singleton":"S"}
def opener(p): return gzip.open(p,"rt") if p.endswith(".gz") else open(p)
def load(p):
    d={}
    with opener(p) as fh:
        for line in fh:
            i=line.find("\t"); j=line.find("\t",i+1)
            d[line[:i]] = ST.get(line[i+1:j], "?")
    return d
s0=load(f0); s2=load(f2); s1=load(f1)
joint=collections.Counter()
for rid,a0 in s0.items():
    joint[(a0, s2.get(rid,"?"), s1.get(rid,"?"))] += 1
N=sum(joint.values())
obj=dict(sample=sample, N_fragments=N,
         joint_counts={f"{a}/{b}/{d}":c for (a,b,d),c in joint.items()})
json.dump(obj, open(out,"w"), indent=2)
print(f"[04] hash-joined {N:,} fragments -> {out}", file=sys.stderr)
PY
rc=$?
[[ $rc -eq 0 ]] || { echo "VERDICT [RED] [$NAME] hash-join failed"; exit 1; }

echo
echo "VERDICT [GREEN] [$NAME] 3-pass -R CORE witness complete; joint_counts_${sample}.json written" \
     "(hash-joined by fragment ID, not positional paste). Feed it to 05/06; CORE files feed 07/08."
exit 0
