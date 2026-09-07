#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'MSG'
ERROR: MSMAll requires a project-specific HCP-Pipelines bridge.

Create an executable driver script and set MSMALL_DRIVER_SCRIPT in config.
The driver is called inside the HCP container as:

  /driver.sh SUBJECT /data /fmriprep /freesurfer /out /work [EXTRA_MSMALL_ARGS...]

It should implement the frozen fMRIPrep-to-HCP/MSMAll ingestion, cleaning/FIX,
feature generation, MSMAll registration, QC, and provenance policy accepted for
this project.
MSG
exit 2
