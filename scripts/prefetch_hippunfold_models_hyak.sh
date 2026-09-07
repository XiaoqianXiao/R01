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
HIPPUNFOLD_CORES="${HIPPUNFOLD_CORES:-1}"
HIPPUNFOLD_CONTAINER_ENTRYPOINT="${HIPPUNFOLD_CONTAINER_ENTRYPOINT:-/src/.pixi/envs/default/bin/hippunfold}"

required_vars=(BIDS_DIR DERIVATIVES_DIR HIPPUNFOLD_IMAGE CONTAINER_RUNTIME HIPPUNFOLD_OUT HIPPUNFOLD_WORK HIPPUNFOLD_CACHE_DIR HIPPUNFOLD_MODALITY)
for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "ERROR: $var_name is not set in $CONFIG_ENV" >&2
    exit 2
  fi
done

if [[ ! -d "$BIDS_DIR" ]]; then
  echo "ERROR: BIDS_DIR does not exist: $BIDS_DIR" >&2
  exit 2
fi
if [[ ! -f "$HIPPUNFOLD_IMAGE" ]]; then
  echo "ERROR: HIPPUNFOLD_IMAGE does not exist: $HIPPUNFOLD_IMAGE" >&2
  exit 2
fi

runtime="${CONTAINER_RUNTIME:-apptainer}"
if [[ "$runtime" == "docker" ]]; then
  runtime="apptainer"
fi

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
export LD_PRELOAD="${LD_PRELOAD:-}"

if command -v module >/dev/null 2>&1; then
  module load apptainer >/dev/null 2>&1 || module load singularity >/dev/null 2>&1 || true
fi

if ! command -v "$runtime" >/dev/null 2>&1; then
  if command -v apptainer >/dev/null 2>&1; then
    runtime="apptainer"
  elif command -v singularity >/dev/null 2>&1; then
    runtime="singularity"
  else
    echo "ERROR: Apptainer/Singularity is not available." >&2
    exit 127
  fi
fi

mkdir -p "$HIPPUNFOLD_OUT" "$HIPPUNFOLD_WORK" "$HIPPUNFOLD_CACHE_DIR"

no_mount_args=()
if [[ -n "${APPTAINER_NO_MOUNT:-bind-paths}" ]]; then
  no_mount_args=(--no-mount "${APPTAINER_NO_MOUNT:-bind-paths}")
fi

export APPTAINER_BINDPATH=""
export SINGULARITY_BINDPATH=""

echo "HippUnfold model cache: $HIPPUNFOLD_CACHE_DIR"
echo "Prefetching modality: $HIPPUNFOLD_MODALITY"

"$runtime" exec --cleanenv \
  "${no_mount_args[@]}" \
  -B "${BIDS_DIR}:/data:ro" \
  -B "${HIPPUNFOLD_OUT}:/out" \
  -B "${HIPPUNFOLD_WORK}:/work" \
  -B "${HIPPUNFOLD_CACHE_DIR}:/hippunfold_cache" \
  --env HIPPUNFOLD_CACHE_DIR=/hippunfold_cache \
  "$HIPPUNFOLD_IMAGE" \
  "$HIPPUNFOLD_CONTAINER_ENTRYPOINT" \
  /data /out participant \
  --modality "$HIPPUNFOLD_MODALITY" \
  --cores "$HIPPUNFOLD_CORES" \
  --until download_model

echo "HippUnfold model cache is ready: $HIPPUNFOLD_CACHE_DIR"
