#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/prefetch_hippunfold_models_hyak.sh CONFIG_ENV

Populates the shared HippUnfold model cache before array jobs.
Run this from an internet-enabled Hyak login/data-transfer context, not inside
the HippUnfold SLURM array.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
  usage
  exit 0
fi

CONFIG_ENV="$1"
# shellcheck source=/dev/null
source "$CONFIG_ENV"

HIPPUNFOLD_OUT="${HIPPUNFOLD_OUT:-${DERIVATIVES_DIR}/hippunfold}"
HIPPUNFOLD_WORK="${HIPPUNFOLD_WORK:-${PROJECT_DIR}/scratch/hippunfold_work}"
HIPPUNFOLD_CACHE_DIR="${HIPPUNFOLD_CACHE_DIR:-${PROJECT_DIR}/cache/hippunfold}"
HIPPUNFOLD_MODALITY="${HIPPUNFOLD_MODALITY:-T1w}"

required_vars=(DERIVATIVES_DIR HIPPUNFOLD_OUT HIPPUNFOLD_WORK HIPPUNFOLD_CACHE_DIR HIPPUNFOLD_MODALITY)
for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "ERROR: $var_name is not set in $CONFIG_ENV" >&2
    exit 2
  fi
done

hippunfold_model_file() {
  case "$1" in
    T1w) echo "trained_model.3d_fullres.Task101_hcp1200_T1w.nnUNetTrainerV2.model_best.tar" ;;
    T2w) echo "trained_model.3d_fullres.Task102_hcp1200_T2w.nnUNetTrainerV2.model_best.tar" ;;
    b1000|b1000crop) echo "trained_model.3d_fullres.Task110_hcp1200_b1000crop.nnUNetTrainerV2.model_best.tar" ;;
    *) echo "" ;;
  esac
}

hippunfold_model_url() {
  case "$1" in
    T1w) echo "https://zenodo.org/record/4508747/files/trained_model.3d_fullres.Task101_hcp1200_T1w.nnUNetTrainerV2.model_best.tar" ;;
    T2w) echo "https://zenodo.org/record/4508747/files/trained_model.3d_fullres.Task102_hcp1200_T2w.nnUNetTrainerV2.model_best.tar" ;;
    b1000|b1000crop) echo "https://zenodo.org/record/5732291/files/trained_model.3d_fullres.Task110_hcp1200_b1000crop.nnUNetTrainerV2.model_best.tar" ;;
    *) echo "" ;;
  esac
}

mkdir -p "$HIPPUNFOLD_OUT" "$HIPPUNFOLD_WORK" "${HIPPUNFOLD_CACHE_DIR}/model"
snakebids_marker="${HIPPUNFOLD_OUT}/.snakebids"
tmp_marker="${snakebids_marker}.tmp.$$"
printf '%s\n' '{"mode":"bidsapp"}' > "$tmp_marker"
mv "$tmp_marker" "$snakebids_marker"

echo "HippUnfold model cache: $HIPPUNFOLD_CACHE_DIR"
echo "Prefetching modality: $HIPPUNFOLD_MODALITY"
required_model="${HIPPUNFOLD_REQUIRED_MODEL:-$(hippunfold_model_file "$HIPPUNFOLD_MODALITY")}"
model_url="$(hippunfold_model_url "$HIPPUNFOLD_MODALITY")"
if [[ -z "$required_model" || -z "$model_url" ]]; then
  echo "ERROR: no built-in model URL is configured for HIPPUNFOLD_MODALITY=$HIPPUNFOLD_MODALITY" >&2
  echo "Set HIPPUNFOLD_REQUIRED_MODEL and download/extract it under ${HIPPUNFOLD_CACHE_DIR}/model." >&2
  exit 2
fi

model_tar="${HIPPUNFOLD_CACHE_DIR}/model/${required_model}"
model_dir="${model_tar%.tar}"
legacy_model_tar="${HIPPUNFOLD_CACHE_DIR}/${required_model}"
if [[ ! -f "$model_tar" && -f "$legacy_model_tar" ]]; then
  mv "$legacy_model_tar" "$model_tar"
fi

if [[ ! -f "$model_tar" ]]; then
  tmp_model="${model_tar}.tmp.$$"
  if command -v curl >/dev/null 2>&1; then
    curl -fL "$model_url" -o "$tmp_model"
  elif command -v wget >/dev/null 2>&1; then
    wget "$model_url" -O "$tmp_model"
  else
    echo "ERROR: neither curl nor wget is available for model download." >&2
    exit 127
  fi
  mv "$tmp_model" "$model_tar"
fi

if [[ ! -s "$model_tar" ]]; then
  echo "ERROR: downloaded model is missing or empty: $model_tar" >&2
  exit 2
fi

if [[ ! -d "$model_dir" ]]; then
  mkdir -p "$model_dir"
  tar -xf "$model_tar" -C "$model_dir"
fi

echo "HippUnfold model cache is ready: $HIPPUNFOLD_CACHE_DIR"
echo "Model tar: $model_tar"
echo "Model directory: $model_dir"
