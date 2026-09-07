#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  /driver.sh SUBJECT BIDS_DIR FMRIPREP_DIR FREESURFER_DIR OUT_DIR WORK_DIR [OPTIONS]

Runs HCP Pipelines MSMAll for one subject inside the HCP container.

Required positional arguments are supplied by scripts/run_msmall.sh:
  SUBJECT        BIDS-style subject label, e.g. sub-305
  BIDS_DIR       container path to raw BIDS input, usually /data
  FMRIPREP_DIR   container path to fMRIPrep derivatives, usually /fmriprep
  FREESURFER_DIR container path to FreeSurfer subjects, usually /freesurfer
  OUT_DIR        subject output directory bind, e.g. /out/sub-305
  WORK_DIR       subject work directory bind, usually /work

Options:
  --hcp-study-folder PATH
      HCP-style study folder containing SUBJECT/MNINonLinear. Default: WORK_DIR/hcp
  --hcp-source-folder PATH
      Optional read-only HCP-style study folder to copy SUBJECT from before
      running MSMAll. This should contain SUBJECT/MNINonLinear.
  --hcp-session ID
      HCP session/subject folder name. Default: SUBJECT without "sub-"
  --fmri-names-list LIST
      @-separated HCP single-run fMRI names. Default: empty, using multi-run FIX.
  --multirun-fix-names LIST
      @-separated runs in the multi-run FIX concatenation.
  --multirun-fix-concat-name NAME
      HCP multi-run FIX concatenated result name. Default: fMRI_CONCAT
  --multirun-fix-names-to-use LIST
      @-separated resting-state runs to use for MSMAll.
  --output-fmri-name NAME
      Name for MSMAll concatenated fMRI output. Default: rfMRI_REST_CONCAT
  --high-pass VALUE
      FIX high-pass value. Default: 0
  --fmri-proc-string STRING
      Existing HCP fMRI processing suffix. Default: _Atlas_hp0_clean
  --input-registration-name NAME
      Existing surface registration name. Default: MSMSulc
  --output-registration-name NAME
      MSMAll registration name stem. Default: MSMAll_InitialReg
  --high-res-mesh N
      HCP high-resolution mesh in thousands. Default: 164
  --low-res-mesh N
      HCP low-resolution mesh in thousands. Default: 32
  --matlab-run-mode N
      HCP MATLAB mode: 0 compiled, 1 MATLAB, 2 Octave. Default: 1
  --dry-run
      Print the MSMAll command and exit.

Important:
  This script does not convert fMRIPrep derivatives into HCP Minimal
  Preprocessing outputs. MSMAll expects HCP-style MNINonLinear/Native and
  MNINonLinear/Results inputs from the HCP pipelines, including myelin and
  FIX-cleaned dense timeseries products.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

