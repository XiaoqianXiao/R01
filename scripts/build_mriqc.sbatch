#!/usr/bin/env bash
#SBATCH --job-name=mriqc_build
#SBATCH --account=fang
#SBATCH --partition=ckpt-all
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=03:00:00
#SBATCH --output=mriqc_build_%j.out
#SBATCH --error=mriqc_build_%j.err

set -euo pipefail

MRIQC_VERSION="${MRIQC_VERSION:-24.0.2}"
CONTAINER_DIR="${CONTAINER_DIR:-/gscratch/fang/images}"
CONTAINER="${CONTAINER_DIR}/mriqc-${MRIQC_VERSION}.sif"

mkdir -p "$CONTAINER_DIR"

module purge
module load apptainer

echo "Apptainer:"
apptainer --version

export APPTAINER_CACHEDIR="/scr/${USER}/apptainer_cache"
export APPTAINER_TMPDIR="/scr/${USER}/apptainer_tmp"
mkdir -p "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR"

echo "============================================================"
echo "Building MRIQC ${MRIQC_VERSION} Apptainer image"
echo "Source: docker://nipreps/mriqc:${MRIQC_VERSION}"
echo "Output: ${CONTAINER}"
echo "============================================================"

apptainer pull \
  "$CONTAINER" \
  "docker://nipreps/mriqc:${MRIQC_VERSION}"

echo
echo "Checking MRIQC version..."
apptainer run "$CONTAINER" --version

echo
echo "Computing SHA256..."
sha256sum "$CONTAINER" > "${CONTAINER}.sha256"
apptainer inspect "$CONTAINER" > "${CONTAINER}.inspect.txt"

echo
echo "============================================================"
echo "DONE"
echo "Container:"
echo "$CONTAINER"
echo
echo "Checksum:"
cat "${CONTAINER}.sha256"
echo "============================================================"
