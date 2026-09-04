# MRI Preprocessing Scripts

These scripts implement the executable pieces of `plans/MRI_Preprocessing_Plan.md`.
The plan remains the scientific specification; these scripts are operational helpers.

## Files

- `config/mri_preproc.env.example`: copy to `config/mri_preproc.env` and edit project paths, container runtime, fMRIPrep image, FreeSurfer license, resource limits, and participant labels.
- `scripts/run_bids_validator.sh`: runs BIDS validation and saves a log.
- `scripts/audit_sdc_metadata.py`: audits AP/PA fieldmap JSON metadata, `B0FieldIdentifier` / `B0FieldSource` mappings, `IntendedFor`, readout metadata, and optional fieldmap geometry.
- `scripts/run_fmriprep.sh`: runs the canonical fMRIPrep 25.2.5 workflow with `func`, `T1w`, `MNI152NLin2009cAsym:res-native`, `fsnative`, CIFTI 91k, MSMSulc, explicit session tracking, and `--slice-time-ref 0.5`.
- `scripts/check_fmriprep_outputs.py`: checks that expected canonical derivatives exist after a run.
- `scripts/freeze_release_manifest.py`: writes a provenance JSON manifest with logs, config, command records, environment details, and checksums.
- `scripts/run_preproduction_pilot.sh`: runs the validation, audit, pilot fMRIPrep, output check, and manifest steps in order.

## Quick Start

From the repository root:

```bash
cp config/mri_preproc.env.example config/mri_preproc.env
```

Edit `config/mri_preproc.env`, then run a pilot on representative participant labels:

```bash
scripts/run_preproduction_pilot.sh config/mri_preproc.env
```

For only the canonical fMRIPrep run:

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