need_path() {
  local label="$1"
  local path="$2"
  [[ -e "$path" ]] || die "$label does not exist: $path"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ $# -lt 6 ]]; then
  usage >&2
  exit 2
fi

SUBJECT="$1"
BIDS_DIR="$2"
FMRIPREP_DIR="$3"
FREESURFER_DIR="$4"
OUT_DIR="$5"
WORK_DIR="$6"
shift 6

SUBJECT_ID="${SUBJECT#sub-}"
HCP_SESSION="$SUBJECT_ID"
HCP_SESSION_SET="FALSE"
HCP_STUDY_FOLDER="${WORK_DIR}/hcp"
HCP_SOURCE_FOLDER=""
FMRINAMES=""
MRFIX_NAMES=""
MRFIX_CONCAT_NAME="fMRI_CONCAT"
MRFIX_NAMES_TO_USE=""
OUTPUT_FMRI_NAME="rfMRI_REST_CONCAT"
HIGH_PASS="0"
FMRI_PROC_STRING="_Atlas_hp0_clean"
INPUT_REG_NAME="MSMSulc"
OUTPUT_REG_NAME="MSMAll_InitialReg"
HIGH_RES_MESH="164"
LOW_RES_MESH="32"
MATLAB_RUN_MODE="1"
DRY_RUN="FALSE"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hcp-study-folder=*) HCP_STUDY_FOLDER="${1#*=}" ;;
    --hcp-study-folder) HCP_STUDY_FOLDER="${2:?missing value for --hcp-study-folder}"; shift ;;
    --hcp-source-folder=*) HCP_SOURCE_FOLDER="${1#*=}" ;;
    --hcp-source-folder) HCP_SOURCE_FOLDER="${2:?missing value for --hcp-source-folder}"; shift ;;
    --hcp-session=*) HCP_SESSION="${1#*=}"; HCP_SESSION_SET="TRUE" ;;
    --hcp-session) HCP_SESSION="${2:?missing value for --hcp-session}"; HCP_SESSION_SET="TRUE"; shift ;;
    --fmri-names-list=*) FMRINAMES="${1#*=}" ;;
    --fmri-names-list) FMRINAMES="${2:?missing value for --fmri-names-list}"; shift ;;
    --multirun-fix-names=*) MRFIX_NAMES="${1#*=}" ;;
    --multirun-fix-names) MRFIX_NAMES="${2:?missing value for --multirun-fix-names}"; shift ;;
    --multirun-fix-concat-name=*) MRFIX_CONCAT_NAME="${1#*=}" ;;
    --multirun-fix-concat-name) MRFIX_CONCAT_NAME="${2:?missing value for --multirun-fix-concat-name}"; shift ;;
    --multirun-fix-names-to-use=*) MRFIX_NAMES_TO_USE="${1#*=}" ;;
    --multirun-fix-names-to-use) MRFIX_NAMES_TO_USE="${2:?missing value for --multirun-fix-names-to-use}"; shift ;;
    --output-fmri-name=*) OUTPUT_FMRI_NAME="${1#*=}" ;;
    --output-fmri-name) OUTPUT_FMRI_NAME="${2:?missing value for --output-fmri-name}"; shift ;;
    --high-pass=*) HIGH_PASS="${1#*=}" ;;
    --high-pass) HIGH_PASS="${2:?missing value for --high-pass}"; shift ;;
    --fmri-proc-string=*) FMRI_PROC_STRING="${1#*=}" ;;
    --fmri-proc-string) FMRI_PROC_STRING="${2:?missing value for --fmri-proc-string}"; shift ;;
    --input-registration-name=*) INPUT_REG_NAME="${1#*=}" ;;
    --input-registration-name) INPUT_REG_NAME="${2:?missing value for --input-registration-name}"; shift ;;
    --output-registration-name=*) OUTPUT_REG_NAME="${1#*=}" ;;
    --output-registration-name) OUTPUT_REG_NAME="${2:?missing value for --output-registration-name}"; shift ;;
    --high-res-mesh=*) HIGH_RES_MESH="${1#*=}" ;;
    --high-res-mesh) HIGH_RES_MESH="${2:?missing value for --high-res-mesh}"; shift ;;
    --low-res-mesh=*) LOW_RES_MESH="${1#*=}" ;;
    --low-res-mesh) LOW_RES_MESH="${2:?missing value for --low-res-mesh}"; shift ;;
    --matlab-run-mode=*) MATLAB_RUN_MODE="${1#*=}" ;;
    --matlab-run-mode) MATLAB_RUN_MODE="${2:?missing value for --matlab-run-mode}"; shift ;;
    --dry-run) DRY_RUN="TRUE" ;;
    *) die "unrecognized MSMAll driver option: $1" ;;
  esac
  shift
done

need_path "BIDS_DIR" "$BIDS_DIR"
need_path "FMRIPREP_DIR" "$FMRIPREP_DIR"
need_path "FREESURFER_DIR" "$FREESURFER_DIR"
mkdir -p "$OUT_DIR" "$WORK_DIR"

if [[ -n "$HCP_SOURCE_FOLDER" ]]; then
  need_path "HCP_SOURCE_FOLDER" "$HCP_SOURCE_FOLDER"
  if [[ "$HCP_SESSION_SET" == "FALSE" && ! -e "${HCP_SOURCE_FOLDER}/${HCP_SESSION}" && -e "${HCP_SOURCE_FOLDER}/${SUBJECT}" ]]; then
    HCP_SESSION="$SUBJECT"
  fi
  need_path "HCP source subject folder" "${HCP_SOURCE_FOLDER}/${HCP_SESSION}"
  mkdir -p "$HCP_STUDY_FOLDER"
  if [[ ! -e "${HCP_STUDY_FOLDER}/${HCP_SESSION}" ]]; then
    cp -a "${HCP_SOURCE_FOLDER}/${HCP_SESSION}" "${HCP_STUDY_FOLDER}/${HCP_SESSION}"
  fi
elif [[ "$HCP_SESSION_SET" == "FALSE" && ! -e "${HCP_STUDY_FOLDER}/${HCP_SESSION}" && -e "${HCP_STUDY_FOLDER}/${SUBJECT}" ]]; then
  HCP_SESSION="$SUBJECT"
fi

if [[ -z "${HCPPIPEDIR:-}" ]]; then
  for candidate in \
    /pipeline_tools/HCPpipelines \
    /opt/HCPpipelines \
    /usr/local/HCPpipelines \
    /HCPpipelines; do
    if [[ -x "${candidate}/MSMAll/MSMAllPipeline.sh" ]]; then
      export HCPPIPEDIR="$candidate"
      break
    fi
  done
fi
[[ -n "${HCPPIPEDIR:-}" ]] || die "HCPPIPEDIR is not set and could not be discovered in the container"
[[ -x "${HCPPIPEDIR}/MSMAll/MSMAllPipeline.sh" ]] || die "MSMAllPipeline.sh is not executable under HCPPIPEDIR: $HCPPIPEDIR"

