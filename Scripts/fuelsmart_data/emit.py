"""Turn normalized records into the compact files the app bundles.

Two artefacts per country:

``vehicles-<CC>.json``
    Every record. Read once, lazily, and indexed in memory by the app.

``catalog-<CC>.json``
    A prebuilt year -> make -> model tree with counts. The browse picker renders
    entirely from this, so drilling Country -> Year -> Make -> Model never
    touches the large records file at all.

Plus one ``manifest.json`` describing versions, counts, checksums and the
attribution text the app is required to display.
"""

from __future__ import annotations

import hashlib
import json
import os
from collections import defaultdict
from datetime import datetime, timezone

from .model import VehicleRecord


def _write_json(path: str, payload: dict) -> int:
    """Write compact JSON (no spaces) and return the byte size."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    return len(text.encode("utf-8"))


def _sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_catalog(records: list[VehicleRecord]) -> dict:
    """year -> make -> [{model, configurations, powertrains, count}]."""
    tree: dict[int, dict[str, dict[str, dict]]] = defaultdict(lambda: defaultdict(dict))
    for record in records:
        bucket = tree[record.year][record.make]
        entry = bucket.setdefault(
            record.model,
            {"model": record.model, "count": 0, "powertrains": set(), "ids": []},
        )
        entry["count"] += 1
        entry["powertrains"].add(record.powertrain)
        entry["ids"].append(record.id)

    years = []
    for year in sorted(tree.keys(), reverse=True):
        makes = []
        for make in sorted(tree[year].keys(), key=str.casefold):
            models = []
            for model in sorted(tree[year][make].keys(), key=str.casefold):
                entry = tree[year][make][model]
                models.append({
                    "model": entry["model"],
                    "count": entry["count"],
                    "powertrains": sorted(entry["powertrains"]),
                    "ids": entry["ids"],
                })
            makes.append({
                "make": make,
                "count": sum(m["count"] for m in models),
                "models": models,
            })
        years.append({"year": year, "count": sum(m["count"] for m in makes), "makes": makes})
    return {"years": years}


def emit_country(
    out_dir: str,
    country: str,
    records: list[VehicleRecord],
    sources: list[dict],
    dataset_version: str,
) -> dict:
    records_path = os.path.join(out_dir, f"vehicles-{country}.json")
    catalog_path = os.path.join(out_dir, f"catalog-{country}.json")

    records_bytes = _write_json(records_path, {
        "schemaVersion": 1,
        "country": country,
        "datasetVersion": dataset_version,
        "records": [record.to_compact_dict() for record in records],
    })
    catalog_bytes = _write_json(catalog_path, {
        "schemaVersion": 1,
        "country": country,
        "datasetVersion": dataset_version,
        **build_catalog(records),
    })

    powertrain_counts: dict[str, int] = defaultdict(int)
    for record in records:
        powertrain_counts[record.powertrain] += 1

    return {
        "country": country,
        "recordCount": len(records),
        "yearRange": [min(r.year for r in records), max(r.year for r in records)] if records else None,
        "powertrainCounts": dict(sorted(powertrain_counts.items())),
        "files": {
            "records": {
                "name": os.path.basename(records_path),
                "bytes": records_bytes,
                "sha256": _sha256(records_path),
            },
            "catalog": {
                "name": os.path.basename(catalog_path),
                "bytes": catalog_bytes,
                "sha256": _sha256(catalog_path),
            },
        },
        "sources": sources,
    }


def emit_manifest(out_dir: str, countries: list[dict], dataset_version: str) -> str:
    path = os.path.join(out_dir, "manifest.json")
    _write_json(path, {
        "schemaVersion": 1,
        "datasetVersion": dataset_version,
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "countries": countries,
        "attribution": {
            "CA": "Contains information licensed under the Open Government Licence - Canada. "
                  "Fuel consumption ratings: Natural Resources Canada.",
            "US": "Fuel economy data: U.S. Department of Energy and U.S. Environmental "
                  "Protection Agency, fueleconomy.gov. A work of the U.S. Government.",
        },
        "disclaimer": "Government ratings are standardized laboratory tests. Real-world "
                      "consumption varies with climate, terrain, load and driving style.",
    })
    return path
