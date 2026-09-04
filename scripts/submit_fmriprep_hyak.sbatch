#!/usr/bin/env bash
#SBATCH --job-name=r01-fmriprep
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=48:00:00
#SBATCH --output=logs/slurm/fmriprep_%A_%a.out
#SBATCH --error=logs/slurm/fmriprep_%A_%a.err

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  sbatch [SLURM_OPTIONS] scripts/submit_fmriprep_hyak.sbatch CONFIG_ENV

Examples:
  sbatch -A MY_ALLOCATION scripts/submit_fmriprep_hyak.sbatch config/mri_preproc.env
  sbatch -A MY_ALLOCATION --cpus-per-task=24 --mem=96G scripts/submit_fmriprep_hyak.sbatch config/mri_preproc.env

This submits the canonical fMRIPrep worker to Hyak. Edit CONFIG_ENV first.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
  usage
  exit 0
fi

CONFIG_ENV="$1"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

# shellcheck source=/dev/null
source "$CONFIG_ENV"

mkdir -p logs/slurm "$LOG_DIR" "$WORK_DIR" "$FMRIPREP_OUT" "$FS_SUBJECTS_DIR"

export OMP_NUM_THREADS="${OMP_NTHREADS}"
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${OMP_NTHREADS}"

if command -v module >/dev/null 2>&1; then
  module purge || true
  module load apptainer || module load singularity || true
fi

if ! command -v apptainer >/dev/null 2>&1 && ! command -v singularity >/dev/null 2>&1; then
  echo "ERROR: Apptainer/Singularity is not available on this Hyak node." >&2
  exit 127
fi

if [[ "$CONTAINER_RUNTIME" == "docker" ]]; then
  echo "ERROR: Docker is not appropriate for Hyak jobs. Set CONTAINER_RUNTIME=apptainer or singularity." >&2
  exit 2
fi

echo "Running on host: $(hostname)"
echo "SLURM_JOB_ID=${SLURM_JOB_ID:-NA}"
echo "SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK:-NA}"
echo "CONFIG_ENV=$CONFIG_ENV"

"${REPO_DIR}/scripts/run_fmriprep.sh" "$CONFIG_ENV"
