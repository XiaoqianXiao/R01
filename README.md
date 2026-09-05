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
│   ├── submit_fmriprep_array_hyak.sh
│   ├── submit_fmriprep_hyak.sbatch
│   ├── run_preproduction_pilot.sh
│   ├── run_fmriprep.sh
│   ├── run_python_hyak.sh
│   ├── run_bids_validator.sh
│   ├── make_multisession_manifest.py
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
- `PYTHON_CONTAINER_IMAGE`, usually `/gscratch/fang/images/jupyter.sif`
- `HYAK_ARRAY_CONCURRENCY`
- `PARTICIPANT_LABELS`, only for manual/non-array runs
- `NTHREADS`, `OMP_NTHREADS`, and `MEM_MB`

The default example is set for Hyak-style execution with:

```bash
CONTAINER_RUNTIME="apptainer"
FMRIPREP_IMAGE="/gscratch/fang/images/fmriprep-25.2.5.sif"
PYTHON_CONTAINER_IMAGE="/gscratch/fang/images/jupyter.sif"
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

After the pilot and manual QC are accepted, run all subjects in parallel with a SLURM job array:

```bash
scripts/submit_fmriprep_array_hyak.sh config/mri_preproc.env
```

This creates a subject list from:

```bash
/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/sourcedata/nii/sub-*
```

and submits:

```bash
one SLURM array task = one subject
```

Because all participants have multiple sessions, the array is deliberately **subject-level**, not session-level. Each task passes one `--participant-label` to fMRIPrep and keeps all of that participant's sessions visible, so `--subject-anatomical-reference unbiased` can build the shared within-subject anatomical reference. Do not add `--session-label` for the canonical release.

Control the maximum number of simultaneous subject jobs in `config/mri_preproc.env`:

```bash
HYAK_ARRAY_CONCURRENCY="10"
```

To run one non-array fMRIPrep job manually:

```bash
sbatch scripts/submit_fmriprep_hyak.sbatch config/mri_preproc.env
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

The scripts also archive a multi-session manifest recording the subject/session rows found under `BIDS_DIR`. This documents the sessions available for the common-reference workflow.

The FreeSurfer subjects directory is stored separately at:

```bash
${DERIVATIVES_DIR}/freesurfer
```

## Manual Helper Commands

Run only the SDC metadata audit:

```bash
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/audit_sdc_metadata.py "${BIDS_DIR}" \
  --output "${LOG_DIR}/sdc_metadata_audit.csv"
```

Run only output checks after fMRIPrep:

```bash
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/check_fmriprep_outputs.py \
  --fmriprep-dir "${FMRIPREP_OUT}" \
  --freesurfer-dir "${FS_SUBJECTS_DIR}" \
  --output "${LOG_DIR}/fmriprep_output_check.csv"
```

Generate a release manifest:

```bash
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/freeze_release_manifest.py \
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
