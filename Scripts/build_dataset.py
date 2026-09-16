#!/usr/bin/env python3
"""Parse, normalize, validate and emit the bundled FuelSmart vehicle database.

    python Scripts/build_dataset.py [--in DataSources] [--out GeneratedData]
                                    [--us-min-year 2000] [--ca-min-year 2000]

Reads the raw government CSVs downloaded by ``fetch_datasets.py`` and writes the
compact JSON the app bundles. The build fails rather than emitting output it
cannot vouch for — see ``fuelsmart_data/validate.py``.

Newest source files are processed first so that when the same configuration
appears in several NRCan releases, the most recent publication is the one kept.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from fuelsmart_data import emit, epa, nrcan, validate  # noqa: E402
from fuelsmart_data.model import VehicleRecord  # noqa: E402


def _existing(directory: str, url: str) -> str | None:
    path = os.path.join(directory, url.rsplit("/", 1)[-1])
    return path if os.path.exists(path) else None


def load_sources() -> dict:
    with open(os.path.join(HERE, "sources.json"), encoding="utf-8") as handle:
        return json.load(handle)


def source_attribution(source: dict) -> dict:
    return {
        "id": source["id"],
        "publisher": source["publisher"],
        "dataset": source["dataset"],
        "licence": source["licence"],
        "licenceUrl": source["licenceUrl"],
        "landingPage": source["landingPage"],
    }


def build_canada(config: dict, in_dir: str, min_year: int) -> tuple[list[VehicleRecord], list[dict]]:
    records: list[VehicleRecord] = []
    attributions: list[dict] = []

    for source in config["sources"]:
        if source["country"] != "CA":
            continue
        attributions.append(source_attribution(source))
        parser = {
            "conventional": nrcan.parse_conventional,
            "bev": nrcan.parse_bev,
            "phev": nrcan.parse_phev,
        }[source["kind"]]

        for url in source["urls"]:
            path = _existing(in_dir, url)
            if path is None:
                print(f"  skip  {source['id']}: {url.rsplit('/', 1)[-1]} not downloaded")
                continue
            parsed = parser(path, source["id"], source["encoding"])
            print(f"  read  {source['id']:<20} {os.path.basename(path):<52} {len(parsed):>6} rows")
            records.extend(parsed)

    nrcan.finalize(records)
    records = [r for r in records if r.year >= min_year]
    return records, attributions


def build_united_states(config: dict, in_dir: str, min_year: int) -> tuple[list[VehicleRecord], list[dict]]:
    records: list[VehicleRecord] = []
    attributions: list[dict] = []

    for source in config["sources"]:
        if source["country"] != "US":
            continue
        attributions.append(source_attribution(source))
        for url in source["urls"]:
            path = _existing(in_dir, url)
            if path is None:
                print(f"  skip  {source['id']}: {url.rsplit('/', 1)[-1]} not downloaded")
                continue
            parsed = epa.parse_vehicles(path, source["id"], min_year=min_year, encoding=source["encoding"])
            print(f"  read  {source['id']:<20} {os.path.basename(path):<52} {len(parsed):>6} rows")
            records.extend(parsed)

    epa.finalize(records)
    return records, attributions


def process(country: str, records: list[VehicleRecord], min_records: int) -> list[VehicleRecord]:
    """Reject bad rows, drop duplicates, then gate the whole dataset."""
    good, bad = validate.filter_valid(records)
    print(f"  {country}: {validate.summarize_rejections(bad)}")

    # Newest model years first, so deduplication keeps the latest publication.
    good.sort(key=lambda r: (-r.year, r.make.casefold(), r.model.casefold()))
    unique, duplicates = validate.deduplicate(good)
    print(f"  {country}: {duplicates} duplicate records collapsed")

    validate.assert_dataset_sane(country, unique, min_records)
    print(f"  {country}: {len(unique)} records validated")
    return unique


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--in", dest="in_dir", default=os.path.join(REPO, "DataSources"))
    parser.add_argument("--out", dest="out_dir", default=os.path.join(REPO, "GeneratedData"))
    parser.add_argument("--ca-min-year", type=int, default=2000)
    parser.add_argument("--us-min-year", type=int, default=2000)
    parser.add_argument("--min-records-ca", type=int, default=1000)
    parser.add_argument("--min-records-us", type=int, default=5000)
    args = parser.parse_args()

    config = load_sources()
    dataset_version = f"{date.today().year}.{date.today().month}"

    print("Canada")
    ca_records, ca_sources = build_canada(config, args.in_dir, args.ca_min_year)
    ca_records = process("CA", ca_records, args.min_records_ca)

    print("United States")
    us_records, us_sources = build_united_states(config, args.in_dir, args.us_min_year)
    us_records = process("US", us_records, args.min_records_us)

    print("Emitting")
    countries = [
        emit.emit_country(args.out_dir, "CA", ca_records, ca_sources, dataset_version),
        emit.emit_country(args.out_dir, "US", us_records, us_sources, dataset_version),
    ]
    manifest = emit.emit_manifest(args.out_dir, countries, dataset_version)

    total = 0
    for country in countries:
        for role, info in country["files"].items():
            total += info["bytes"]
            print(f"  {info['name']:<22} {info['bytes']:>10,} bytes  sha256 {info['sha256'][:16]}…")
    print(f"  {'manifest.json':<22} {os.path.getsize(manifest):>10,} bytes")
    print(f"\n  bundled total: {total/1_048_576:.1f} MiB  (dataset version {dataset_version})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
