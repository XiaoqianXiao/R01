# MRI Preprocessing Scripts

These scripts implement the executable pieces of `plans/MRI_Preprocessing_Plan.md`.
The plan remains the scientific specification; these scripts are operational helpers.

## Project Execution Summary

**Goal:** produce a frozen, auditable MRI preprocessing release with raw-data
QC, canonical fMRIPrep derivatives, and separately versioned optional branches.

**Operating model:** run cohort-scale work on Hyak using subject-level SLURM
arrays where possible. Keep one BIDS subject per array task for fMRIPrep,
MRIQC, HippUnfold, FIRST, and MSMAll branch workers.

**Done means:**

- BIDS validation and SDC metadata audits are complete with logs archived.
- MRIQC participant and group outputs are generated under `derivatives/qc/mriqc`.
- Canonical fMRIPrep outputs pass expected-file checks.
- Optional branches are run only after their prerequisites and pilot/QC gates are met.
- Container images, commands, logs, config, and checksums are preserved in the release manifest.
- QC decisions are recorded in the branch-aware QC files described by the QC SOP.

## Execution Roadmap

| Phase | Purpose | Main commands | Exit gate |
|---|---|---|---|
| 0. Configure | Create project-specific env file and verify Hyak paths/resources. | `cp config/mri_preproc.env.example config/mri_preproc.env` | Config is reviewed; required paths, images, license, resources, and array concurrency are set. |
| 1. Build/cache | Prepare frozen containers and offline resources. | `sbatch scripts/build_mriqc.sbatch`; `sbatch scripts/build_fmriprep.sbatch`; `scripts/prefetch_templateflow_hyak.sh config/mri_preproc.env` | Required `.sif` files, checksums, TemplateFlow cache, and branch-specific caches exist. |
| 2. Raw preflight | Validate BIDS and audit AP/PA SDC metadata before production. | `scripts/run_bids_validator.sh config/mri_preproc.env`; `scripts/run_python_hyak.sh ... audit_sdc_metadata.py` | No unresolved BIDS/metadata errors that compromise preprocessing. |
| 3. MRIQC | Generate raw-image QC reports and cohort IQM tables. | `scripts/submit_mriqc_array_hyak.sh config/mri_preproc.env`; `sbatch scripts/submit_mriqc_group_hyak.sbatch config/mri_preproc.env` | Participant and group MRIQC reports are complete and ready for reviewer adjudication. |
| 4. Pilot | Run the pre-production pilot and inspect expected outputs. | `sbatch scripts/submit_preproduction_pilot_hyak.sbatch config/mri_preproc.env` | Pilot QC accepts fMRIPrep settings, SDC behavior, output spaces, and resource profile. |
| 5. Canonical production | Run frozen fMRIPrep release. | `scripts/submit_fmriprep_array_hyak.sh config/mri_preproc.env` | Every intended subject has complete or explicitly documented fMRIPrep status. |
| 6. Output/provenance closeout | Check derivatives and freeze provenance. | `scripts/check_fmriprep_outputs.py`; `scripts/freeze_release_manifest.py` | Expected outputs, logs, commands, config, and checksums are archived. |
| 7. Optional branches | Run branch-specific derivatives only when eligible and approved. | `scripts/submit_hippunfold_array_hyak.sh`; `scripts/submit_first_array_hyak.sh`; `scripts/submit_msmall_array_hyak.sh` | Branch outputs and branch-specific QC statuses are recorded without changing unrelated branch decisions. |

## Dependency Map

```text
config/mri_preproc.env
  ├── container builds / resource caches
  │     ├── MRIQC image
  │     ├── fMRIPrep image
  │     ├── TemplateFlow cache
  │     ├── HippUnfold image/cache
  │     └── HCP Pipelines image
  ├── raw preflight
  │     ├── BIDS validation
  │     └── SDC metadata audit
  ├── MRIQC participant array ──> MRIQC group
  └── fMRIPrep pilot ──> fMRIPrep production ──> output check / release manifest
                                      ├── HippUnfold branch
                                      ├── FIRST branch
                                      └── MSMAll branch, after eligibility gate
```

