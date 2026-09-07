# HCP MSMAll Pipeline Runbook

This runbook describes how to run the HCP Pipelines MSMAll derivative branch on
Hyak for the R01/IFOCUS project.

MSMAll is not generated directly from fMRIPrep. It requires HCP-style structural
and functional outputs, including `SUBJECT/MNINonLinear`, native myelin maps,
surface fMRI outputs, and multi-run FIX-cleaned dense time series. The scripts
therefore run in three stages:

1. HCP structural preprocessing
2. HCP functional preprocessing plus multi-run ICA-FIX
3. MSMAll registration

## Scripts

- `scripts/build_hcp_pipelines.sbatch`: builds the HCP Pipelines 5.0.0
  Apptainer image used by all three stages.
- `scripts/run_hcp_structural.sh`: runs PreFreeSurfer, FreeSurfer, and
  PostFreeSurfer for one or more subjects.
- `scripts/submit_hcp_structural_array_hyak.sh`: submits one HCP structural
  SLURM array task per BIDS subject.
- `scripts/submit_hcp_structural_hyak.sbatch`: worker used by the structural
  array.
- `scripts/run_hcp_functional.sh`: runs GenericfMRIVolume,
  GenericfMRISurface, and multi-run ICA-FIX.
- `scripts/submit_hcp_functional_array_hyak.sh`: submits one HCP functional
  SLURM array task per subject with completed structural outputs.
- `scripts/submit_hcp_functional_hyak.sbatch`: worker used by the functional
  array.
- `scripts/run_msmall.sh`: wraps the MSMAll driver, handles subject selection,
  container binds, logs, and optional eligibility filtering.
- `scripts/msmall_driver.sh`: runs `MSMAll/MSMAllPipeline.sh` inside the HCP
  Pipelines container.
- `scripts/submit_msmall_array_hyak.sh`: submits one MSMAll SLURM array task
  per completed fMRIPrep subject.
- `scripts/submit_msmall_hyak.sbatch`: worker used by the MSMAll array.

## Prerequisites

Run from the repository root on Hyak:

```bash
cd /gscratch/scrubbed/fanglab/xiaoqian/repo/R01
```

Create and edit the environment file if it does not already exist:

```bash
cp config/mri_preproc.env.example config/mri_preproc.env
```

Confirm these paths and settings in `config/mri_preproc.env`:

```bash
PROJECT_DIR="/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS"
BIDS_DIR="${PROJECT_DIR}/sourcedata/nii"
DERIVATIVES_DIR="${PROJECT_DIR}/derivatives"
FMRIPREP_OUT="${DERIVATIVES_DIR}/fmriprep"
FS_SUBJECTS_DIR="${DERIVATIVES_DIR}/freesurfer"
FS_LICENSE="/mmfs1/home/xxqian/files/fs_license.txt"
CONTAINER_RUNTIME="apptainer"
MSMALL_IMAGE="/gscratch/fang/images/hcp-pipelines-5.0.0.sif"
MSMALL_DRIVER_SCRIPT="/gscratch/scrubbed/fanglab/xiaoqian/repo/R01/scripts/msmall_driver.sh"
MSMALL_HCP_STUDY_FOLDER="${HCP_STRUCTURAL_OUT}"
```

The HCP Pipelines image must exist before running the pipeline:

```bash
sbatch scripts/build_hcp_pipelines.sbatch
```

The build writes:

```bash
/gscratch/fang/images/hcp-pipelines-5.0.0.sif
```

## Stage 1: HCP Structural

Submit the structural preprocessing array:

```bash
scripts/submit_hcp_structural_array_hyak.sh config/mri_preproc.env
```

This submits one SLURM array task per eligible BIDS subject found under:

```bash
${BIDS_DIR}/sub-*
```

When `HCP_REQUIRE_T2_FOR_MSMALL="1"`, subjects without a T2w image are skipped
before submission. The skipped-subject list is written to `LOG_DIR`.

Each worker runs:

```bash
scripts/run_hcp_structural.sh config/mri_preproc.env
```

Expected subject-level output:

```bash
${HCP_STRUCTURAL_OUT}/${SUBJECT_ID}/MNINonLinear
${HCP_STRUCTURAL_OUT}/${SUBJECT_ID}/MNINonLinear/Native/${SUBJECT_ID}.MyelinMap.native.dscalar.nii
```

For `sub-305`, `SUBJECT_ID` is `305`.

By default, `HCP_REQUIRE_T2_FOR_MSMALL="1"`. Keep this enabled for MSMAll,
because MSMAll needs the HCP myelin-map products.

## Stage 2: HCP Functional and FIX

