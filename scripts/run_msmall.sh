#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/run_msmall.sh CONFIG_ENV

Runs the separate MSMAll derivative branch for eligible subjects. This wrapper
handles subject selection, logging, and container binds. The project-specific
HCP/MSMAll bridge is supplied by MSMALL_DRIVER_SCRIPT.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
  usage
  exit 0
fi

CONFIG_ENV="$1"
# shellcheck source=/dev/null
source "$CONFIG_ENV"

MSMALL_OUT="${MSMALL_OUT:-${DERIVATIVES_DIR}/msmall}"
MSMALL_WORK="${MSMALL_WORK:-${PROJECT_DIR}/scratch/msmall_work}"
MSMALL_PARTICIPANT_LABELS="${MSMALL_PARTICIPANT_LABELS:-}"
if [[ -n "${MSMALL_SINGLE_SUBJECT:-}" ]]; then
  MSMALL_PARTICIPANT_LABELS="$MSMALL_SINGLE_SUBJECT"
  MSMALL_WORK="${MSMALL_WORK}/${MSMALL_SINGLE_SUBJECT#sub-}"
fi

required_vars=(BIDS_DIR FMRIPREP_OUT FS_SUBJECTS_DIR DERIVATIVES_DIR LOG_DIR PROVENANCE_DIR MSMALL_OUT MSMALL_WORK MSMALL_IMAGE MSMALL_DRIVER_SCRIPT CONTAINER_RUNTIME)
for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "ERROR: $var_name is not set in $CONFIG_ENV" >&2
    exit 2
  fi
done
for path_var in BIDS_DIR FMRIPREP_OUT FS_SUBJECTS_DIR; do
  if [[ ! -d "${!path_var}" ]]; then
    echo "ERROR: $path_var does not exist: ${!path_var}" >&2
    exit 2
  fi
done
if [[ ! -f "$MSMALL_IMAGE" ]]; then
  echo "ERROR: MSMALL_IMAGE does not exist: $MSMALL_IMAGE" >&2
  exit 2
fi
if [[ ! -e "$MSMALL_DRIVER_SCRIPT" ]]; then
  echo "ERROR: MSMALL_DRIVER_SCRIPT does not exist: $MSMALL_DRIVER_SCRIPT" >&2
  echo "Set MSMALL_DRIVER_SCRIPT to an executable project-specific HCP/MSMAll bridge." >&2
  echo "Use scripts/msmall_driver_template.sh as the interface template." >&2
  exit 2
fi
if [[ ! -x "$MSMALL_DRIVER_SCRIPT" ]]; then
  echo "ERROR: MSMALL_DRIVER_SCRIPT exists but is not executable: $MSMALL_DRIVER_SCRIPT" >&2
  echo "Use scripts/msmall_driver_template.sh as the interface template." >&2
  exit 2
fi

mkdir -p "$MSMALL_OUT" "$MSMALL_WORK" "$LOG_DIR" "$PROVENANCE_DIR"

if [[ -n "$MSMALL_PARTICIPANT_LABELS" ]]; then
  # shellcheck disable=SC2206
  subjects=($MSMALL_PARTICIPANT_LABELS)
else
  mapfile -t subjects < <(find "$FMRIPREP_OUT" -maxdepth 1 -type d -name 'sub-*' -exec basename {} \; | sort)
fi
if [[ "${#subjects[@]}" -eq 0 ]]; then
  echo "ERROR: no fMRIPrep subject directories found." >&2
  exit 2
fi

if [[ -n "${MSMALL_ELIGIBILITY_CSV:-}" && -f "$MSMALL_ELIGIBILITY_CSV" ]]; then
  eligible_subjects="$(awk -F, 'NR == 1 {for (i=1; i<=NF; i++) {if ($i=="subject") s=i; if ($i=="eligible") e=i}} NR > 1 && s && e && tolower($e) ~ /^(1|true|yes|pass|eligible)$/ {print $s}' "$MSMALL_ELIGIBILITY_CSV")"
else
  eligible_subjects=""
fi

is_eligible() {
  local subject="$1"
  if [[ -z "$eligible_subjects" ]]; then
    return 0
  fi
  grep -qx "${subject}" <<< "$eligible_subjects"
}

apptainer_no_mount_args=()
if [[ -n "${APPTAINER_NO_MOUNT:-bind-paths}" ]]; then
  apptainer_no_mount_args=(--no-mount "${APPTAINER_NO_MOUNT:-bind-paths}")
fi

export APPTAINER_BINDPATH=""
export SINGULARITY_BINDPATH=""
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
export LD_PRELOAD="${LD_PRELOAD:-}"

