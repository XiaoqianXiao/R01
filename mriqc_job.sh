#!/bin/bash
   #SBATCH --job-name=mriqc_all
   #SBATCH --account=fang
   #SBATCH --partition=cpu-g2
   #SBATCH --qos=normal
   #SBATCH --ntasks=2
   #SBATCH --mem=40G
   #SBATCH --time=12:00:00
   #SBATCH --output=mriqc_all_%j.out
   #SBATCH --error=mriqc_all_%j.err

module load apptainer

# Dynamically get all subject IDs from /gscratch/fang/IFOCUS
SUBJECTS=$(find /gscratch/fang/IFOCUS -maxdepth 1 -type d -name "sub-*" -exec basename {} \; | sed 's/sub-//g' | sort | tr '\n' ' ')

apptainer run \
  --cleanenv \
  -B /gscratch/fang/IFOCUS:/data:ro \
  -B /gscratch/fang/IFOCUS/derivatives/mriqc:/out \
  -B /gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/mriqc_work:/work \
  /gscratch/scrubbed/fanglab/xiaoqian/images/mriqc_24.0.2.sif \
  /data /out participant \
  #--participant-label ${SUBJECTS} \
  --participant-label 102 \
  --work-dir /work \
  --verbose-reports \
  --no-sub