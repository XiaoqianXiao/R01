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
HCP_STRUCTURAL_OUT="${HCP_STRUCTURAL_OUT:-${DERIVATIVES_DIR}/hcp}"
HCP_FMRI_CONCAT_NAME="${HCP_FMRI_CONCAT_NAME:-fMRI_CONCAT}"
HCP_FMRI_HIGH_PASS="${HCP_FMRI_HIGH_PASS:-0}"

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
skipped_list="${LOG_DIR}/msmall_skipped_missing_hcp_inputs_${timestamp}.txt"

find "$FMRIPREP_OUT" -maxdepth 1 -type d -name 'sub-*' -exec basename {} \; | sort | while read -r subject; do
  session="${subject#sub-}"
  hcp_subject_dir=""
  if [[ -d "${HCP_STRUCTURAL_OUT}/${session}/MNINonLinear" ]]; then
    hcp_subject_dir="${HCP_STRUCTURAL_OUT}/${session}"
  elif [[ -d "${HCP_STRUCTURAL_OUT}/${subject}/MNINonLinear" ]]; then
    hcp_subject_dir="${HCP_STRUCTURAL_OUT}/${subject}"
  fi

  if [[ -z "$hcp_subject_dir" ]]; then
    echo "${subject},missing_mninonlinear" >> "$skipped_list"
    continue
  fi
  if [[ ! -f "${hcp_subject_dir}/MNINonLinear/Native/${session}.MyelinMap.native.dscalar.nii" && ! -f "${hcp_subject_dir}/MNINonLinear/Native/${subject}.MyelinMap.native.dscalar.nii" ]]; then
    echo "${subject},missing_myelin_map" >> "$skipped_list"
    continue
  fi
  if [[ ! -f "${hcp_subject_dir}/MNINonLinear/Results/hcp_functional_msmall_inputs.txt" ]]; then
    echo "${subject},missing_functional_manifest" >> "$skipped_list"
    continue
  fi
  if [[ ! -f "${hcp_subject_dir}/MNINonLinear/Results/${HCP_FMRI_CONCAT_NAME}/${HCP_FMRI_CONCAT_NAME}_Atlas_hp${HCP_FMRI_HIGH_PASS}_clean.dtseries.nii" ]]; then
    echo "${subject},missing_fix_dtseries" >> "$skipped_list"
    continue
  fi
  if [[ ! -f "${hcp_subject_dir}/MNINonLinear/Results/${HCP_FMRI_CONCAT_NAME}/${HCP_FMRI_CONCAT_NAME}_Atlas_hp${HCP_FMRI_HIGH_PASS}_clean_vn.dscalar.nii" ]]; then
    echo "${subject},missing_fix_vn" >> "$skipped_list"
    continue
  fi
  echo "$subject"
done > "$subject_list"

if [[ -f "$skipped_list" ]]; then
  skipped_count="$(wc -l < "$skipped_list" | tr -d ' ')"
else
  skipped_count="0"
fi
subject_count="$(wc -l < "$subject_list" | tr -d ' ')"
if [[ "$subject_count" -eq 0 ]]; then
  echo "ERROR: no MSMAll-ready subjects found from FMRIPREP_OUT: $FMRIPREP_OUT" >&2
  echo "Skipped list: $skipped_list" >&2
  exit 2
fi

concurrency="${MSMALL_ARRAY_CONCURRENCY:-${HYAK_ARRAY_CONCURRENCY:-10}}"
if ! [[ "$concurrency" =~ ^[0-9]+$ ]] || [[ "$concurrency" -lt 1 ]]; then
  echo "ERROR: MSMALL_ARRAY_CONCURRENCY/HYAK_ARRAY_CONCURRENCY must be a positive integer." >&2
  exit 2
fi
last_index="$((subject_count - 1))"

echo "Subject list: $subject_list"
echo "Subject count: $subject_count"
echo "Skipped for missing HCP/MSMAll inputs: $skipped_count"
if [[ "$skipped_count" -gt 0 ]]; then
  echo "Skipped list: $skipped_list"
fi
echo "Array range: 0-${last_index}%${concurrency}"

sbatch \
  --array="0-${last_index}%${concurrency}" \
  --partition="${HYAK_PARTITION:-ckpt-all}" \
  --time="${MSMALL_HYAK_TIME:-${HYAK_TIME:-48:00:00}}" \
  "${REPO_DIR}/scripts/submit_msmall_hyak.sbatch" \
  "$CONFIG_ENV" \
  "$subject_list"
