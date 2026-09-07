#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/submit_hcp_structural_array_hyak.sh CONFIG_ENV

Submits one HCP structural preprocessing SLURM array task per BIDS subject.
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

HCP_STRUCTURAL_OUT="${HCP_STRUCTURAL_OUT:-${DERIVATIVES_DIR}/hcp}"
HCP_STRUCTURAL_WORK="${HCP_STRUCTURAL_WORK:-${PROJECT_DIR}/scratch/hcp_structural_work}"
mkdir -p logs/slurm "$LOG_DIR" "$HCP_STRUCTURAL_OUT" "$HCP_STRUCTURAL_WORK"

if [[ ! -d "$BIDS_DIR" ]]; then
  echo "ERROR: BIDS_DIR does not exist: $BIDS_DIR" >&2
  exit 2
fi

timestamp="$(date +%Y%m%d_%H%M%S)"
subject_list="${LOG_DIR}/hcp_structural_subjects_${timestamp}.txt"

find "$BIDS_DIR" -maxdepth 1 -type d -name 'sub-*' -exec basename {} \; | sort > "$subject_list"
subject_count="$(wc -l < "$subject_list" | tr -d ' ')"
if [[ "$subject_count" -eq 0 ]]; then
  echo "ERROR: no sub-* directories found in BIDS_DIR: $BIDS_DIR" >&2
  exit 2
fi

concurrency="${HCP_STRUCTURAL_ARRAY_CONCURRENCY:-${HYAK_ARRAY_CONCURRENCY:-10}}"
if ! [[ "$concurrency" =~ ^[0-9]+$ ]] || [[ "$concurrency" -lt 1 ]]; then
  echo "ERROR: HCP_STRUCTURAL_ARRAY_CONCURRENCY/HYAK_ARRAY_CONCURRENCY must be a positive integer." >&2
  exit 2
fi

last_index="$((subject_count - 1))"

echo "Subject list: $subject_list"
echo "Subject count: $subject_count"
echo "Array range: 0-${last_index}%${concurrency}"

sbatch \
  --array="0-${last_index}%${concurrency}" \
  --partition="${HYAK_PARTITION:-ckpt-all}" \
  --time="${HCP_STRUCTURAL_HYAK_TIME:-72:00:00}" \
  "${REPO_DIR}/scripts/submit_hcp_structural_hyak.sbatch" \
  "$CONFIG_ENV" \
  "$subject_list"
