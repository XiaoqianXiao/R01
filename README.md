# R01 MRI Preprocessing Scripts

This repository contains the operational scripts for the R01 MRI preprocessing workflow. The preprocessing is designed to run on Hyak with SLURM and Apptainer/Singularity.

The scientific specification is maintained separately in the ignored `plans/` folder. The scripts in this repository implement the canonical fMRIPrep production workflow and supporting pre-production checks.

## Repository Layout

```text
R01/
├── config/
│   └── mri_preproc.env.example
├── scripts/
│   ├── build_fmriprep.sbatch
│   ├── submit_preproduction_pilot_hyak.sbatch
│   ├── submit_fmriprep_hyak.sbatch
│   ├── run_preproduction_pilot.sh
│   ├── run_fmriprep.sh
│   ├── run_bids_validator.sh
│   ├── audit_sdc_metadata.py
│   ├── check_fmriprep_outputs.py
│   ├── freeze_release_manifest.py
│   └── README_MRI_PREPROCESSING.md
└── README.md
```

## Hyak Setup

Log into Hyak and work from the repository root:

```bash
cd /path/to/R01
cp config/mri_preproc.env.example config/mri_preproc.env
```

Edit `config/mri_preproc.env` before running jobs. The default paths are set for the IFOCUS Hyak project:

```bash
PROJECT_DIR="/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS"
BIDS_DIR="/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/sourcedata/nii"
FMRIPREP_OUT="/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/derivatives/fmriprep"
FS_LICENSE="/mmfs1/home/xxqian/files/fs_license.txt"
```

At minimum, verify:

- `PROJECT_DIR`
- `BIDS_DIR`
- `FMRIPREP_OUT`
- `FS_LICENSE`, usually `/mmfs1/home/xxqian/files/fs_license.txt`
- `FMRIPREP_IMAGE`
- `PARTICIPANT_LABELS`; leave it empty to run all subjects
- `NTHREADS`, `OMP_NTHREADS`, and `MEM_MB`

The default example is set for Hyak-style execution with:

```bash
CONTAINER_RUNTIME="apptainer"
FMRIPREP_IMAGE="/gscratch/fang/images/fmriprep-25.2.5.sif"
FS_LICENSE="/mmfs1/home/xxqian/files/fs_license.txt"
HYAK_ACCOUNT="fang"
HYAK_PARTITION="ckpt-all"
```

## Build the fMRIPrep Container

If the fMRIPrep Apptainer image is not already available on Hyak, build it with:

```bash
sbatch scripts/build_fmriprep.sbatch
```

This creates the fMRIPrep `25.2.5` image and records checksum/metadata in `/gscratch/fang/images`.

## Run the Pre-Production Pilot

For a pre-production pilot, set `PARTICIPANT_LABELS` in `config/mri_preproc.env` to a representative sample, then submit:

```bash
sbatch scripts/submit_preproduction_pilot_hyak.sbatch config/mri_preproc.env
```

The pilot wrapper runs:

- BIDS validation
- AP/PA SDC metadata audit
- canonical fMRIPrep pilot run
- expected-output checks
- provenance manifest generation

## Run Canonical fMRIPrep

After the pilot and manual QC are accepted, run all subjects by leaving `PARTICIPANT_LABELS` empty:

```bash
PARTICIPANT_LABELS=""
```

Then submit the canonical fMRIPrep job:

```bash
sbatch scripts/submit_fmriprep_hyak.sbatch config/mri_preproc.env
```

To request more resources:

```bash
sbatch --cpus-per-task=24 --mem=96G --time=72:00:00 \
  scripts/submit_fmriprep_hyak.sbatch config/mri_preproc.env
```

## Canonical fMRIPrep Settings

The launcher runs the frozen baseline from the preprocessing plan:

```bash
--subject-anatomical-reference unbiased
--track-sessions
--output-spaces func T1w MNI152NLin2009cAsym:res-native fsnative
--cifti-output 91k
--msm
--slice-time-ref 0.5
--random-seed 20260904
```

The FreeSurfer subjects directory is stored separately at:

```bash
${DERIVATIVES_DIR}/freesurfer
```

## Manual Helper Commands

Run only the SDC metadata audit:

```bash
python scripts/audit_sdc_metadata.py "${BIDS_DIR}" --output "${LOG_DIR}/sdc_metadata_audit.csv"
```

Run only output checks after fMRIPrep:

```bash
python scripts/check_fmriprep_outputs.py \
  --fmriprep-dir "${FMRIPREP_OUT}" \
  --freesurfer-dir "${FS_SUBJECTS_DIR}" \
  --output "${LOG_DIR}/fmriprep_output_check.csv"
```

Generate a release manifest:

```bash
python scripts/freeze_release_manifest.py \
  --config config/mri_preproc.env \
  --output "${PROVENANCE_DIR}/release_manifest.json"
```

## Outputs

The canonical preprocessing release preserves:

- corrected native functional-grid BOLD
- T1w-space BOLD
- MNI152NLin2009cAsym `res-native` BOLD
- fsnative cortical outputs
- CIFTI 91k
- confounds, masks, transforms, logs, HTML reports
- full FreeSurfer reconstruction
- provenance records and QC reports

Denoising, atlas extraction, connectivity, task GLM, MVPA, HippUnfold, FIRST, and MSMAll production are separate derivative branches and are not run by the canonical fMRIPrep scripts.

More detailed operational notes are in `scripts/README_MRI_PREPROCESSING.md`.
