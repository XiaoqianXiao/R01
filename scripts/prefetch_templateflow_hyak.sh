#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/prefetch_templateflow_hyak.sh CONFIG_ENV

Populates the configured TEMPLATEFLOW_HOME cache before fMRIPrep production.
Run this from an internet-enabled Hyak login/data-transfer context, not inside
the fMRIPrep SLURM array.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
  usage
  exit 0
fi

CONFIG_ENV="$1"
# shellcheck source=/dev/null
source "$CONFIG_ENV"

if [[ -z "${TEMPLATEFLOW_HOME:-}" ]]; then
  if [[ -z "${PROJECT_DIR:-}" ]]; then
    echo "ERROR: TEMPLATEFLOW_HOME is empty and PROJECT_DIR is not set in $CONFIG_ENV" >&2
    exit 2
  fi
  TEMPLATEFLOW_HOME="${PROJECT_DIR}/templateflow"
  echo "TEMPLATEFLOW_HOME is empty; using default: $TEMPLATEFLOW_HOME" >&2
fi

if [[ -z "${FMRIPREP_IMAGE:-}" || ! -f "$FMRIPREP_IMAGE" ]]; then
  echo "ERROR: FMRIPREP_IMAGE is not set or does not exist: ${FMRIPREP_IMAGE:-}" >&2
  exit 2
fi

runtime="${CONTAINER_RUNTIME:-apptainer}"
if [[ "$runtime" == "docker" ]]; then
  runtime="apptainer"
fi

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

mkdir -p "$TEMPLATEFLOW_HOME"

no_mount_args=()
if [[ -n "${APPTAINER_NO_MOUNT:-bind-paths}" ]]; then
  no_mount_args=(--no-mount "${APPTAINER_NO_MOUNT:-bind-paths}")
fi

export APPTAINER_BINDPATH=""
export SINGULARITY_BINDPATH=""

"$runtime" exec --cleanenv \
  "${no_mount_args[@]}" \
  -B "${TEMPLATEFLOW_HOME}:/templateflow" \
  --env TEMPLATEFLOW_HOME=/templateflow \
  "$FMRIPREP_IMAGE" \
  python - <<'PY'
from pathlib import Path
from templateflow import api as tf

templates = [
    "MNI152NLin6Asym",
    "MNI152NLin2009cAsym",
    "OASIS30ANTs",
    "fsaverage",
    "fsLR",
]

for template in templates:
    print(f"Fetching TemplateFlow template: {template}", flush=True)
    files = tf.get(template, raise_empty=True)
    if isinstance(files, (str, Path)):
        files = [files]
    print(f"  cached {len(files)} files", flush=True)

required = Path("/templateflow/tpl-MNI152NLin6Asym/tpl-MNI152NLin6Asym_res-01_T1w.nii.gz")
if not required.exists():
    raise SystemExit(f"Required TemplateFlow file is still missing: {required}")

print("TemplateFlow cache is ready.", flush=True)
PY