## Management Checkpoints

Use these checkpoints as sign-offs before moving to the next expensive stage:

- **Configuration review:** confirm Hyak paths, container image paths, resource requests, `FS_LICENSE`, and privacy setting `MRIQC_NO_SUB`.
- **Raw-data gate:** BIDS validation and SDC metadata audit have no unresolved blocking errors.
- **MRIQC gate:** participant reports and group IQM tables exist; metric outliers are queued for manual review, not automatically failed.
- **Pilot gate:** fMRIPrep pilot confirms AP/PA SDC behavior, output-space choices, multi-session handling, and memory/runtime fit.
- **Production gate:** fMRIPrep array jobs are complete, crashes are logged as `processing_failed`, and expected outputs are checked.
- **Branch gate:** HippUnfold, FIRST, and MSMAll run only after branch prerequisites are met and the branch-specific QC plan is ready.
- **Release gate:** manifests, checksums, logs, command records, QC tables, rerun notes, and exclusion reasons are versioned together.

## Ownership Model

| Role | Owns | Key decision |
|---|---|---|
| Preprocessing lead | Frozen preprocessing configuration, pilot acceptance, release gate. | Whether the production settings are scientifically and operationally ready. |
| Hyak operator | Container builds, cache preparation, SLURM submissions, job monitoring. | Whether the cluster run is technically ready to launch or rerun. |
| QC reviewer | MRIQC/fMRIPrep/branch visual review and reason-code entry. | Whether each raw scan or derivative branch is `pass`, `pass_with_note`, `review_required`, or `fail`. |
| Analysis lead | Downstream recipe-specific exclusions and eligibility. | Whether data enter a specific FC, GLM, MVPA, or longitudinal analysis. |

## Files