timestamp="$(date +%Y%m%d_%H%M%S)"
log_label="$(echo "${MSMALL_PARTICIPANT_LABELS:-all_subjects}" | tr ' /' '__')"
array_label="${SLURM_ARRAY_TASK_ID:-manual}"
command_log="${LOG_DIR}/msmall_command_${log_label}_${array_label}_${timestamp}.txt"
run_log="${LOG_DIR}/msmall_run_${log_label}_${array_label}_${timestamp}.log"

{
  echo "CONFIG_ENV=$CONFIG_ENV"
  echo "MSMALL_IMAGE=$MSMALL_IMAGE"
  echo "MSMALL_DRIVER_SCRIPT=$MSMALL_DRIVER_SCRIPT"
  echo "MSMALL_ELIGIBILITY_CSV=${MSMALL_ELIGIBILITY_CSV:-}"
  echo "MSMALL_PARTICIPANT_LABELS=$MSMALL_PARTICIPANT_LABELS"
} > "$command_log"

run_one_subject() {
  local subject="$1"
  subject="${subject#sub-}"
  subject="sub-${subject}"
  if ! is_eligible "$subject"; then
    echo "Skipping $subject: not eligible according to $MSMALL_ELIGIBILITY_CSV"
    return 0
  fi

  local subject_out="${MSMALL_OUT}/${subject}"
  local subject_work="${MSMALL_WORK}/${subject}"
  mkdir -p "$subject_out" "$subject_work"

  local driver_args=("$subject" /data /fmriprep /freesurfer "/out/${subject}" /work)
  local hcp_bind_args=()
  if [[ -n "${MSMALL_HCP_STUDY_FOLDER:-}" ]]; then
    if [[ ! -d "$MSMALL_HCP_STUDY_FOLDER" ]]; then
      echo "ERROR: MSMALL_HCP_STUDY_FOLDER does not exist: $MSMALL_HCP_STUDY_FOLDER" >&2
      return 2
    fi
    driver_args+=(--hcp-source-folder /hcp_input --hcp-study-folder /work/hcp)
    case "$CONTAINER_RUNTIME" in
      docker) hcp_bind_args=(-v "${MSMALL_HCP_STUDY_FOLDER}:/hcp_input:ro") ;;
      apptainer|singularity) hcp_bind_args=(-B "${MSMALL_HCP_STUDY_FOLDER}:/hcp_input:ro") ;;
    esac
  fi
  if [[ -n "${EXTRA_MSMALL_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    extra_args=($EXTRA_MSMALL_ARGS)
    driver_args+=("${extra_args[@]}")
  fi
  {
    printf 'msmall driver args for %s:' "$subject"
    printf ' %q' "${driver_args[@]}"
    echo
  } >> "$command_log"

  case "$CONTAINER_RUNTIME" in
    docker)
      docker run --rm \
        -v "${BIDS_DIR}:/data:ro" \
        -v "${FMRIPREP_OUT}:/fmriprep:ro" \
        -v "${FS_SUBJECTS_DIR}:/freesurfer:ro" \
        -v "${subject_out}:/out/${subject}" \
        -v "${subject_work}:/work" \
        -v "${MSMALL_DRIVER_SCRIPT}:/driver.sh:ro" \
        "${hcp_bind_args[@]}" \
        "$MSMALL_IMAGE" \
        /driver.sh "${driver_args[@]}"
      ;;
    apptainer)
      apptainer exec --cleanenv \
        "${apptainer_no_mount_args[@]}" \
        -B "${BIDS_DIR}:/data:ro" \
        -B "${FMRIPREP_OUT}:/fmriprep:ro" \
        -B "${FS_SUBJECTS_DIR}:/freesurfer:ro" \
        -B "${subject_out}:/out/${subject}" \
        -B "${subject_work}:/work" \
        -B "${MSMALL_DRIVER_SCRIPT}:/driver.sh:ro" \
        "${hcp_bind_args[@]}" \
        "$MSMALL_IMAGE" \
        /driver.sh "${driver_args[@]}"
      ;;
    singularity)
      singularity exec --cleanenv \
        "${apptainer_no_mount_args[@]}" \
        -B "${BIDS_DIR}:/data:ro" \
        -B "${FMRIPREP_OUT}:/fmriprep:ro" \
        -B "${FS_SUBJECTS_DIR}:/freesurfer:ro" \
        -B "${subject_out}:/out/${subject}" \
        -B "${subject_work}:/work" \
        -B "${MSMALL_DRIVER_SCRIPT}:/driver.sh:ro" \
        "${hcp_bind_args[@]}" \
        "$MSMALL_IMAGE" \
        /driver.sh "${driver_args[@]}"
      ;;
    *)
      echo "ERROR: Unsupported CONTAINER_RUNTIME: $CONTAINER_RUNTIME" >&2
      return 2
      ;;
  esac
}

for subject in "${subjects[@]}"; do
  run_one_subject "$subject"
done 2>&1 | tee "$run_log"

echo "Command record: $command_log"
echo "Run log: $run_log"
