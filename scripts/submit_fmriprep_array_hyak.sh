#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/submit_fmriprep_array_hyak.sh CONFIG_ENV

Generates a subject/session manifest from BIDS_DIR and submits one Hyak SLURM
array task per subject. Each task runs fMRIPrep for exactly one subject with all
sessions visible to fMRIPrep.
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

mkdir -p logs/slurm "$LOG_DIR"

if [[ ! -d "$BIDS_DIR" ]]; then
  echo "ERROR: BIDS_DIR does not exist: $BIDS_DIR" >&2
  exit 2
fi

if [[ -z "${TEMPLATEFLOW_HOME:-}" ]]; then
  if [[ -z "${PROJECT_DIR:-}" ]]; then
    echo "ERROR: PROJECT_DIR is not set in $CONFIG_ENV" >&2
    echo "PROJECT_DIR is needed to locate the project TemplateFlow cache." >&2
    exit 2
  fi
  TEMPLATEFLOW_HOME="${PROJECT_DIR}/templateflow"
fi

required_template="${TEMPLATEFLOW_HOME}/tpl-MNI152NLin6Asym/tpl-MNI152NLin6Asym_res-01_T1w.nii.gz"
if [[ ! -f "$required_template" ]]; then
  echo "ERROR: TemplateFlow cache is not ready for offline Hyak fMRIPrep jobs." >&2
  echo "Missing required file: $required_template" >&2
  echo "Run scripts/prefetch_templateflow_hyak.sh $CONFIG_ENV from an internet-enabled Hyak context, then resubmit." >&2
  exit 2
fi

timestamp="$(date +%Y%m%d_%H%M%S)"
subject_list="${LOG_DIR}/fmriprep_subjects_${timestamp}.txt"
session_manifest="${LOG_DIR}/fmriprep_multisession_manifest_${timestamp}.csv"

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

concurrency="${HYAK_ARRAY_CONCURRENCY:-10}"
if ! [[ "$concurrency" =~ ^[0-9]+$ ]] || [[ "$concurrency" -lt 1 ]]; then
  echo "ERROR: HYAK_ARRAY_CONCURRENCY must be a positive integer." >&2
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
  --time="${HYAK_TIME:-48:00:00}" \
  "${REPO_DIR}/scripts/submit_fmriprep_hyak.sbatch" \
  "$CONFIG_ENV" \
  "$subject_list"
