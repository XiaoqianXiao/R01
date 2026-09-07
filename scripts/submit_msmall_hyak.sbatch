#!/usr/bin/env bash
#SBATCH --job-name=r01-msmall
#SBATCH --account=fang
#SBATCH --partition=ckpt-all
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=48:00:00
#SBATCH --output=logs/slurm/msmall_%A_%a.out
#SBATCH --error=logs/slurm/msmall_%A_%a.err

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: sbatch [SLURM_OPTIONS] scripts/submit_msmall_hyak.sbatch CONFIG_ENV [SUBJECT_LIST]"
  exit 0
fi

CONFIG_ENV="$1"
SUBJECT_LIST="${2:-}"
REPO_DIR="${SLURM_SUBMIT_DIR:-$(pwd)}"
cd "$REPO_DIR"

if [[ "$CONFIG_ENV" != /* ]]; then
  CONFIG_ENV="${REPO_DIR}/${CONFIG_ENV}"
fi
if [[ -n "$SUBJECT_LIST" && "$SUBJECT_LIST" != /* ]]; then
  SUBJECT_LIST="${REPO_DIR}/${SUBJECT_LIST}"
fi

# shellcheck source=/dev/null
source "$CONFIG_ENV"
mkdir -p logs/slurm "$LOG_DIR" "$PROVENANCE_DIR" "${MSMALL_OUT:-${DERIVATIVES_DIR}/msmall}" "${MSMALL_WORK:-${PROJECT_DIR}/scratch/msmall_work}"

if [[ -n "$SUBJECT_LIST" ]]; then
  if [[ -z "${SLURM_ARRAY_TASK_ID:-}" ]]; then
    echo "ERROR: SUBJECT_LIST was provided, but SLURM_ARRAY_TASK_ID is not set." >&2
    exit 2
  fi
  subject="$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" "$SUBJECT_LIST")"
  if [[ -z "$subject" ]]; then
    echo "ERROR: no subject found for array index ${SLURM_ARRAY_TASK_ID}" >&2
    exit 2
  fi
  export MSMALL_SINGLE_SUBJECT="$subject"
fi

export OMP_NUM_THREADS="${OMP_NTHREADS:-1}"
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${OMP_NTHREADS:-1}"

if command -v module >/dev/null 2>&1; then
  module purge || true
  module load apptainer || module load singularity || true
fi

echo "Running on host: $(hostname)"
echo "SLURM_JOB_ID=${SLURM_JOB_ID:-NA}"
echo "SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID:-NA}"
echo "CONFIG_ENV=$CONFIG_ENV"
echo "MSMALL_SINGLE_SUBJECT=${MSMALL_SINGLE_SUBJECT:-}"

"${REPO_DIR}/scripts/run_msmall.sh" "$CONFIG_ENV"
