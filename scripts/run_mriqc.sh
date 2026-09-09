#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/run_mriqc.sh CONFIG_ENV [participant|group]

Runs MRIQC for raw-image QC. Participant mode may run all configured subjects,
or one SLURM array subject when MRIQC_SINGLE_SUBJECT is set by the submitter.
Run group mode after participant-level jobs finish.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 0
fi

CONFIG_ENV="$1"
MRIQC_LEVEL="${2:-participant}"

if [[ "$MRIQC_LEVEL" != "participant" && "$MRIQC_LEVEL" != "group" ]]; then
  echo "ERROR: MRIQC level must be participant or group, got: $MRIQC_LEVEL" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$CONFIG_ENV"

MRIQC_OUT="${MRIQC_OUT:-${DERIVATIVES_DIR}/qc/mriqc}"
MRIQC_WORK="${MRIQC_WORK:-${PROJECT_DIR}/scratch/mriqc_work}"
MRIQC_LOG_DIR="${MRIQC_LOG_DIR:-${PROJECT_DIR}/logs/mriqc}"
MRIQC_NO_SUB="${MRIQC_NO_SUB:-1}"
MRIQC_MODALITIES="${MRIQC_MODALITIES:-T1w T2w bold}"
MRIQC_NPROC="${MRIQC_NPROC:-${NTHREADS:-8}}"
MRIQC_OMP_NTHREADS="${MRIQC_OMP_NTHREADS:-${OMP_NTHREADS:-4}}"
MRIQC_MEM_GB="${MRIQC_MEM_GB:-64}"

if [[ -n "${MRIQC_SINGLE_SUBJECT:-}" ]]; then
  MRIQC_PARTICIPANT_LABELS="$MRIQC_SINGLE_SUBJECT"
  subject_work_label="${MRIQC_SINGLE_SUBJECT#sub-}"
  MRIQC_WORK="${MRIQC_WORK}/${subject_work_label}"
fi

required_vars=(
  BIDS_DIR MRIQC_OUT MRIQC_WORK MRIQC_LOG_DIR CONTAINER_RUNTIME MRIQC_IMAGE
  MRIQC_NPROC MRIQC_OMP_NTHREADS MRIQC_MEM_GB
)

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

if [[ ! -f "$MRIQC_IMAGE" && "$CONTAINER_RUNTIME" != "docker" ]]; then
  echo "ERROR: MRIQC_IMAGE does not exist: $MRIQC_IMAGE" >&2
  echo "Build or copy the frozen MRIQC image before submitting Hyak jobs." >&2
  exit 2
fi

mkdir -p "$MRIQC_OUT" "$MRIQC_WORK" "$MRIQC_LOG_DIR" "${MRIQC_WORK}/matplotlib"

mriqc_args=(
  /data
  /out
  "$MRIQC_LEVEL"
  --nprocs
  "$MRIQC_NPROC"
  --omp-nthreads
  "$MRIQC_OMP_NTHREADS"
  --mem
  "$MRIQC_MEM_GB"
  --work-dir
  /work
)

if [[ -n "${MRIQC_MODALITIES:-}" ]]; then
  mriqc_args+=(-m)
  # shellcheck disable=SC2206
  modality_array=($MRIQC_MODALITIES)
  mriqc_args+=("${modality_array[@]}")
fi

if [[ "$MRIQC_LEVEL" == "participant" && -n "${MRIQC_PARTICIPANT_LABELS:-}" ]]; then
  mriqc_args+=(--participant-label)
  # shellcheck disable=SC2206
  participant_array=($MRIQC_PARTICIPANT_LABELS)
  participant_labels=()
  for participant in "${participant_array[@]}"; do
    participant_labels+=("${participant#sub-}")
  done
  mriqc_args+=("${participant_labels[@]}")
fi

if [[ "$MRIQC_NO_SUB" == "1" ]]; then
  mriqc_args+=(--no-sub)
fi

if [[ -n "${EXTRA_MRIQC_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra_args=($EXTRA_MRIQC_ARGS)
  mriqc_args+=("${extra_args[@]}")
fi

apptainer_no_mount_args=()
if [[ -n "${APPTAINER_NO_MOUNT:-bind-paths}" ]]; then
  apptainer_no_mount_args=(--no-mount "${APPTAINER_NO_MOUNT:-bind-paths}")
fi

export APPTAINER_BINDPATH=""
export SINGULARITY_BINDPATH=""

timestamp="$(date +%Y%m%d_%H%M%S)"
log_label="$MRIQC_LEVEL"
if [[ -n "${MRIQC_SINGLE_SUBJECT:-}" ]]; then
  log_label="${log_label}_${MRIQC_SINGLE_SUBJECT}"
elif [[ -n "${MRIQC_PARTICIPANT_LABELS:-}" ]]; then
  log_label="${log_label}_$(echo "$MRIQC_PARTICIPANT_LABELS" | tr ' /' '__')"
fi
array_label="${SLURM_ARRAY_TASK_ID:-manual}"
command_log="${MRIQC_LOG_DIR}/mriqc_command_${log_label}_${array_label}_${timestamp}.txt"
run_log="${MRIQC_LOG_DIR}/mriqc_run_${log_label}_${array_label}_${timestamp}.log"

{
  echo "CONFIG_ENV=$CONFIG_ENV"
  echo "MRIQC_IMAGE=$MRIQC_IMAGE"
  echo "CONTAINER_RUNTIME=$CONTAINER_RUNTIME"
  echo "MRIQC_LEVEL=$MRIQC_LEVEL"
  echo "MRIQC_PARTICIPANT_LABELS=${MRIQC_PARTICIPANT_LABELS:-}"
  echo "MRIQC_MODALITIES=${MRIQC_MODALITIES:-}"
  printf 'mriqc args:'
  printf ' %q' "${mriqc_args[@]}"
  echo
} > "$command_log"

case "$CONTAINER_RUNTIME" in
  docker)
    docker run --rm \
      -v "${BIDS_DIR}:/data:ro" \
      -v "${MRIQC_OUT}:/out" \
      -v "${MRIQC_WORK}:/work" \
      -e MPLCONFIGDIR=/work/matplotlib \
      "$MRIQC_IMAGE" \
      "${mriqc_args[@]}" 2>&1 | tee "$run_log"
    ;;
  apptainer)
    apptainer run --cleanenv \
      "${apptainer_no_mount_args[@]}" \
      -B "${BIDS_DIR}:/data:ro" \
      -B "${MRIQC_OUT}:/out" \
      -B "${MRIQC_WORK}:/work" \
      --env MPLCONFIGDIR=/work/matplotlib \
      "$MRIQC_IMAGE" \
      "${mriqc_args[@]}" 2>&1 | tee "$run_log"
    ;;
  singularity)
    singularity run --cleanenv \
      "${apptainer_no_mount_args[@]}" \
      -B "${BIDS_DIR}:/data:ro" \
      -B "${MRIQC_OUT}:/out" \
      -B "${MRIQC_WORK}:/work" \
      --env MPLCONFIGDIR=/work/matplotlib \
      "$MRIQC_IMAGE" \
      "${mriqc_args[@]}" 2>&1 | tee "$run_log"
    ;;
  *)
    echo "ERROR: Unsupported CONTAINER_RUNTIME: $CONTAINER_RUNTIME" >&2
    exit 2
    ;;
esac

echo "Command record: $command_log"
echo "Run log: $run_log"