After structural jobs finish and basic QC passes, submit the functional array:

```bash
scripts/submit_hcp_functional_array_hyak.sh config/mri_preproc.env
```

The submitter includes only subjects with an existing structural
`MNINonLinear` folder under `HCP_STRUCTURAL_OUT`.

Each worker runs:

```bash
scripts/run_hcp_functional.sh config/mri_preproc.env
```

The functional script finds raw BOLD runs using:

```bash
HCP_FUNCTIONAL_RUN_GLOB="func/*_bold.nii.gz"
HCP_FUNCTIONAL_RUN_INCLUDE_REGEX=""
HCP_FUNCTIONAL_RUN_EXCLUDE_REGEX="desc-|space-|_boldref"
```

With the current config, TOPUP distortion correction is enabled:

```bash
HCP_FMRI_DISTORTION_CORRECTION="TOPUP"
HCP_FMRI_TOPUP_NEGATIVE_GLOB="fmap/*dir-AP*_epi.nii.gz"
HCP_FMRI_TOPUP_POSITIVE_GLOB="fmap/*dir-PA*_epi.nii.gz"
HCP_FMRI_UNWARP_DIR_DEFAULT="y-"
```

Expected functional/FIX outputs:

```bash
${HCP_STRUCTURAL_OUT}/${SUBJECT_ID}/MNINonLinear/Results/${HCP_FMRI_CONCAT_NAME}/${HCP_FMRI_CONCAT_NAME}_Atlas_hp${HCP_FMRI_HIGH_PASS}_clean.dtseries.nii
${HCP_STRUCTURAL_OUT}/${SUBJECT_ID}/MNINonLinear/Results/${HCP_FMRI_CONCAT_NAME}/${HCP_FMRI_CONCAT_NAME}_Atlas_hp${HCP_FMRI_HIGH_PASS}_clean_vn.dscalar.nii
${HCP_STRUCTURAL_OUT}/${SUBJECT_ID}/MNINonLinear/Results/hcp_functional_msmall_inputs.txt
```

The manifest records the fMRI run names, FIX concatenation name, high-pass
setting, output fMRI name, and TOPUP inputs. `msmall_driver.sh` reads this file
automatically.

## Stage 3: MSMAll

After functional/FIX jobs finish and the expected files exist, submit MSMAll:

```bash
scripts/submit_msmall_array_hyak.sh config/mri_preproc.env
```

Each worker runs:

```bash
scripts/run_msmall.sh config/mri_preproc.env
```

The submitter includes only subjects with `MNINonLinear`, a native myelin map,
the functional MSMAll manifest, and the expected multi-run FIX outputs. Subjects
missing those inputs are written to a skipped-subject list in `LOG_DIR`.

`run_msmall.sh` binds `MSMALL_HCP_STUDY_FOLDER` read-only as `/hcp_input`.
For each subject, the driver stages the subject into `/work/hcp` and runs:

```bash
${HCPPIPEDIR}/MSMAll/MSMAllPipeline.sh
```

Expected MSMAll output directory:

```bash
${MSMALL_OUT}/sub-${SUBJECT_ID}
```

The driver also writes:

```bash
${MSMALL_OUT}/sub-${SUBJECT_ID}/msmall_driver_command.txt
```

After MSMAll finishes, the wrapper copies the updated `MNINonLinear` tree into
the subject output directory when possible.

## Optional Subject Selection

For cohort-wide arrays, leave these empty:

```bash
HCP_STRUCTURAL_PARTICIPANT_LABELS=""
HCP_FUNCTIONAL_PARTICIPANT_LABELS=""
MSMALL_PARTICIPANT_LABELS=""
```

For a manual single-subject test inside an interactive allocation, set one of
these in `config/mri_preproc.env` or export it in the shell:

```bash
HCP_STRUCTURAL_PARTICIPANT_LABELS="sub-305"
HCP_FUNCTIONAL_PARTICIPANT_LABELS="sub-305"
MSMALL_PARTICIPANT_LABELS="sub-305"
```

Then run the corresponding wrapper directly:

```bash
scripts/run_hcp_structural.sh config/mri_preproc.env
scripts/run_hcp_functional.sh config/mri_preproc.env
scripts/run_msmall.sh config/mri_preproc.env
```

## Optional MSMAll Eligibility File

If `MSMALL_ELIGIBILITY_CSV` exists, `run_msmall.sh` only runs subjects marked
eligible. The CSV must include `subject` and `eligible` columns:

```csv
subject,eligible
sub-305,yes
sub-306,no
```

Accepted eligible values are:

```text
1, true, yes, pass, eligible
```

If the CSV does not exist, all selected subjects are treated as eligible.

