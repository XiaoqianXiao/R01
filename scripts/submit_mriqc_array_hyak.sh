#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/submit_mriqc_array_hyak.sh CONFIG_ENV

Generates a subject/session manifest from BIDS_DIR and submits one Hyak SLURM
array task per subject for MRIQC participant-level raw-image QC.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
  usage
  exit 0
fi

CONFIG_ENV="$1"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

if [[ "$CONFIG_ENV" != /* ]]; then
  CONFIG_ENV="${REPO_DIR}/${CONFIG_ENV}"
fi

# shellcheck source=/dev/null
source "$CONFIG_ENV"

MRIQC_OUT="${MRIQC_OUT:-${DERIVATIVES_DIR}/qc/mriqc}"
MRIQC_WORK="${MRIQC_WORK:-${PROJECT_DIR}/scratch/mriqc_work}"
MRIQC_LOG_DIR="${MRIQC_LOG_DIR:-${PROJECT_DIR}/logs/mriqc}"

mkdir -p logs/slurm "$MRIQC_LOG_DIR" "$MRIQC_OUT" "$MRIQC_WORK"

if [[ ! -d "$BIDS_DIR" ]]; then
  echo "ERROR: BIDS_DIR does not exist: $BIDS_DIR" >&2
  exit 2
fi

if [[ ! -f "$MRIQC_IMAGE" ]]; then
  echo "ERROR: MRIQC_IMAGE does not exist: $MRIQC_IMAGE" >&2
  echo "Build it with scripts/build_mriqc.sbatch or copy a frozen image to this path." >&2
  exit 2
fi

timestamp="$(date +%Y%m%d_%H%M%S)"
subject_list="${MRIQC_LOG_DIR}/mriqc_subjects_${timestamp}.txt"
session_manifest="${MRIQC_LOG_DIR}/mriqc_multisession_manifest_${timestamp}.csv"

"${REPO_DIR}/scripts/run_python_hyak.sh" \
  "$CONFIG_ENV" \
  "${REPO_DIR}/scripts/make_multisession_manifest.py" \
  "$BIDS_DIR" \
  --manifest "$session_manifest" \
  --subject-list "$subject_list"

subject_count="$(wc -l < "$subject_list" | tr -d ' ')"
if [[ "$subject_count" -eq 0 ]]; then
  echo "ERROR: no sub-* directories found in BIDS_DIR: $BIDS_DIR" >&2
  exit 2
fi

concurrency="${MRIQC_ARRAY_CONCURRENCY:-${HYAK_ARRAY_CONCURRENCY:-10}}"
if ! [[ "$concurrency" =~ ^[0-9]+$ ]] || [[ "$concurrency" -lt 1 ]]; then
  echo "ERROR: MRIQC_ARRAY_CONCURRENCY must be a positive integer." >&2
  exit 2
fi

last_index="$((subject_count - 1))"

echo "Subject list: $subject_list"
echo "Session manifest: $session_manifest"
echo "Subject count: $subject_count"
echo "Array range: 0-${last_index}%${concurrency}"

sbatch \
  --array="0-${last_index}%${concurrency}" \
  --partition="${HYAK_PARTITION:-ckpt-all}" \
  --time="${MRIQC_HYAK_TIME:-24:00:00}" \
  --cpus-per-task="${MRIQC_NPROC:-${NTHREADS:-16}}" \
  --mem="${MRIQC_MEM_GB:-64}G" \
  "${REPO_DIR}/scripts/submit_mriqc_hyak.sbatch" \
  "$CONFIG_ENV" \
  "$subject_list"
