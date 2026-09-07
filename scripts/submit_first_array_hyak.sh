#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
  echo "Usage: scripts/submit_first_array_hyak.sh CONFIG_ENV"
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
mkdir -p logs/slurm "$LOG_DIR"

timestamp="$(date +%Y%m%d_%H%M%S)"
subject_list="${LOG_DIR}/first_subjects_${timestamp}.txt"

find "$FMRIPREP_OUT" -maxdepth 1 -type d -name 'sub-*' -exec basename {} \; | sort > "$subject_list"
subject_count="$(wc -l < "$subject_list" | tr -d ' ')"
if [[ "$subject_count" -eq 0 ]]; then
  echo "ERROR: no sub-* directories found in FMRIPREP_OUT: $FMRIPREP_OUT" >&2
  exit 2
fi

concurrency="${FIRST_ARRAY_CONCURRENCY:-${HYAK_ARRAY_CONCURRENCY:-10}}"
last_index="$((subject_count - 1))"

echo "Subject list: $subject_list"
echo "Subject count: $subject_count"
echo "Array range: 0-${last_index}%${concurrency}"

sbatch \
  --array="0-${last_index}%${concurrency}" \
  --partition="${HYAK_PARTITION:-ckpt-all}" \
  --time="${FIRST_HYAK_TIME:-12:00:00}" \
  "${REPO_DIR}/scripts/submit_first_hyak.sbatch" \
  "$CONFIG_ENV" \
  "$subject_list"
