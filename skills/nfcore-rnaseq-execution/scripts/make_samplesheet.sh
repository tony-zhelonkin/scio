#!/usr/bin/env bash
# make_samplesheet.sh — build an nf-core/rnaseq samplesheet from ONE directory of FASTQs.
#
# Output: CSV on stdout,  sample,fastq_1,fastq_2,strandedness[,seq_platform]
#   Absolute fastq paths, rows sorted deterministically under LC_ALL=C, single-end rows
#   leaving fastq_2 empty. nf-core/rnaseq concatenates rows that share a `sample` value,
#   so a sample spanning several lanes emits one row per lane and lands in one BAM.
#
# Usage:
#   make_samplesheet.sh <fastq_dir> [strandedness] [--pattern MODE] [--single-end]
#                       [--seq-platform PLATFORM]
#
# Filename grammars, chosen with --pattern (default `illumina`):
#
#   illumina   <sample>_S<n>[_L<lane>]_R{1,2}_001.fastq.gz    — the lane field is optional
#   novogene   <sample>_{1,2}.fq.gz
#   bare       <sample>.fastq.gz | <sample>.fq.gz             — requires --single-end
#
# Three rules the grammars exist to enforce, each earned from a way this goes wrong:
#
#   1. The mode is explicit. There is no auto-detection and no fallback from one grammar
#      to the next, because a directory that half-matches would otherwise yield a
#      plausible samplesheet covering only part of the data.
#   2. Every FASTQ in the directory is accounted for. A file the selected grammar does not
#      match is an error, never a silent omission — a narrow R1-only glob is exactly how
#      an orphan R2, or a second naming convention in the same directory, goes unnoticed.
#   3. Single-end is never inferred from absent mates. A truncated transfer that dropped
#      every R2 would otherwise produce a clean-looking single-end samplesheet for a
#      paired-end experiment, and the run would finish and report wrong numbers. So
#      --single-end is required, and under it a present R2 is a contradiction and an error.
#
# `bare` strips only the extension, deliberately. Real single-end submissions name files
# <run>_<well>_<index>.fastq.gz — RUN_1_1.fastq.gz, RUN_16_16.fastq.gz — so a "trailing
# _1/_2 is a mate marker" heuristic would mangle precisely the layout this mode exists for.
#
# What this script will not do, by design: it reads one flat directory, and it never
# rewrites a derived sample name. Cross-directory merges — a two-flowcell depth top-up,
# say — are the caller's job, carried by an explicit mapping table, so that months later
# a row's sample name traces back to a reviewed decision instead of to a regex.
#
# AppleDouble `._*` files are dropped before classification and the count is reported on
# stderr. macOS writes one alongside every file it touches, and they match every
# *_R1_001.fastq.gz glob, so they arrive as extra samples if nothing excludes them.
#
# Exit status: 0 success; 2 usage or option error; 1 input or data error. Nothing is
# written to stdout on failure. Needs bash 4.4+ and coreutils, nothing else — 4.4 because
# `set -u` treats "${empty_array[@]}" as unbound before it, and this script relies on that
# expansion being safe. Randi and both workstations run 4.4 or newer; macOS bash 3.2 does
# not, which is why the check names the version rather than failing obscurely later.

set -euo pipefail
export LC_ALL=C

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ] ||
   { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 4 ]; }; then
  echo "ERROR: bash 4.4+ required (found ${BASH_VERSION:-unknown})." >&2
  exit 2
fi

die()       { echo "ERROR: $*" >&2; exit 1; }
die_usage() { echo "ERROR: $*" >&2; usage; exit 2; }

usage() {
  cat >&2 <<'EOF'
Usage: make_samplesheet.sh <fastq_dir> [strandedness] [options]

  <fastq_dir>          one flat directory of FASTQs (not searched recursively)
  [strandedness]       auto | forward | reverse | unstranded   (default: auto)

Options:
  --pattern MODE       illumina | novogene | bare              (default: illumina)
                         illumina  <sample>_S<n>[_L<lane>]_R{1,2}_001.fastq.gz
                         novogene  <sample>_{1,2}.fq.gz
                         bare      <sample>.fastq.gz | <sample>.fq.gz  (single-end only)
  --single-end         emit an empty fastq_2; required for --pattern bare.
                       Never inferred: a present mate under this flag is an error.
  --seq-platform PLAT  append a seq_platform column (e.g. ILLUMINA) -> BAM PL tag

Writes an nf-core/rnaseq samplesheet CSV to stdout:
  sample,fastq_1,fastq_2,strandedness[,seq_platform]
Rows sharing a `sample` value are concatenated by nf-core/rnaseq (its CAT_FASTQ step).
EOF
}

# --- arguments ----------------------------------------------------------------------