## Resource Controls

Set these in `config/mri_preproc.env`:

```bash
HCP_STRUCTURAL_ARRAY_CONCURRENCY="10"
HCP_STRUCTURAL_HYAK_TIME="72:00:00"
HCP_FUNCTIONAL_ARRAY_CONCURRENCY="10"
HCP_FUNCTIONAL_HYAK_TIME="48:00:00"
MSMALL_ARRAY_CONCURRENCY="10"
MSMALL_HYAK_TIME="48:00:00"
OMP_NTHREADS="8"
```

The `.sbatch` files request 16 CPUs and 64 GB memory by default.

## Logs

SLURM logs are written under:

```bash
logs/slurm/
```

Command records and run logs are written under:

```bash
${LOG_DIR}
```

Useful log names include:

```bash
hcp_structural_command_*.txt
hcp_structural_run_*.log
hcp_functional_command_*.txt
hcp_functional_run_*.log
msmall_command_*.txt
msmall_run_*.log
```

## Minimal Full Run Order

Use this order for a full cohort run:

```bash
cd /gscratch/scrubbed/fanglab/xiaoqian/repo/R01

sbatch scripts/build_hcp_pipelines.sbatch

scripts/submit_hcp_structural_array_hyak.sh config/mri_preproc.env

# After structural completion and QC:
scripts/submit_hcp_functional_array_hyak.sh config/mri_preproc.env

# After functional/FIX completion and QC:
scripts/submit_msmall_array_hyak.sh config/mri_preproc.env
```

## Preflight Checks

Before submitting MSMAll, confirm one subject has the required HCP inputs:

```bash
SUBJECT_ID=305
test -d "${HCP_STRUCTURAL_OUT}/${SUBJECT_ID}/MNINonLinear"
test -f "${HCP_STRUCTURAL_OUT}/${SUBJECT_ID}/MNINonLinear/Native/${SUBJECT_ID}.MyelinMap.native.dscalar.nii"
test -f "${HCP_STRUCTURAL_OUT}/${SUBJECT_ID}/MNINonLinear/Results/${HCP_FMRI_CONCAT_NAME}/${HCP_FMRI_CONCAT_NAME}_Atlas_hp${HCP_FMRI_HIGH_PASS}_clean.dtseries.nii"
test -f "${HCP_STRUCTURAL_OUT}/${SUBJECT_ID}/MNINonLinear/Results/${HCP_FMRI_CONCAT_NAME}/${HCP_FMRI_CONCAT_NAME}_Atlas_hp${HCP_FMRI_HIGH_PASS}_clean_vn.dscalar.nii"
test -f "${HCP_STRUCTURAL_OUT}/${SUBJECT_ID}/MNINonLinear/Results/hcp_functional_msmall_inputs.txt"
```

Also confirm the driver is executable:

```bash
test -x "${MSMALL_DRIVER_SCRIPT}"
```

## Common Failures

### `MSMALL_HCP_STUDY_FOLDER is empty`

MSMAll needs HCP-style inputs. Set:

```bash
MSMALL_HCP_STUDY_FOLDER="${HCP_STRUCTURAL_OUT}"
```

Do not set `MSMALL_ALLOW_WITHOUT_HCP=1` for production.

### `no T2w images found`

The structural stage needs T2w images to create myelin maps for MSMAll. Keep
`HCP_REQUIRE_T2_FOR_MSMALL="1"` and check the raw BIDS anatomical files.
For cohort arrays, subjects without T2w images are skipped by
`submit_hcp_structural_array_hyak.sh`; this error mainly appears in older jobs
or direct manual runs.

### `TOPUP requested but no ... SE-EPI found`

Check the fieldmap naming and update:

```bash
HCP_FMRI_TOPUP_NEGATIVE_GLOB
HCP_FMRI_TOPUP_POSITIVE_GLOB
HCP_FMRI_TOPUP_NEGATIVE_IMAGE
HCP_FMRI_TOPUP_POSITIVE_IMAGE
```

Use the explicit image variables when a subject has unusual filenames.

### `set --multirun-fix-names when --fmri-names-list is empty`

The functional manifest is missing or empty. Rerun `run_hcp_functional.sh` for
that subject and confirm `hcp_functional_msmall_inputs.txt` exists.

### `MSMAll myelin target does not exist`

The HCP Pipelines image does not contain the expected MSMAll templates, or
`HCPPIPEDIR` was discovered incorrectly. Inspect the image and set
`MSMALL_TEMPLATES` or `MYELIN_TARGET_FILE` through `EXTRA_MSMALL_ARGS` only
after confirming the correct template paths.
