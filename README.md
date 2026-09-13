# R01 MRI Preprocessing Runbook

This repository contains the operational scripts for the R01/IFOCUS MRI
preprocessing workflow. Cohort-scale processing is designed to run on Hyak with
SLURM and Apptainer/Singularity.

The workflow is managed as a gated release process: configure the environment,
build/cache frozen software, validate raw data, run MRIQC, pilot fMRIPrep, run
canonical fMRIPrep production, freeze provenance, then run optional derivative
branches only after branch-specific prerequisites and QC gates are met.

The scientific specification is maintained in `plans/`. This README is the
short operational overview. Use `scripts/README_MRI_PREPROCESSING.md` as the
detailed runbook, and use `scripts/README_MSMALL_PIPELINE.md` for the HCP
structural/functional/MSMAll branch.

## Repository Layout

```text
R01/
├── config/
│   └── mri_preproc.env.example
├── scripts/
│   ├── build_fmriprep.sbatch
│   ├── build_mriqc.sbatch
│   ├── build_hcp_pipelines.sbatch
│   ├── build_hippunfold.sbatch
│   ├── prefetch_templateflow_hyak.sh
│   ├── prefetch_hippunfold_models_hyak.sh
│   ├── run_bids_validator.sh
│   ├── run_mriqc.sh
│   ├── run_fmriprep.sh
│   ├── run_hippunfold.sh
│   ├── run_first.sh
│   ├── run_hcp_structural.sh
│   ├── run_hcp_functional.sh
│   ├── run_msmall.sh
│   ├── submit_*_array_hyak.sh
│   ├── submit_*_hyak.sbatch
│   ├── audit_sdc_metadata.py
│   ├── check_fmriprep_outputs.py
│   ├── freeze_release_manifest.py
│   ├── README_MRI_PREPROCESSING.md
│   └── README_MSMALL_PIPELINE.md
└── README.md
```

## Workflow At A Glance

| Phase | Purpose | Main command(s) | Move on when |
|---|---|---|---|
| 0. Configure | Create the project env file and verify Hyak paths/resources. | `cp config/mri_preproc.env.example config/mri_preproc.env` | Paths, image locations, `FS_LICENSE`, resources, and concurrency are reviewed. |
| 1. Build/cache | Prepare frozen containers and offline resources. | `sbatch scripts/build_mriqc.sbatch`; `sbatch scripts/build_fmriprep.sbatch`; `scripts/prefetch_templateflow_hyak.sh config/mri_preproc.env` | Required images, checksums, TemplateFlow cache, and branch caches exist. |
| 2. Raw preflight | Validate BIDS and AP/PA SDC metadata. | `scripts/run_bids_validator.sh config/mri_preproc.env`; `scripts/run_python_hyak.sh ... audit_sdc_metadata.py` | No unresolved raw-data errors block preprocessing. |
| 3. MRIQC | Generate participant and group raw-image QC outputs. | `scripts/submit_mriqc_array_hyak.sh config/mri_preproc.env`; `sbatch scripts/submit_mriqc_group_hyak.sbatch config/mri_preproc.env` | MRIQC reports/IQM tables are ready for reviewer decisions. |
| 4. Pilot | Run a representative fMRIPrep pilot. | `sbatch scripts/submit_preproduction_pilot_hyak.sbatch config/mri_preproc.env` | Pilot QC accepts settings, SDC behavior, outputs, and resource profile. |
| 5. Canonical production | Run frozen fMRIPrep for the cohort. | `scripts/submit_fmriprep_array_hyak.sh config/mri_preproc.env` | Every intended subject is complete or explicitly documented. |
| 6. Closeout | Check expected outputs and freeze provenance. | `scripts/run_python_hyak.sh ... check_fmriprep_outputs.py`; `scripts/run_python_hyak.sh ... freeze_release_manifest.py` | Logs, commands, config, checksums, and output checks are archived. |
| 7. Optional branches | Run branch derivatives after eligibility/QC gates. | HippUnfold, FIRST, and the HCP MSMAll branch commands below. | Branch outputs and branch-specific QC statuses are recorded. |

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
- `MRIQC_IMAGE`
- `TEMPLATEFLOW_HOME`, usually `/gscratch/fang/templateflow`
- `PYTHON_CONTAINER_IMAGE`, usually `/gscratch/fang/images/jupyter.sif`
- `HYAK_ARRAY_CONCURRENCY`
- `PARTICIPANT_LABELS`, only for manual/non-array runs
- `NTHREADS`, `OMP_NTHREADS`, and `MEM_MB`

The default example is set for Hyak-style execution with:

```bash
CONTAINER_RUNTIME="apptainer"
FMRIPREP_IMAGE="/gscratch/fang/images/fmriprep-25.2.5.sif"
MRIQC_IMAGE="/gscratch/fang/images/mriqc-24.0.2.sif"
TEMPLATEFLOW_HOME="/gscratch/fang/templateflow"
PYTHON_CONTAINER_IMAGE="/gscratch/fang/images/jupyter.sif"
PYTHON_CONTAINER_PYTHON="python3"
APPTAINER_NO_MOUNT="bind-paths"
FS_LICENSE="/mmfs1/home/xxqian/files/fs_license.txt"
HYAK_ACCOUNT="fang"
HYAK_PARTITION="ckpt-all"
```