dir=""
strandedness=""
strandedness_set=0
seq_platform=""
seq_platform_set=0
pattern="illumina"
pattern_set=0
single_end=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage; exit 0 ;;
    --pattern)
      [ "$#" -ge 2 ] || die_usage "--pattern needs a value."
      [ "$pattern_set" -eq 0 ] || die_usage "--pattern given more than once."
      pattern="$2"; pattern_set=1; shift 2 ;;
    --pattern=*)
      [ "$pattern_set" -eq 0 ] || die_usage "--pattern given more than once."
      pattern="${1#*=}"; pattern_set=1; shift ;;
    --single-end)
      single_end=1; shift ;;
    --seq-platform)
      [ "$#" -ge 2 ] || die_usage "--seq-platform needs a value."
      [ "$seq_platform_set" -eq 0 ] || die_usage "--seq-platform given more than once."
      seq_platform="$2"; seq_platform_set=1; shift 2 ;;
    --seq-platform=*)
      [ "$seq_platform_set" -eq 0 ] || die_usage "--seq-platform given more than once."
      seq_platform="${1#*=}"; seq_platform_set=1; shift ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        if   [ -z "$dir" ];              then dir="$1"
        elif [ "$strandedness_set" -eq 0 ]; then strandedness="$1"; strandedness_set=1
        else die_usage "too many positional arguments."
        fi
        shift
      done ;;
    -*)
      die_usage "unknown option: $1" ;;
    *)
      if   [ -z "$dir" ];                 then dir="$1"
      elif [ "$strandedness_set" -eq 0 ]; then strandedness="$1"; strandedness_set=1
      else die_usage "too many positional arguments."
      fi
      shift ;;
  esac
done

[ -n "$dir" ] || die_usage "<fastq_dir> is required."

[ "$strandedness_set" -eq 1 ] || strandedness="auto"
case "$strandedness" in
  auto|forward|reverse|unstranded) ;;
  *) die_usage "strandedness must be auto, forward, reverse or unstranded (got '$strandedness')." ;;
esac

case "$pattern" in
  illumina|novogene|bare) ;;
  *) die_usage "--pattern must be illumina, novogene or bare (got '$pattern')." ;;
esac

if [ "$pattern" = "bare" ] && [ "$single_end" -eq 0 ]; then
  die_usage "--pattern bare carries no mate marker, so it requires --single-end."
fi

if [ "$seq_platform_set" -eq 1 ] && [ -z "$seq_platform" ]; then
  die_usage "--seq-platform needs a non-empty value."
fi

[ -d "$dir" ] || die "not a directory: $dir"

# Resolve to an absolute path so the fastq columns are absolute. No `cd`; cwd stays put.
abs_dir="$(cd "$dir" && pwd)"

# --- inventory ----------------------------------------------------------------------
# Both extensions, hidden entries included, so nothing in the directory escapes notice.

