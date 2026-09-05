# MRI Preprocessing Scripts

These scripts implement the executable pieces of `plans/MRI_Preprocessing_Plan.md`.
The plan remains the scientific specification; these scripts are operational helpers.

## Files

- `config/mri_preproc.env.example`: copy to `config/mri_preproc.env` on Hyak and edit project paths, Apptainer/Singularity image, FreeSurfer license, resource limits, and participant labels.
- `scripts/run_bids_validator.sh`: runs BIDS validation and saves a log.
- `scripts/audit_sdc_metadata.py`: audits AP/PA fieldmap JSON metadata, `B0FieldIdentifier` / `B0FieldSource` mappings, `IntendedFor`, readout metadata, and optional fieldmap geometry.
- `scripts/run_fmriprep.sh`: runs the canonical fMRIPrep 25.2.5 workflow with `func`, `T1w`, `MNI152NLin2009cAsym:res-native`, `fsnative`, CIFTI 91k, MSMSulc, explicit session tracking, and `--slice-time-ref 0.5`.
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
- `FS_LICENSE` to the FreeSurfer license on Hyak, usually `/mmfs1/home/xxqian/files/fs_license.txt`
- `PARTICIPANT_LABELS`; use a small pilot sample before production, then leave it empty to run all subjects
- `NTHREADS`, `OMP_NTHREADS`, and `MEM_MB` to match the SLURM request

If the fMRIPrep Apptainer image has not been built yet, submit the existing image-build job first:

```bash
sbatch scripts/build_fmriprep.sbatch
```

Submit the full pre-production pilot job:

```bash
sbatch scripts/submit_preproduction_pilot_hyak.sbatch config/mri_preproc.env
```

Submit the canonical fMRIPrep job:

```bash
sbatch scripts/submit_fmriprep_hyak.sbatch config/mri_preproc.env
```

For all subjects, keep this line in `config/mri_preproc.env`:

```bash
PARTICIPANT_LABELS=""
```

For a larger request:

```bash
sbatch --cpus-per-task=24 --mem=96G --time=72:00:00 \
  scripts/submit_fmriprep_hyak.sbatch config/mri_preproc.env
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
python scripts/audit_sdc_metadata.py /project/rawdata/BIDS --output /project/logs/sdc_metadata_audit.csv
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
