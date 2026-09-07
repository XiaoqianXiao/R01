#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
  echo "Usage: scripts/submit_msmall_array_hyak.sh CONFIG_ENV"
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

if [[ -z "${MSMALL_HCP_STUDY_FOLDER:-}" && "${MSMALL_ALLOW_WITHOUT_HCP:-0}" != "1" ]]; then
  cat >&2 <<'MSG'
ERROR: MSMAll submission requires HCP-style inputs.

MSMALL_HCP_STUDY_FOLDER is empty. MSMAll cannot be generated directly from
fMRIPrep outputs; it requires HCP Minimal Preprocessing/FIX outputs with
SUBJECT/MNINonLinear inputs. Set MSMALL_HCP_STUDY_FOLDER after those inputs
exist, or set MSMALL_ALLOW_WITHOUT_HCP=1 only for a deliberate dry/preflight run.
MSG
  exit 2
fi

timestamp="$(date +%Y%m%d_%H%M%S)"
subject_list="${LOG_DIR}/msmall_subjects_${timestamp}.txt"

find "$FMRIPREP_OUT" -maxdepth 1 -type d -name 'sub-*' -exec basename {} \; | sort > "$subject_list"
subject_count="$(wc -l < "$subject_list" | tr -d ' ')"
if [[ "$subject_count" -eq 0 ]]; then
  echo "ERROR: no sub-* directories found in FMRIPREP_OUT: $FMRIPREP_OUT" >&2
  exit 2
fi

concurrency="${MSMALL_ARRAY_CONCURRENCY:-${HYAK_ARRAY_CONCURRENCY:-10}}"
last_index="$((subject_count - 1))"

echo "Subject list: $subject_list"
echo "Subject count: $subject_count"
echo "Array range: 0-${last_index}%${concurrency}"

sbatch \
  --array="0-${last_index}%${concurrency}" \
  --partition="${HYAK_PARTITION:-ckpt-all}" \
  --time="${MSMALL_HYAK_TIME:-${HYAK_TIME:-48:00:00}}" \
  "${REPO_DIR}/scripts/submit_msmall_hyak.sbatch" \
  "$CONFIG_ENV" \
  "$subject_list"