- `config/mri_preproc.env.example`: copy to `config/mri_preproc.env` on Hyak and edit project paths, Apptainer/Singularity image, FreeSurfer license, resource limits, and participant labels.
- `scripts/run_bids_validator.sh`: runs BIDS validation and saves a log.
- `scripts/download_templateflow_cache.sh`: downloads and packages the TemplateFlow cache on a machine with internet access.
- `scripts/prefetch_templateflow_hyak.sh`: populates the TemplateFlow cache before offline Hyak fMRIPrep jobs.
- `scripts/build_mriqc.sbatch`: builds the MRIQC `.sif` used for raw-image QC.
- `scripts/build_hcp_pipelines.sbatch`: builds the HCP Pipelines 5.0.0 `.sif` used by the MSMAll branch.
- `scripts/build_hippunfold.sbatch`: builds the HippUnfold 2.0.0 `.sif` used by the HippUnfold branch.
- `scripts/prefetch_hippunfold_models_hyak.sh`: downloads and unpacks the HippUnfold nnU-Net model, atlas, and template cache before offline Hyak array jobs.
- `scripts/run_python_hyak.sh`: runs Python helper scripts inside `/gscratch/fang/images/jupyter.sif`.
- `scripts/make_multisession_manifest.py`: records each subject/session and whether anat, func, and fmap files are present.
- `scripts/audit_sdc_metadata.py`: audits AP/PA fieldmap JSON metadata, `B0FieldIdentifier` / `B0FieldSource` mappings, `IntendedFor`, readout metadata, and optional fieldmap geometry.
- `scripts/run_mriqc.sh`: runs MRIQC participant or group level with project resource controls and `--no-sub` by default.
- `scripts/submit_mriqc_array_hyak.sh`: submits one MRIQC participant-level array task per BIDS subject.
- `scripts/submit_mriqc_hyak.sbatch`: submits the MRIQC participant-level worker as a Hyak SLURM job.
- `scripts/submit_mriqc_group_hyak.sbatch`: submits MRIQC group-level report/table generation after participant outputs are complete.
- `scripts/run_fmriprep.sh`: runs the canonical fMRIPrep 25.2.5 workflow with `func`, `T1w`, `MNI152NLin2009cAsym:res-native`, `fsnative`, CIFTI 91k, MSMSulc, explicit session tracking, and `--slice-time-ref 0.5`.
- `scripts/submit_fmriprep_array_hyak.sh`: generates a subject list from `BIDS_DIR` and submits one SLURM array task per subject.
- `scripts/submit_fmriprep_hyak.sbatch`: submits the canonical fMRIPrep worker as a Hyak SLURM job.
- `scripts/run_hippunfold.sh`: runs the separate HippUnfold derivative branch.
- `scripts/submit_hippunfold_array_hyak.sh`: submits one HippUnfold array task per BIDS subject.
- `scripts/run_first.sh`: runs the separate FSL FIRST derivative branch from fMRIPrep T1w anatomical outputs.
- `scripts/submit_first_array_hyak.sh`: submits one FIRST array task per completed fMRIPrep subject.
- `scripts/run_msmall.sh`: runs the separate MSMAll branch wrapper for eligible subjects using a project-specific driver.
- `scripts/submit_msmall_array_hyak.sh`: submits one MSMAll array task per completed fMRIPrep subject.
- `scripts/msmall_driver.sh`: runs HCP Pipelines MSMAll inside the container.
- `scripts/README_MSMALL_PIPELINE.md`: gives the full HCP structural, HCP functional/FIX, and MSMAll run order.
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
- `MRIQC_IMAGE` to the frozen MRIQC `.sif`, usually `/gscratch/fang/images/mriqc-24.0.2.sif`
- `MRIQC_NO_SUB=1` unless anonymized MRIQC metric submission has been approved
- `PYTHON_CONTAINER_IMAGE` to the Python/Jupyter `.sif`, usually `/gscratch/fang/images/jupyter.sif`
- `PYTHON_CONTAINER_PYTHON` to the Python executable inside that container, usually `python3`
- `APPTAINER_NO_MOUNT` to `bind-paths` so Hyak does not try to auto-mount unavailable site paths
- `FS_LICENSE` to the FreeSurfer license on Hyak, usually `/mmfs1/home/xxqian/files/fs_license.txt`
- `HYAK_ARRAY_CONCURRENCY`; controls how many subject jobs can run at the same time
- `PARTICIPANT_LABELS`; only used for manual/non-array runs
- `NTHREADS`, `OMP_NTHREADS`, and `MEM_MB` to match the SLURM request

If the fMRIPrep Apptainer image has not been built yet, submit the existing image-build job first:

```bash
sbatch scripts/build_fmriprep.sbatch
```

If the MRIQC Apptainer image has not been built yet, submit:

```bash
sbatch scripts/build_mriqc.sbatch
```

The build script writes `/gscratch/fang/images/mriqc-24.0.2.sif` by default,
matching `MRIQC_IMAGE` in `config/mri_preproc.env`. To build a different
project-frozen version:

```bash
MRIQC_VERSION=YOUR_VERSION sbatch scripts/build_mriqc.sbatch
```

If the HCP Pipelines 5.0.0 Apptainer image for MSMAll has not been built yet,
submit:

```bash
sbatch scripts/build_hcp_pipelines.sbatch
```

The build script writes `/gscratch/fang/images/hcp-pipelines-5.0.0.sif`,
matching `MSMALL_IMAGE` in `config/mri_preproc.env`. To use a lab-approved or
registered QuNex source image instead of the public fallback, submit with:

```bash
HCP_PIPELINES_SOURCE=docker://YOUR_IMAGE:TAG sbatch scripts/build_hcp_pipelines.sbatch
```

If the HippUnfold 2.0.0 Apptainer image has not been built yet, submit:

```bash
sbatch scripts/build_hippunfold.sbatch
```

The build script writes `/gscratch/fang/images/hippunfold-2.0.0.sif`,
matching `HIPPUNFOLD_IMAGE` in `config/mri_preproc.env`. To use a different
frozen source image, submit with:

