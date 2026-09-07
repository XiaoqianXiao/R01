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
HIPPUNFOLD_OUT="${HIPPUNFOLD_OUT:-${DERIVATIVES_DIR}/hippunfold}"
HIPPUNFOLD_CACHE_DIR="${HIPPUNFOLD_CACHE_DIR:-${PROJECT_DIR}/cache/hippunfold}"
HIPPUNFOLD_MODALITY="${HIPPUNFOLD_MODALITY:-T1w}"
HIPPUNFOLD_REQUIRE_CACHED_MODEL="${HIPPUNFOLD_REQUIRE_CACHED_MODEL:-1}"
mkdir -p logs/slurm "$LOG_DIR" "$HIPPUNFOLD_OUT" "${HIPPUNFOLD_CACHE_DIR}/model"

hippunfold_model_file() {
  case "$1" in
    T1w) echo "trained_model.3d_fullres.Task101_hcp1200_T1w.nnUNetTrainerV2.model_best.tar" ;;
    T2w) echo "trained_model.3d_fullres.Task102_hcp1200_T2w.nnUNetTrainerV2.model_best.tar" ;;
    b1000|b1000crop) echo "trained_model.3d_fullres.Task110_hcp1200_b1000crop.nnUNetTrainerV2.model_best.tar" ;;
    *) echo "" ;;
  esac
}

required_model="${HIPPUNFOLD_REQUIRED_MODEL:-$(hippunfold_model_file "$HIPPUNFOLD_MODALITY")}"
required_model_tar="${HIPPUNFOLD_CACHE_DIR}/model/${required_model}"
if [[ "$HIPPUNFOLD_REQUIRE_CACHED_MODEL" == "1" && -n "$required_model" && ! -f "$required_model_tar" ]]; then
  cat >&2 <<MSG
ERROR: HippUnfold model is not cached: $required_model_tar

Run this from an internet-enabled Hyak login or data-transfer context before
submitting the array:

  scripts/prefetch_hippunfold_models_hyak.sh ${CONFIG_ENV}

Set HIPPUNFOLD_REQUIRE_CACHED_MODEL=0 only for a deliberate online test.
MSG
  exit 2
fi

snakebids_marker="${HIPPUNFOLD_OUT}/.snakebids"
tmp_marker="${snakebids_marker}.tmp.$$"
printf '%s\n' '{"mode":"bidsapp"}' > "$tmp_marker"
mv "$tmp_marker" "$snakebids_marker"

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
