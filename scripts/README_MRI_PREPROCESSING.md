# MRI Preprocessing Scripts

These scripts implement the executable pieces of `plans/MRI_Preprocessing_Plan.md`.
The plan remains the scientific specification; these scripts are operational helpers.

## Files

- `config/mri_preproc.env.example`: copy to `config/mri_preproc.env` on Hyak and edit project paths, Apptainer/Singularity image, FreeSurfer license, resource limits, and participant labels.
- `scripts/run_bids_validator.sh`: runs BIDS validation and saves a log.
- `scripts/prefetch_templateflow_hyak.sh`: populates the TemplateFlow cache before offline Hyak fMRIPrep jobs.
- `scripts/run_python_hyak.sh`: runs Python helper scripts inside `/gscratch/fang/images/jupyter.sif`.
- `scripts/make_multisession_manifest.py`: records each subject/session and whether anat, func, and fmap files are present.
- `scripts/audit_sdc_metadata.py`: audits AP/PA fieldmap JSON metadata, `B0FieldIdentifier` / `B0FieldSource` mappings, `IntendedFor`, readout metadata, and optional fieldmap geometry.
- `scripts/run_fmriprep.sh`: runs the canonical fMRIPrep 25.2.5 workflow with `func`, `T1w`, `MNI152NLin2009cAsym:res-native`, `fsnative`, CIFTI 91k, MSMSulc, explicit session tracking, and `--slice-time-ref 0.5`.
- `scripts/submit_fmriprep_array_hyak.sh`: generates a subject list from `BIDS_DIR` and submits one SLURM array task per subject.
- `scripts/submit_fmriprep_hyak.sbatch`: submits the canonical fMRIPrep worker as a Hyak SLURM job.
- `scripts/submit_preproduction_pilot_hyak.sbatch`: submits the full pre-production pilot wrapper as a Hyak SLURM job.
- `scripts/check_fmriprep_outputs.py`: checks that expected canonical derivatives exist after a run.
- `scripts/freeze_release_manifest.py`: writes a provenance JSON manifest with logs, config, command records, environment details, and checksums.
- `scripts/run_preproduction_pilot.sh`: runs the validation, audit, pilot fMRIPrep, output check, and manifest steps in order.

## Hyak Quick Start

All preprocessing should be run on Hyak. From the repository root on Hyak:

```bash
cp config/mri_preproc.env.example config/mri_preproc.env
```

Edit `config/mri_preproc.env` so paths point to the Hyak project storage. The IFOCUS defaults are:

```bash
PROJECT_DIR="/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS"
BIDS_DIR="/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/sourcedata/nii"
FMRIPREP_OUT="/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/derivatives/fmriprep"
FS_LICENSE="/mmfs1/home/xxqian/files/fs_license.txt"
```

Also set:

- `CONTAINER_RUNTIME` to `apptainer` or `singularity`
- `FMRIPREP_IMAGE` to the frozen fMRIPrep 25.2.5 `.sif`, usually `/gscratch/fang/images/fmriprep-25.2.5.sif`
- `PYTHON_CONTAINER_IMAGE` to the Python/Jupyter `.sif`, usually `/gscratch/fang/images/jupyter.sif`
- `PYTHON_CONTAINER_PYTHON` to the Python executable inside that container, usually `python3`
- `APPTAINER_NO_MOUNT` to `bind-paths` so Hyak does not try to auto-mount unavailable site paths
- `TEMPLATEFLOW_HOME` to a populated TemplateFlow cache, usually `${PROJECT_DIR}/templateflow`; if left empty, the scripts use that default
- `FS_LICENSE` to the FreeSurfer license on Hyak, usually `/mmfs1/home/xxqian/files/fs_license.txt`
- `HYAK_ARRAY_CONCURRENCY`; controls how many subject jobs can run at the same time
- `PARTICIPANT_LABELS`; only used for manual/non-array runs
- `NTHREADS`, `OMP_NTHREADS`, and `MEM_MB` to match the SLURM request

If the fMRIPrep Apptainer image has not been built yet, submit the existing image-build job first:

```bash
sbatch scripts/build_fmriprep.sbatch
```

Populate TemplateFlow before submitting fMRIPrep on compute nodes. This avoids
runtime failures when a job tries to download templates from S3 on a DNS- or
internet-restricted node. If `TEMPLATEFLOW_HOME=""`, the prefetch script uses
`${PROJECT_DIR}/templateflow` automatically:

```bash
scripts/prefetch_templateflow_hyak.sh config/mri_preproc.env
```

Submit the full pre-production pilot job:

```bash
sbatch scripts/submit_preproduction_pilot_hyak.sbatch config/mri_preproc.env
```

Submit one parallel array task per subject:

```bash
scripts/submit_fmriprep_array_hyak.sh config/mri_preproc.env
```

The submitter writes a subject list and multi-session manifest into `LOG_DIR`, then submits:

```bash
one SLURM array task = one BIDS subject
```

For this multi-session project, do not split production into one array task per session. Each subject task keeps all intended sessions visible to fMRIPrep, uses `--subject-anatomical-reference unbiased`, and explicitly uses `--track-sessions`. This preserves a common within-subject anatomical reference while keeping functional outputs session- and run-specific.

To change the number of subjects running at the same time, edit:

```bash
HYAK_ARRAY_CONCURRENCY="10"
```

To run the full pre-production wrapper manually inside an interactive Hyak allocation:

```bash
scripts/run_preproduction_pilot.sh config/mri_preproc.env
```

For only the canonical fMRIPrep worker inside an interactive Hyak job:

```bash
scripts/run_fmriprep.sh config/mri_preproc.env
```

For only the AP/PA SDC metadata audit:

```bash
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/audit_sdc_metadata.py "${BIDS_DIR}" \
  --output "${LOG_DIR}/sdc_metadata_audit.csv"
```

## Production Notes

Before cohort-wide production, freeze and archive:

- exact fMRIPrep 25.2.5 container image and digest
- FreeSurfer license/configuration and version
- TemplateFlow snapshot
- BIDS Validator version and validation report
- explicit anatomical-reference strategy
- explicit `--track-sessions` or `--no-track-sessions`
- exact fMRIPrep command and resource settings
- SDC audit report
- pilot QC decisions
- output check report
- release manifest

The scripts intentionally do not run denoising, atlas extraction, FC, graph analysis, task GLM, MVPA, HippUnfold, FIRST, or MSMAll production. Those are separate derivative branches in the plan and need their own frozen configurations.