shopt -s nullglob dotglob
candidates=("$abs_dir"/*.fastq.gz "$abs_dir"/*.fq.gz)
shopt -u nullglob dotglob

appledouble=0
files=()
for path in "${candidates[@]}"; do
  case "$(basename "$path")" in
    ._*) appledouble=$((appledouble + 1)); continue ;;
  esac
  files+=("$path")
done

[ "$appledouble" -eq 0 ] || \
  echo "NOTE: excluded $appledouble AppleDouble (._*) FASTQ-like file(s) in $abs_dir" >&2

if [ "${#files[@]}" -eq 0 ]; then
  die "no FASTQ files (*.fastq.gz, *.fq.gz) found in $abs_dir"
fi

# --- classify -----------------------------------------------------------------------
# Every file is matched against the one selected grammar. `key` is the pairing key: it
# retains the sample index and lane, so mates pair only within their own lane.

declare -A r1_of r2_of sample_of
keys=()
unmatched=()

for path in "${files[@]}"; do
  base="$(basename "$path")"
  key=""; sample=""; read_no=""

  case "$pattern" in
    illumina)
      if [[ $base =~ ^(.+)_S([0-9]+)(_L([0-9]+))?_R([12])_001\.fastq\.gz$ ]]; then
        sample="${BASH_REMATCH[1]}"
        key="${sample}_S${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
        read_no="${BASH_REMATCH[5]}"
      fi ;;
    novogene)
      if [[ $base =~ ^(.+)_([12])\.fq\.gz$ ]]; then
        sample="${BASH_REMATCH[1]}"
        key="$sample"
        read_no="${BASH_REMATCH[2]}"
      fi ;;
    bare)
      if [[ $base =~ ^(.+)\.(fastq|fq)\.gz$ ]]; then
        sample="${BASH_REMATCH[1]}"
        key="$sample"
        read_no=1
      fi ;;
  esac

  if [ -z "$key" ]; then
    unmatched+=("$base")
    continue
  fi
  [ -n "$sample" ] || die "empty sample name derived from: $base"

  if [ -z "${sample_of[$key]+set}" ]; then
    keys+=("$key")
    sample_of["$key"]="$sample"
  fi

  if [ "$read_no" = "1" ]; then
    [ -z "${r1_of[$key]+set}" ] || \
      die "two files claim the same R1 slot '$key': $(basename "${r1_of[$key]}") and $base"
    r1_of["$key"]="$path"
  else
    [ -z "${r2_of[$key]+set}" ] || \
      die "two files claim the same R2 slot '$key': $(basename "${r2_of[$key]}") and $base"
    r2_of["$key"]="$path"
  fi
done

if [ "${#unmatched[@]}" -gt 0 ]; then
  {
    echo "ERROR: ${#unmatched[@]} file(s) in $abs_dir do not match --pattern $pattern:"
    printf '  %s\n' "${unmatched[@]}"
    echo "Every FASTQ in the directory must match the selected grammar. Check --pattern,"
    echo "or move the foreign files out of the directory before generating the sheet."
  } >&2
  exit 1
fi

# `bare` accepts any stem, so a paired directory read in bare mode yields two rows per
# sample rather than an error. Nothing in a filename can rule that out, so say so.
if [ "$pattern" = "bare" ]; then
  mates=0
  for key in "${keys[@]}"; do
    case "$key" in
      *_1) [ -n "${sample_of[${key%_1}_2]+set}" ] && mates=$((mates + 1)) ;;
    esac
  done
  [ "$mates" -eq 0 ] || \
    echo "NOTE: $mates stem pair(s) in $abs_dir differ only by a trailing _1/_2. If these are mates, --pattern novogene is the one you want." >&2
fi

# --- validate pairing ----------------------------------------------------------------

for key in "${keys[@]}"; do
  if [ "$single_end" -eq 1 ]; then
    [ -n "${r1_of[$key]+set}" ] || \
      die "single-end requested but '$key' has only a mate-2 file: $(basename "${r2_of[$key]}")"
    [ -z "${r2_of[$key]+set}" ] || \
      die "single-end requested but '$key' has a mate-2 file: $(basename "${r2_of[$key]}")"
  else
    [ -n "${r1_of[$key]+set}" ] || \
      die "orphan mate-2 with no mate-1: $(basename "${r2_of[$key]}")"
    [ -n "${r2_of[$key]+set}" ] || \
      die "R1 has no matching R2: ${r1_of[$key]}"
  fi
done

# --- build rows ----------------------------------------------------------------------
# Plain CSV with no quoting, so a field that would need quoting is rejected instead.

csv_safe() { # csv_safe <what> <value>
  case "$2" in
    *,*)      die "$1 contains a comma, which this plain-CSV writer cannot carry: $2" ;;
    *'"'*)    die "$1 contains a double quote: $2" ;;
    *$'\r'*)  die "$1 contains a carriage return: $2" ;;
    *$'\n'*)  die "$1 contains a newline: $2" ;;
  esac
}

csv_safe "strandedness" "$strandedness"
[ "$seq_platform_set" -eq 0 ] || csv_safe "seq_platform" "$seq_platform"

rows=()
for key in "${keys[@]}"; do
  sample="${sample_of[$key]}"
  f1="${r1_of[$key]}"
  f2=""
  [ "$single_end" -eq 1 ] || f2="${r2_of[$key]}"

  csv_safe "sample name" "$sample"
  case "$sample" in
    *[[:space:]]*) die "sample name contains whitespace, which nf-core converts to an underscore and can silently merge distinct samples: '$sample'" ;;
  esac
  csv_safe "fastq_1 path" "$f1"
  [ -z "$f2" ] || csv_safe "fastq_2 path" "$f2"

  [ -f "$f1" ] && [ -r "$f1" ] || die "not a readable regular file: $f1"
  if [ -n "$f2" ]; then
    [ -f "$f2" ] && [ -r "$f2" ] || die "not a readable regular file: $f2"
  fi

  if [ "$seq_platform_set" -eq 1 ]; then
    rows+=("$sample,$f1,$f2,$strandedness,$seq_platform")
  else
    rows+=("$sample,$f1,$f2,$strandedness")
  fi
done

[ "${#rows[@]}" -gt 0 ] || die "no rows to emit from $abs_dir"

# Sort to completion before anything reaches stdout, so a failure here emits no partial
# sheet. Repeated sample values are legitimate (one row per lane), so never `sort -u`.
sorted="$(printf '%s\n' "${rows[@]}" | sort)"

if [ "$seq_platform_set" -eq 1 ]; then
  printf 'sample,fastq_1,fastq_2,strandedness,seq_platform\n'
else
  printf 'sample,fastq_1,fastq_2,strandedness\n'
fi
printf '%s\n' "$sorted"
