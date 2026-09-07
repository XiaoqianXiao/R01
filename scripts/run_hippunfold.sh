#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/run_hippunfold.sh CONFIG_ENV

Runs the separate HippUnfold derivative branch. For SLURM arrays, the worker
sets HIPPUNFOLD_SINGLE_SUBJECT and this script runs one participant.
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
HIPPUNFOLD_PARTICIPANT_LABELS="${HIPPUNFOLD_PARTICIPANT_LABELS:-}"
HIPPUNFOLD_MODALITY="${HIPPUNFOLD_MODALITY:-T1w}"
HIPPUNFOLD_CORES="${HIPPUNFOLD_CORES:-${NTHREADS:-all}}"
HIPPUNFOLD_CONTAINER_ENTRYPOINT="${HIPPUNFOLD_CONTAINER_ENTRYPOINT:-/src/.pixi/envs/default/bin/hippunfold}"
if [[ -n "${HIPPUNFOLD_SINGLE_SUBJECT:-}" ]]; then
  HIPPUNFOLD_PARTICIPANT_LABELS="$HIPPUNFOLD_SINGLE_SUBJECT"
  HIPPUNFOLD_WORK="${HIPPUNFOLD_WORK}/${HIPPUNFOLD_SINGLE_SUBJECT#sub-}"
fi

required_vars=(BIDS_DIR DERIVATIVES_DIR LOG_DIR HIPPUNFOLD_OUT HIPPUNFOLD_WORK HIPPUNFOLD_IMAGE CONTAINER_RUNTIME HIPPUNFOLD_MODALITY HIPPUNFOLD_CORES)
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

mkdir -p "$HIPPUNFOLD_OUT" "$HIPPUNFOLD_WORK" "$LOG_DIR"

hippunfold_args=(/data /out participant --modality "$HIPPUNFOLD_MODALITY" --cores "$HIPPUNFOLD_CORES")
if [[ -n "$HIPPUNFOLD_PARTICIPANT_LABELS" ]]; then
  hippunfold_args+=(--participant-label)
  # shellcheck disable=SC2206
  participant_array=($HIPPUNFOLD_PARTICIPANT_LABELS)
  for participant in "${participant_array[@]}"; do
    hippunfold_args+=("${participant#sub-}")
  done
fi
if [[ -n "${EXTRA_HIPPUNFOLD_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra_args=($EXTRA_HIPPUNFOLD_ARGS)
  hippunfold_args+=("${extra_args[@]}")
fi

apptainer_no_mount_args=()
if [[ -n "${APPTAINER_NO_MOUNT:-bind-paths}" ]]; then
  apptainer_no_mount_args=(--no-mount "${APPTAINER_NO_MOUNT:-bind-paths}")
fi

export APPTAINER_BINDPATH=""
export SINGULARITY_BINDPATH=""
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
export LD_PRELOAD="${LD_PRELOAD:-}"

timestamp="$(date +%Y%m%d_%H%M%S)"
log_label="${HIPPUNFOLD_PARTICIPANT_LABELS:-all_subjects}"
log_label="$(echo "$log_label" | tr ' /' '__')"
array_label="${SLURM_ARRAY_TASK_ID:-manual}"
command_log="${LOG_DIR}/hippunfold_command_${log_label}_${array_label}_${timestamp}.txt"
run_log="${LOG_DIR}/hippunfold_run_${log_label}_${array_label}_${timestamp}.log"

{
  echo "CONFIG_ENV=$CONFIG_ENV"
  echo "HIPPUNFOLD_IMAGE=$HIPPUNFOLD_IMAGE"
  echo "CONTAINER_RUNTIME=$CONTAINER_RUNTIME"
  echo "HIPPUNFOLD_PARTICIPANT_LABELS=$HIPPUNFOLD_PARTICIPANT_LABELS"
  echo "HIPPUNFOLD_MODALITY=$HIPPUNFOLD_MODALITY"
  echo "HIPPUNFOLD_CORES=$HIPPUNFOLD_CORES"
  echo "HIPPUNFOLD_CONTAINER_ENTRYPOINT=$HIPPUNFOLD_CONTAINER_ENTRYPOINT"
  printf 'hippunfold args:'
  printf ' %q' "${hippunfold_args[@]}"
  echo
} > "$command_log"

case "$CONTAINER_RUNTIME" in
  docker)
    docker run --rm \
      -v "${BIDS_DIR}:/data:ro" \
      -v "${HIPPUNFOLD_OUT}:/out" \
      -v "${HIPPUNFOLD_WORK}:/work" \
      "$HIPPUNFOLD_IMAGE" \
      hippunfold \
      "${hippunfold_args[@]}" 2>&1 | tee "$run_log"
    ;;
  apptainer)
    apptainer exec --cleanenv \
      "${apptainer_no_mount_args[@]}" \
      -B "${BIDS_DIR}:/data:ro" \
      -B "${HIPPUNFOLD_OUT}:/out" \
      -B "${HIPPUNFOLD_WORK}:/work" \
      "$HIPPUNFOLD_IMAGE" \
      "$HIPPUNFOLD_CONTAINER_ENTRYPOINT" \
      "${hippunfold_args[@]}" 2>&1 | tee "$run_log"
    ;;
  singularity)
    singularity exec --cleanenv \
      "${apptainer_no_mount_args[@]}" \
      -B "${BIDS_DIR}:/data:ro" \
      -B "${HIPPUNFOLD_OUT}:/out" \
      -B "${HIPPUNFOLD_WORK}:/work" \
      "$HIPPUNFOLD_IMAGE" \
      "$HIPPUNFOLD_CONTAINER_ENTRYPOINT" \
      "${hippunfold_args[@]}" 2>&1 | tee "$run_log"
    ;;
  *)
    echo "ERROR: Unsupported CONTAINER_RUNTIME: $CONTAINER_RUNTIME" >&2
    exit 2
    ;;
esac

echo "Command record: $command_log"
echo "Run log: $run_log"
