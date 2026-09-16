"""Importer for the U.S. DOE/EPA FuelEconomy.gov bulk vehicle dataset.

One file (``vehicles.csv``, ~22 MB, 50k rows, 1984 onwards, 84 columns) covers
every powertrain, so the work here is classification and unit normalization
rather than format juggling.

Column meanings that matter, from the FuelEconomy.gov field reference:

    city08/highway08/comb08   MPG for combustion; MPGe for electric
    cityE/highwayE/combE      kWh per 100 *miles* — the real electrical
                              consumption, published directly. This is what the
                              engine uses; MPGe is an equivalence, not a rate.
    atvType                   "EV", "Plug-in Hybrid", "Hybrid", "Diesel", ...
    fuelType1/fuelType2       primary / secondary energy source
    range / rangeA            electric range (EV) / alternate-fuel range (PHEV)
    charge240                 hours for a full charge on 240 V
    feScore / ghgScore        EPA 1-10 ratings
"""

from __future__ import annotations

import csv
import sys
from typing import Iterator

from .model import Powertrain, VehicleRecord, tidy, to_float, to_int
from .units import (
    grams_per_mile_to_grams_per_km,
    kwh_per_100mi_to_kwh_per_100km,
    miles_to_km,
    round_or_none,
    us_mpg_to_l_per_100km,
)

# Some description fields in this file are very long.
csv.field_size_limit(10_000_000)


def _rows(path: str, encoding: str = "utf-8") -> Iterator[dict]:
    with open(path, "r", encoding=encoding, newline="", errors="replace") as handle:
        yield from csv.DictReader(handle)


def _classify(row: dict) -> str:
    """Map EPA's several overlapping type columns onto one powertrain value."""
    atv = (tidy(row.get("atvType")) or "").lower()
    fuel1 = (tidy(row.get("fuelType1")) or "").lower()
    fuel2 = (tidy(row.get("fuelType2")) or "").lower()

    if atv == "ev" or fuel1 == "electricity":
        return Powertrain.BEV
    if "plug-in hybrid" in atv or (fuel2 == "electricity" and fuel1):
        return Powertrain.PHEV
    if "hybrid" in atv:
        return Powertrain.HYBRID
    if "diesel" in atv or "diesel" in fuel1:
        return Powertrain.DIESEL
    if "gasoline" in fuel1 or "ethanol" in fuel1 or fuel1 in ("midgrade", "premium", "regular"):
        return Powertrain.GASOLINE
    if fuel1:
        return Powertrain.OTHER
    return Powertrain.OTHER


def _transmission(row: dict) -> str | None:
    """Prefer the readable ``trany`` string, falling back to the descriptor."""
    return tidy(row.get("trany")) or tidy(row.get("trans_dscr"))


def parse_vehicles(
    path: str,
    source_id: str,
    min_year: int = 2000,
    encoding: str = "utf-8",
) -> list[VehicleRecord]:
    """Normalize EPA rows into the shared record.

    ``min_year`` trims the bundled database: EPA data reaches back to 1984, but
    shipping four decades of it costs app size for vehicles almost nobody is
    cross-shopping today. The pipeline flag is exposed so the cutoff is a
    deliberate, documented choice rather than a hidden constant.
    """
    records: list[VehicleRecord] = []
    for row in _rows(path, encoding):
        year = to_int(row.get("year"))
        if year is None or year < min_year:
            continue

        powertrain = _classify(row)
        record = VehicleRecord(
            country="US",
            year=year,
            make=tidy(row.get("make")) or "",
            model=tidy(row.get("baseModel")) or tidy(row.get("model")) or "",
            powertrain=powertrain,
            sourceId=source_id,
            vehicleClass=tidy(row.get("VClass")),
            transmission=_transmission(row),
            drive=tidy(row.get("drive")),
            engineSizeL=to_float(row.get("displ")),
            cylinders=to_int(row.get("cylinders")),
            fuelEconomyScore=to_int(row.get("feScore")),
        )

        # When baseModel was used above, the fuller "model" string carries the
        # configuration detail that distinguishes one listing from another.
        full_model = tidy(row.get("model")) or ""
        if record.model and full_model.lower().startswith(record.model.lower()):
            record.configuration = tidy(full_model[len(record.model):]) or tidy(row.get("eng_dscr"))
        else:
            record.configuration = tidy(row.get("eng_dscr"))

        fuel1 = tidy(row.get("fuelType1"))
        fuel2 = tidy(row.get("fuelType2"))
        record.fuelDescription = " + ".join(x for x in (fuel1, fuel2) if x) or tidy(row.get("fuelType"))

        # --- electricity: use the published kWh/100 mi, never MPGe ------------
        comb_e = to_float(row.get("combE"))
        if comb_e:
            record.officialCombinedKwhPer100Mi = comb_e
            record.combinedKwhPer100Km = kwh_per_100mi_to_kwh_per_100km(comb_e)
            record.cityKwhPer100Km = kwh_per_100mi_to_kwh_per_100km(to_float(row.get("cityE")))
            record.highwayKwhPer100Km = kwh_per_100mi_to_kwh_per_100km(to_float(row.get("highwayE")))

        # --- liquid fuel ------------------------------------------------------
        if powertrain != Powertrain.BEV:
            city_mpg = to_float(row.get("city08"))
            hwy_mpg = to_float(row.get("highway08"))
            comb_mpg = to_float(row.get("comb08"))
            record.officialCityMpgUS = city_mpg
            record.officialHighwayMpgUS = hwy_mpg
            record.officialCombinedMpgUS = comb_mpg
            record.cityLPer100Km = us_mpg_to_l_per_100km(city_mpg)
            record.highwayLPer100Km = us_mpg_to_l_per_100km(hwy_mpg)
            record.combinedLPer100Km = us_mpg_to_l_per_100km(comb_mpg)

        # --- range and charging ----------------------------------------------
        if powertrain == Powertrain.BEV:
            record.electricRangeKm = miles_to_km(to_float(row.get("range")))
            record.totalRangeKm = record.electricRangeKm
        elif powertrain == Powertrain.PHEV:
            # rangeA is the electric-drive range for a plug-in hybrid.
            record.electricRangeKm = miles_to_km(to_float(row.get("rangeA")))
            record.totalRangeKm = miles_to_km(to_float(row.get("range")))
        record.rechargeHours = to_float(row.get("charge240")) or None

        record.co2GramsPerKm = grams_per_mile_to_grams_per_km(to_float(row.get("co2TailpipeGpm")))
        ghg = to_int(row.get("ghgScore"))
        record.co2Rating = ghg if (ghg is not None and ghg > 0) else None

        record.assign_id()
        records.append(record)
    return records


def finalize(records: list[VehicleRecord]) -> list[VehicleRecord]:
    for record in records:
        for name in (
            "cityLPer100Km", "highwayLPer100Km", "combinedLPer100Km",
            "cityKwhPer100Km", "highwayKwhPer100Km", "combinedKwhPer100Km",
        ):
            setattr(record, name, round_or_none(getattr(record, name), 2))
        for name in ("electricRangeKm", "totalRangeKm", "co2GramsPerKm", "rechargeHours"):
            setattr(record, name, round_or_none(getattr(record, name), 1))
    return records


__all__ = ["parse_vehicles", "finalize"]
