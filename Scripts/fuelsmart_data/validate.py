"""Validation gates for the ingestion pipeline.

Two kinds of check:

*Record* validation drops individual bad rows without failing the build — a
single malformed government row must never cost the user the whole dataset.

*Dataset* validation fails the build loudly, because these conditions mean the
source format changed underneath us and the output should not be shipped.
"""

from __future__ import annotations

from collections import Counter, defaultdict

from .model import Powertrain, VehicleRecord


class DatasetValidationError(Exception):
    """Raised when generated output is not fit to bundle."""


def filter_valid(records: list[VehicleRecord]) -> tuple[list[VehicleRecord], list[tuple[VehicleRecord, list[str]]]]:
    """Split records into usable and rejected, with reasons."""
    good: list[VehicleRecord] = []
    bad: list[tuple[VehicleRecord, list[str]]] = []
    for record in records:
        issues = record.problems()
        (good if not issues else bad).append(record if not issues else (record, issues))
    return good, bad


def deduplicate(records: list[VehicleRecord]) -> tuple[list[VehicleRecord], int]:
    """Collapse records sharing an id.

    NRCan reissues unchanged rows across its multi-year files, so the same
    configuration legitimately appears more than once. The first occurrence wins;
    inputs are processed newest-first so the most recent publication is kept.
    """
    seen: set[str] = set()
    unique: list[VehicleRecord] = []
    duplicates = 0
    for record in records:
        if record.id in seen:
            duplicates += 1
            continue
        seen.add(record.id)
        unique.append(record)
    return unique, duplicates


def assert_dataset_sane(country: str, records: list[VehicleRecord], min_records: int) -> None:
    """Fail the build if the shape of the data suggests a schema change."""
    problems: list[str] = []

    if len(records) < min_records:
        problems.append(
            f"only {len(records)} usable records for {country}, expected at least {min_records}"
        )

    ids = Counter(record.id for record in records)
    collisions = [key for key, count in ids.items() if count > 1]
    if collisions:
        problems.append(f"{len(collisions)} duplicate ids survived deduplication")

    by_powertrain: dict[str, int] = defaultdict(int)
    for record in records:
        by_powertrain[record.powertrain] += 1

    # Every supported powertrain must be represented, or a parser has silently
    # stopped classifying one of them.
    for required in (Powertrain.GASOLINE, Powertrain.BEV, Powertrain.PHEV):
        if by_powertrain.get(required, 0) == 0:
            problems.append(f"no {required} records for {country}")

    # Electric records must carry real consumption, never a derived stand-in.
    missing_electric = [
        record.id for record in records
        if record.powertrain == Powertrain.BEV and record.combinedKwhPer100Km is None
    ]
    if missing_electric:
        problems.append(f"{len(missing_electric)} BEV records without kWh/100 km")

    if problems:
        raise DatasetValidationError(
            f"{country} dataset failed validation:\n  - " + "\n  - ".join(problems)
        )


def summarize_rejections(bad: list[tuple[VehicleRecord, list[str]]], limit: int = 8) -> str:
    """Human-readable rollup of why rows were dropped."""
    if not bad:
        return "no records rejected"
    reasons = Counter(issue for _, issues in bad for issue in issues)
    lines = [f"{len(bad)} records rejected:"]
    for reason, count in reasons.most_common(limit):
        lines.append(f"    {count:>6}  {reason}")
    return "\n".join(lines)