```bash
HIPPUNFOLD_SOURCE=docker://YOUR_IMAGE:TAG sbatch scripts/build_hippunfold.sbatch
```

For the official `khanlab/hippunfold:dev-v2.0.0` image converted with
Apptainer, run through `/app/entrypoint.sh` with
`HIPPUNFOLD_CONTAINER_COMMAND=hippunfold`. The entrypoint initializes the
container's pixi/conda environment before launching HippUnfold. Passing
`hippunfold` explicitly also prevents Apptainer from handing `/data` to the
entrypoint as the command.

HippUnfold containers from v1.3.0 onward download model files on demand.
Before offline or restricted compute runs, populate the shared
`HIPPUNFOLD_CACHE_DIR` from an internet-enabled login/data-transfer context.
The helper downloads the required nnU-Net tarball into
`${HIPPUNFOLD_CACHE_DIR}/model` and unpacks it. It also downloads the
`multihist7` atlas and the default `CITI168` and `upenn` templates. It writes
Snakemake directory markers into these cache directories so array jobs do not
try to rebuild shared atlas/template resources. This keeps compute nodes from
resolving Zenodo or OSF during Snakemake DAG construction:

```bash
scripts/prefetch_hippunfold_models_hyak.sh config/mri_preproc.env
```

Wait for the helper to finish downloading and extracting the model before
submitting the array. A successful run prints `HippUnfold model cache is ready`
and reports both the model tarball and unpacked model directory. For the default
T1w branch, verify:

```bash
ls -lh "${HIPPUNFOLD_CACHE_DIR}/model/trained_model.3d_fullres.Task101_hcp1200_T1w.nnUNetTrainerV2.model_best.tar"
test -d "${HIPPUNFOLD_CACHE_DIR}/model/trained_model.3d_fullres.Task101_hcp1200_T1w.nnUNetTrainerV2.model_best"
test -d "${HIPPUNFOLD_CACHE_DIR}/atlases_dl/tpl-multihist7"
test -d "${HIPPUNFOLD_CACHE_DIR}/atlas/multihist7"
test -d "${HIPPUNFOLD_CACHE_DIR}/atlases/tpl-multihist7"
test -d "${HIPPUNFOLD_CACHE_DIR}/template/CITI168"
test -d "${HIPPUNFOLD_CACHE_DIR}/template/upenn"
test -f "${HIPPUNFOLD_CACHE_DIR}/atlases/tpl-multihist7/.snakemake_timestamp"
```

Array submission requires the model and resource caches to already exist in
`HIPPUNFOLD_CACHE_DIR` by default. This prevents compute-node jobs from failing
during DAG construction when they cannot resolve `zenodo.org` or OSF. Set
`HIPPUNFOLD_REQUIRE_CACHED_MODEL=0` or
`HIPPUNFOLD_REQUIRE_CACHED_RESOURCES=0` only for a deliberate online test.

Populate the project TemplateFlow cache before submitting fMRIPrep on compute
nodes. No TemplateFlow customization is needed; the scripts use
`${PROJECT_DIR}/templateflow` automatically when `TEMPLATEFLOW_HOME` is empty.
This avoids runtime failures when a job tries to download templates from S3 on
a DNS- or internet-restricted node:

```bash
scripts/prefetch_templateflow_hyak.sh config/mri_preproc.env
```

If the prefetch script reports that it cannot resolve
`templateflow.s3.amazonaws.com`, the current Hyak context also lacks
internet/DNS access. Run the prefetch from a login/data-transfer node with
internet access, or copy a populated TemplateFlow cache into
`${PROJECT_DIR}/templateflow` before submitting the array.

To download the cache somewhere else and package it for transfer:

```bash
scripts/download_templateflow_cache.sh
scp templateflow_download/templateflow.tar.gz YOUR_HYAK_USER@klone.hyak.uw.edu:/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/
```

Submit the full pre-production pilot job:

```bash
sbatch scripts/submit_preproduction_pilot_hyak.sbatch config/mri_preproc.env
```

