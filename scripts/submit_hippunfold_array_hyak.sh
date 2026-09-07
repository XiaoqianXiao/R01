#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
  echo "Usage: scripts/submit_hippunfold_array_hyak.sh CONFIG_ENV"
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
subject_list="${LOG_DIR}/hippunfold_subjects_${timestamp}.txt"
session_manifest="${LOG_DIR}/hippunfold_multisession_manifest_${timestamp}.csv"

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

concurrency="${HIPPUNFOLD_ARRAY_CONCURRENCY:-${HYAK_ARRAY_CONCURRENCY:-10}}"
last_index="$((subject_count - 1))"

echo "Subject list: $subject_list"
echo "Session manifest: $session_manifest"
echo "Subject count: $subject_count"
echo "Array range: 0-${last_index}%${concurrency}"

sbatch \
  --array="0-${last_index}%${concurrency}" \
  --partition="${HYAK_PARTITION:-ckpt-all}" \
  --time="${HIPPUNFOLD_HYAK_TIME:-${HYAK_TIME:-48:00:00}}" \
  "${REPO_DIR}/scripts/submit_hippunfold_hyak.sbatch" \
  "$CONFIG_ENV" \
  "$subject_list"
