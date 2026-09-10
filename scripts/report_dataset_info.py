#!/usr/bin/env python3
"""Report basic subject, session, and run information for a BIDS dataset."""

from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from pathlib import Path


BOLD_SUFFIXES = (".nii.gz", ".nii")


@dataclass(frozen=True)
class SessionSummary:
    subject: str
    group: str
    session: str
    runs: tuple[str, ...]

    @property
    def run_count(self) -> int:
        return len(self.runs)


def strip_bids_prefix(subject_name: str) -> str:
    return subject_name.removeprefix("sub-")


def group_for_subject(subject_name: str) -> str:
    subject_id = strip_bids_prefix(subject_name)
    if subject_id.startswith("1"):
        return "patient"
    if subject_id.startswith("3"):
        return "HC"
    return "unknown"


def discover_sessions(subject_dir: Path) -> list[Path]:
    sessions = sorted(path for path in subject_dir.glob("ses-*") if path.is_dir())
    return sessions if sessions else [subject_dir]


def strip_nii_suffix(filename: str) -> str:
    for suffix in BOLD_SUFFIXES:
        if filename.endswith(suffix):
            return filename[: -len(suffix)]
    return filename


def run_label_from_bold(bold_file: Path) -> str:
    stem = strip_nii_suffix(bold_file.name)
    entities = dict(re.findall(r"(sub|ses|task|acq|dir|run|echo)-([^_]+)", stem))
    label_parts = [
        f"{entity}-{entities[entity]}"
        for entity in ("task", "acq", "dir", "run", "echo")
        if entity in entities
    ]
    if label_parts:
        return "_".join(label_parts)
    return stem


def discover_runs(session_dir: Path) -> tuple[str, ...]:
    func_dir = session_dir / "func"
    if not func_dir.is_dir():
        return ()

    bold_files = sorted(
        path
        for suffix in BOLD_SUFFIXES
        for path in func_dir.glob(f"*_bold{suffix}")
        if path.is_file()
    )
    return tuple(run_label_from_bold(path) for path in bold_files)


def build_session_summaries(bids_dir: Path) -> list[SessionSummary]:
    summaries: list[SessionSummary] = []
    subjects = sorted(path for path in bids_dir.glob("sub-*") if path.is_dir())

    for subject_dir in subjects:
        group = group_for_subject(subject_dir.name)
        for session_dir in discover_sessions(subject_dir):
            session = session_dir.name if session_dir.name.startswith("ses-") else "single-session"
            summaries.append(
                SessionSummary(
                    subject=subject_dir.name,
                    group=group,
                    session=session,
                    runs=discover_runs(session_dir),
                )
            )

    return summaries


def write_csv(summaries: list[SessionSummary], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["subject", "group", "session", "run_count", "runs"],
        )
        writer.writeheader()
        for summary in summaries:
            writer.writerow(
                {
                    "subject": summary.subject,
                    "group": summary.group,
                    "session": summary.session,
                    "run_count": summary.run_count,
                    "runs": ";".join(summary.runs),
                }
            )


def print_report(summaries: list[SessionSummary], bids_dir: Path) -> None:
    subjects_by_group: dict[str, set[str]] = {"patient": set(), "HC": set(), "unknown": set()}
    sessions_by_subject: dict[str, list[SessionSummary]] = {}

    for summary in summaries:
        subjects_by_group.setdefault(summary.group, set()).add(summary.subject)
        sessions_by_subject.setdefault(summary.subject, []).append(summary)

    print(f"Dataset: {bids_dir}")
    print()
    print("Subjects by group")
    for group in ("patient", "HC", "unknown"):
        subjects = sorted(subjects_by_group.get(group, set()))
        print(f"- {group}: {len(subjects)}")
    print(f"- total: {len(sessions_by_subject)}")
    print()
    print("Sessions and runs by subject")

    for subject in sorted(sessions_by_subject):
        subject_summaries = sorted(sessions_by_subject[subject], key=lambda item: item.session)
        group = subject_summaries[0].group
        session_names = ", ".join(summary.session for summary in subject_summaries)
        print(f"- {subject} ({group}): {len(subject_summaries)} session(s): {session_names}")
        for summary in subject_summaries:
            runs = ", ".join(summary.runs) if summary.runs else "none"
            print(f"  - {summary.session}: {summary.run_count} run(s): {runs}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog=(
            "Hyak usage: scripts/run_dataset_info_report_hyak.sh "
            "config/mri_preproc.env"
        ),
    )
    parser.add_argument("bids_dir", type=Path, help="Path to the BIDS dataset root containing sub-* folders.")
    parser.add_argument(
        "--csv",
        type=Path,
        help="Optional path for a session-level CSV report.",
    )
    args = parser.parse_args()

    if not args.bids_dir.exists():
        parser.error(f"BIDS directory does not exist: {args.bids_dir}")
    if not args.bids_dir.is_dir():
        parser.error(f"BIDS path is not a directory: {args.bids_dir}")

    summaries = build_session_summaries(args.bids_dir)
    if not summaries:
        parser.error(f"No sub-* directories found in BIDS directory: {args.bids_dir}")

    print_report(summaries, args.bids_dir)

    if args.csv:
        write_csv(summaries, args.csv)
        print()
        print(f"Wrote CSV report: {args.csv}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