Submit one parallel array task per subject:

```bash
scripts/submit_fmriprep_array_hyak.sh config/mri_preproc.env
```

The submitter first checks that the TemplateFlow cache exists and contains the
required template files. It then writes a subject list and multi-session
manifest into `LOG_DIR`, then submits:

```bash
one SLURM array task = one BIDS subject
```

For this multi-session project, do not split production into one array task per session. Each subject task keeps all intended sessions visible to fMRIPrep, uses `--subject-anatomical-reference unbiased`, and explicitly uses `--track-sessions`. This preserves a common within-subject anatomical reference while keeping functional outputs session- and run-specific.

Submit the specialized derivative branches only after their branch-specific
pilot/QC decisions are frozen:

```bash
scripts/submit_hippunfold_array_hyak.sh config/mri_preproc.env
scripts/submit_first_array_hyak.sh config/mri_preproc.env
scripts/submit_msmall_array_hyak.sh config/mri_preproc.env
```

Run MRIQC before or alongside production fMRIPrep. Participant level is run as
one subject per SLURM array task:

```bash
scripts/submit_mriqc_array_hyak.sh config/mri_preproc.env
```

After all participant-level MRIQC jobs are complete, generate group-level
reports and IQM tables from the same output directory:

```bash
sbatch scripts/submit_mriqc_group_hyak.sbatch config/mri_preproc.env
```

By default MRIQC runs with:

```bash
MRIQC_MODALITIES="T1w T2w bold"
MRIQC_NO_SUB="1"
```

Keep `MRIQC_NO_SUB=1` unless project leadership explicitly approves submission
of anonymized MRIQC IQMs.

The HippUnfold branch reads raw BIDS and writes `${DERIVATIVES_DIR}/hippunfold`.
Set `HIPPUNFOLD_MODALITY` in `config/mri_preproc.env` to the image type used
for segmentation, usually `T1w` for the raw anatomical branch.
Run `scripts/prefetch_hippunfold_models_hyak.sh config/mri_preproc.env` and
wait for the download and extraction to complete before calling
`scripts/submit_hippunfold_array_hyak.sh`.
Each array task binds private `${HIPPUNFOLD_WORK}/SUBJECT/.snakebids`,
`${HIPPUNFOLD_WORK}/SUBJECT/.snakemake`, and
`${HIPPUNFOLD_WORK}/SUBJECT/config` paths over `/out/.snakebids`,
`/out/.snakemake`, and `/out/config`. This avoids races in Snakebids'
non-atomic output-mode marker, generated Snakemake config, and lock metadata
when many participants start at once.
The FIRST branch reads completed fMRIPrep anatomical outputs and writes
`${DERIVATIVES_DIR}/first`. The MSMAll branch is a three-stage HCP workflow:
HCP structural preprocessing, HCP functional/FIX preprocessing, then MSMAll.
Use `scripts/README_MSMALL_PIPELINE.md` for the full run order and required
preflight checks.

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

- exact MRIQC container image and digest
- exact fMRIPrep 25.2.5 container image and digest
- FreeSurfer license/configuration and version
- TemplateFlow snapshot
- BIDS Validator version and validation report
- MRIQC participant reports, group reports, and IQM tables
- explicit anatomical-reference strategy
- explicit `--track-sessions` or `--no-track-sessions`
- exact fMRIPrep command and resource settings
- SDC audit report
- pilot QC decisions
- output check report
- release manifest

Track every cohort run with:

- subject list and session manifest used for the array
- SLURM job IDs and array ranges
- failed jobs and rerun reason
- final output location
- reviewer/adjudicator responsible for the next QC decision

The canonical fMRIPrep scripts intentionally do not run denoising, atlas extraction, FC, graph analysis, task GLM, MVPA, HippUnfold, FIRST, or MSMAll production. Those are separate derivative branches in the plan and need their own frozen configurations. The branch wrappers above provide operational entry points for HippUnfold, FIRST, and MSMAll, but each branch still requires project-specific pilot acceptance before cohort-wide production.
