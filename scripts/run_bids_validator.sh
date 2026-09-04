#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/run_bids_validator.sh CONFIG_ENV

Runs the BIDS validator before fMRIPrep production.
Requires Docker, Apptainer, Singularity, or a local bids-validator command.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
  usage
  exit 0
fi

CONFIG_ENV="$1"
# shellcheck source=/dev/null
source "$CONFIG_ENV"

mkdir -p "$LOG_DIR"
REPORT="${LOG_DIR}/bids-validator_$(date +%Y%m%d_%H%M%S).log"

if command -v bids-validator >/dev/null 2>&1; then
  bids-validator "$BIDS_DIR" | tee "$REPORT"
elif command -v docker >/dev/null 2>&1; then
  docker run --rm -v "${BIDS_DIR}:/data:ro" bids/validator /data | tee "$REPORT"
elif command -v apptainer >/dev/null 2>&1; then
  apptainer run docker://bids/validator "$BIDS_DIR" | tee "$REPORT"
elif command -v singularity >/dev/null 2>&1; then
  singularity run docker://bids/validator "$BIDS_DIR" | tee "$REPORT"
else
  echo "ERROR: No BIDS validator command or supported container runtime found." >&2
  exit 127
fi

echo "BIDS validator report: $REPORT"
