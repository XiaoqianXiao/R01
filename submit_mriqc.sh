#!/bin/bash

# Calculate number of subjects
SUBJECTS=($(find /gscratch/fang/IFOCUS -maxdepth 1 -type d -name "sub-*" -exec basename {} \; | sed 's/sub-//g' | sort))
N=$((${#SUBJECTS[@]} - 1))

if [ $N -lt 0 ]; then
  echo "Error: No subjects found in /gscratch/fang/IFOCUS"
  exit 1
fi

echo "Submitting jobs for $((N + 1)) subjects: ${SUBJECTS[@]}"

# Submit the job with dynamic array
sbatch --array=0-$N mriqc_job.sh