## Build Containers And Caches

If the frozen Apptainer images are not already available on Hyak, build them
before production:

```bash
sbatch scripts/build_mriqc.sbatch
sbatch scripts/build_fmriprep.sbatch
sbatch scripts/build_hippunfold.sbatch
sbatch scripts/build_hcp_pipelines.sbatch
```

Populate shared caches before compute-node array jobs:

```bash
scripts/prefetch_templateflow_hyak.sh config/mri_preproc.env
scripts/prefetch_hippunfold_models_hyak.sh config/mri_preproc.env
```

The TemplateFlow cache is required before fMRIPrep production. The HippUnfold
cache is required before the HippUnfold branch.

## Raw Data And MRIQC Gates

Run BIDS validation and the AP/PA fieldmap metadata audit before production:

```bash
source config/mri_preproc.env
scripts/run_bids_validator.sh config/mri_preproc.env
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/audit_sdc_metadata.py "${BIDS_DIR}" \
  --output "${LOG_DIR}/sdc_metadata_audit.csv"
```

Run MRIQC participant level as one subject/session per array task, selecting
only sessions with missing outputs:

```bash
scripts/submit_mriqc_array_hyak.sh config/mri_preproc.env
```

The current config scans `BIDS_DIR=/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/sourcedata/nii`
and checks `MRIQC_OUT=/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/derivatives/qc/mriqc`.
A session is complete when every input image selected by `MRIQC_MODALITIES`
(default: `T1w T2w bold`) has a nonempty IQM JSON and HTML report. Sessions with
missing or empty outputs are submitted, including partially completed sessions;
completed sessions and sessions without matching images are skipped. If nothing
is pending, the script exits successfully without submitting jobs.

Each invocation writes a pending-session list and a session status TSV under
`MRIQC_LOG_DIR` (default: `${PROJECT_DIR}/logs/mriqc`). After jobs finish, rerun
the same command to select any sessions still missing outputs. See the
[MRI preprocessing guide](scripts/README_MRI_PREPROCESSING.md) for manifest details.

After participant-level jobs complete, generate group reports and IQM tables:

```bash
sbatch scripts/submit_mriqc_group_hyak.sbatch config/mri_preproc.env
```

## Run The fMRIPrep Pilot

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

Control the maximum number of simultaneous subject jobs in
`config/mri_preproc.env`:

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

On Hyak, `APPTAINER_NO_MOUNT="bind-paths"` prevents Apptainer from trying to
auto-mount unavailable site paths such as `/var/run/slurm`; the scripts provide
the needed project mounts explicitly.

Use a real shared TemplateFlow cache for production, normally:

```bash
TEMPLATEFLOW_HOME="/gscratch/fang/templateflow"
```

The FreeSurfer subjects directory is stored separately at:

```bash
${DERIVATIVES_DIR}/freesurfer
```

## Manual Helper Commands

Run only the SDC metadata audit:

```bash
source config/mri_preproc.env
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/audit_sdc_metadata.py "${BIDS_DIR}" \
  --output "${LOG_DIR}/sdc_metadata_audit.csv"
```

Run only output checks after fMRIPrep:

```bash
source config/mri_preproc.env
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/check_fmriprep_outputs.py \
  --fmriprep-dir "${FMRIPREP_OUT}" \
  --freesurfer-dir "${FS_SUBJECTS_DIR}" \
  --output "${LOG_DIR}/fmriprep_output_check.csv"
```

Generate a release manifest:

```bash
source config/mri_preproc.env
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/freeze_release_manifest.py \
  --config config/mri_preproc.env \
  --output "${PROVENANCE_DIR}/release_manifest.json"
```

## Optional Derivative Branches

Run optional branches only after the canonical inputs and branch-specific QC
plans are ready.

HippUnfold reads raw BIDS and requires the HippUnfold model/resource cache:

```bash
scripts/prefetch_hippunfold_models_hyak.sh config/mri_preproc.env
scripts/submit_hippunfold_array_hyak.sh config/mri_preproc.env
```

FIRST reads completed fMRIPrep anatomical outputs:

```bash
scripts/submit_first_array_hyak.sh config/mri_preproc.env
```

MSMAll is a three-stage HCP branch, not a direct fMRIPrep postprocess:

```bash
scripts/submit_hcp_structural_array_hyak.sh config/mri_preproc.env

# After structural completion and QC:
scripts/submit_hcp_functional_array_hyak.sh config/mri_preproc.env

# After functional/FIX completion and QC:
scripts/submit_msmall_array_hyak.sh config/mri_preproc.env
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

Denoising, atlas extraction, connectivity, task GLM, MVPA, HippUnfold, FIRST,
and MSMAll production are separate derivative branches and are not run by the
canonical fMRIPrep scripts.

More detailed operational notes are in `scripts/README_MRI_PREPROCESSING.md`.