export HCPPIPEDIR_Global="${HCPPIPEDIR_Global:-${HCPPIPEDIR}/global/scripts}"
export HCPPIPEDIR_Config="${HCPPIPEDIR_Config:-${HCPPIPEDIR}/global/config}"
export HCPPIPEDIR_Templates="${HCPPIPEDIR_Templates:-${HCPPIPEDIR}/global/templates}"
export MSMCONFIGDIR="${MSMCONFIGDIR:-${HCPPIPEDIR}/MSMConfig}"

MSMALL_TEMPLATES="${MSMALL_TEMPLATES:-${HCPPIPEDIR}/global/templates/MSMAll}"
MYELIN_TARGET_FILE="${MYELIN_TARGET_FILE:-${MSMALL_TEMPLATES}/Q1-Q6_RelatedParcellation210.MyelinMap_BC_MSMAll_2_d41_WRN_DeDrift.32k_fs_LR.dscalar.nii}"

need_path "HCP_STUDY_FOLDER" "$HCP_STUDY_FOLDER"
need_path "HCP subject MNINonLinear folder" "${HCP_STUDY_FOLDER}/${HCP_SESSION}/MNINonLinear"
need_path "HCP subject native myelin map" "${HCP_STUDY_FOLDER}/${HCP_SESSION}/MNINonLinear/Native/${HCP_SESSION}.MyelinMap.native.dscalar.nii"
need_path "MSMAll templates" "$MSMALL_TEMPLATES"
need_path "MSMAll myelin target" "$MYELIN_TARGET_FILE"

if [[ -z "$FMRINAMES" ]]; then
  [[ -n "$MRFIX_NAMES" ]] || die "set --multirun-fix-names when --fmri-names-list is empty"
  [[ -n "$MRFIX_NAMES_TO_USE" ]] || die "set --multirun-fix-names-to-use when --fmri-names-list is empty"
  need_path "HCP multi-run FIX dtseries" "${HCP_STUDY_FOLDER}/${HCP_SESSION}/MNINonLinear/Results/${MRFIX_CONCAT_NAME}/${MRFIX_CONCAT_NAME}_Atlas_hp${HIGH_PASS}_clean.dtseries.nii"
  need_path "HCP multi-run FIX variance normalization scalar" "${HCP_STUDY_FOLDER}/${HCP_SESSION}/MNINonLinear/Results/${MRFIX_CONCAT_NAME}/${MRFIX_CONCAT_NAME}_Atlas_hp${HIGH_PASS}_clean_vn.dscalar.nii"
else
  IFS='@' read -r -a fmri_runs <<< "$FMRINAMES"
  for run_name in "${fmri_runs[@]}"; do
    need_path "HCP fMRI dtseries for ${run_name}" "${HCP_STUDY_FOLDER}/${HCP_SESSION}/MNINonLinear/Results/${run_name}/${run_name}${FMRI_PROC_STRING}.dtseries.nii"
  done
fi

command=(
  "${HCPPIPEDIR}/MSMAll/MSMAllPipeline.sh"
  --path="$HCP_STUDY_FOLDER"
  --subject="$HCP_SESSION"
  --fmri-names-list="$FMRINAMES"
  --multirun-fix-names="$MRFIX_NAMES"
  --multirun-fix-concat-name="$MRFIX_CONCAT_NAME"
  --multirun-fix-names-to-use="$MRFIX_NAMES_TO_USE"
  --output-fmri-name="$OUTPUT_FMRI_NAME"
  --high-pass="$HIGH_PASS"
  --fmri-proc-string="$FMRI_PROC_STRING"
  --msm-all-templates="$MSMALL_TEMPLATES"
  --myelin-target-file="$MYELIN_TARGET_FILE"
  --output-registration-name="$OUTPUT_REG_NAME"
  --high-res-mesh="$HIGH_RES_MESH"
  --low-res-mesh="$LOW_RES_MESH"
  --input-registration-name="$INPUT_REG_NAME"
  --matlab-run-mode="$MATLAB_RUN_MODE"
)

{
  echo "SUBJECT=$SUBJECT"
  echo "HCP_SESSION=$HCP_SESSION"
  echo "HCP_STUDY_FOLDER=$HCP_STUDY_FOLDER"
  echo "HCP_SOURCE_FOLDER=$HCP_SOURCE_FOLDER"
  echo "HCPPIPEDIR=$HCPPIPEDIR"
  echo "FMRINAMES=$FMRINAMES"
  echo "MRFIX_NAMES=$MRFIX_NAMES"
  echo "MRFIX_CONCAT_NAME=$MRFIX_CONCAT_NAME"
  echo "MRFIX_NAMES_TO_USE=$MRFIX_NAMES_TO_USE"
  printf 'COMMAND:'
  printf ' %q' "${command[@]}"
  echo
} | tee "${OUT_DIR}/msmall_driver_command.txt"

if [[ "$DRY_RUN" == "TRUE" ]]; then
  echo "Dry run requested; not launching MSMAll."
  exit 0
fi

"${command[@]}"

cp -a "${HCP_STUDY_FOLDER}/${HCP_SESSION}/MNINonLinear" "${OUT_DIR}/" 2>/dev/null || true
echo "MSMAll complete for ${SUBJECT}"
