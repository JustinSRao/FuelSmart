"""Importer for the Natural Resources Canada Fuel Consumption Ratings.

NRCan publishes three differently-shaped CSVs. Each is handled separately
because the columns genuinely differ — not because the code was copied.

Quirks this module exists to absorb:

* Files are Windows-1252, not UTF-8 (accented model names break otherwise).
* One BEV header is literally ``"CO2 rating "`` with a trailing space.
* Fuel type is a single letter code (X/Z/D/E/N/B) rather than a word.
* Conventional hybrids are not a separate file — they live in the conventional
  file and are only identifiable from the model name suffix and transmission.
* The PHEV file packs electrical consumption inside a text field, e.g.
  ``"2.5 (22.3 kWh/100 km)"`` or ``"2.7 ([23.2 kWh + 0.1 L]/100 km)"``.
* Every file ends with several blank / footnote rows.
"""

from __future__ import annotations

import csv
import re
from typing import Iterator

from .model import Powertrain, VehicleRecord, tidy, to_float, to_int
from .units import imperial_mpg_to_l_per_100km, round_or_none

# NRCan single-letter fuel codes, from the published "understanding the tables" key.
FUEL_CODES = {
    "X": ("Regular gasoline", Powertrain.GASOLINE),
    "Z": ("Premium gasoline", Powertrain.GASOLINE),
    "D": ("Diesel", Powertrain.DIESEL),
    "E": ("E85 ethanol", Powertrain.GASOLINE),
    "N": ("Natural gas", Powertrain.OTHER),
    "B": ("Electricity", Powertrain.BEV),
}

# A conventional-file row is a hybrid when NRCan marks the model this way.
_HYBRID_MARKERS = re.compile(r"\bhybrid\b|\bhev\b", re.IGNORECASE)

# "2.5 (22.3 kWh/100 km)"  /  "2.7 ([23.2 kWh + 0.1 L]/100 km)"
_PHEV_KWH = re.compile(r"([0-9]+(?:\.[0-9]+)?)\s*kWh", re.IGNORECASE)


def _rows(path: str, encoding: str) -> Iterator[dict]:
    """Yield CSV rows, tolerating trailing blank/footnote lines and stray spaces."""
    with open(path, "r", encoding=encoding, newline="", errors="replace") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            return
        # Normalise header whitespace once (see the "CO2 rating " quirk).
        reader.fieldnames = [(name or "").strip() for name in reader.fieldnames]
        for row in reader:
            clean = {(k or "").strip(): v for k, v in row.items()}
            if to_int(clean.get("Model year")) is None:
                continue  # blank separator or footnote row
            yield clean


def _split_model(raw: str | None) -> tuple[str, str | None]:
    """Split NRCan's single ``Model`` field into a base model and a configuration.

    NRCan writes e.g. ``"Integra A-SPEC"``, ``"MDX SH-AWD Type S"``,
    ``"Model S (40 kWh)"``. There is no separate trim column, so the first word
    is treated as the model and the remainder as the configuration. This is a
    presentation split only — the full original string is preserved by joining
    them back together for display, and the id is built from both parts.
    """
    text = tidy(raw)
    if not text:
        return "", None
    parts = text.split(" ", 1)
    if len(parts) == 1:
        return parts[0], None
    return parts[0], tidy(parts[1])


def _common(row: dict, source_id: str, powertrain: str) -> VehicleRecord:
    model, configuration = _split_model(row.get("Model"))
    return VehicleRecord(
        country="CA",
        year=to_int(row.get("Model year")) or 0,
        make=tidy(row.get("Make")) or "",
        model=model,
        configuration=configuration,
        powertrain=powertrain,
        sourceId=source_id,
        vehicleClass=tidy(row.get("Vehicle class")),
        transmission=tidy(row.get("Transmission")),
        co2GramsPerKm=to_float(row.get("CO2 emissions (g/km)")),
        co2Rating=to_int(row.get("CO2 rating")),
        smogRating=to_int(row.get("Smog rating")),
    )


# --------------------------------------------------------------- conventional


def parse_conventional(path: str, source_id: str, encoding: str = "cp1252") -> list[VehicleRecord]:
    """Gasoline, diesel, ethanol and conventional-hybrid vehicles."""
    records: list[VehicleRecord] = []
    for row in _rows(path, encoding):
        code = (tidy(row.get("Fuel type")) or "").upper()[:1]
        description, powertrain = FUEL_CODES.get(code, (None, Powertrain.OTHER))

        # NRCan has no hybrid flag; the model name carries it.
        if powertrain == Powertrain.GASOLINE and _HYBRID_MARKERS.search(row.get("Model") or ""):
            powertrain = Powertrain.HYBRID

        record = _common(row, source_id, powertrain)
        record.fuelDescription = description
        record.engineSizeL = to_float(row.get("Engine size (L)"))
        record.cylinders = to_int(row.get("Cylinders"))
        record.cityLPer100Km = to_float(row.get("City (L/100 km)"))
        record.highwayLPer100Km = to_float(row.get("Highway (L/100 km)"))
        record.combinedLPer100Km = to_float(row.get("Combined (L/100 km)"))
        # NRCan's mpg column is Imperial gallons, not U.S. — kept for display only.
        record.officialCombinedMpgImperial = to_float(row.get("Combined (mpg)"))
        record.assign_id()
        records.append(record)
    return records


# ------------------------------------------------------------------------ BEV


def parse_bev(path: str, source_id: str, encoding: str = "cp1252") -> list[VehicleRecord]:
    """Battery-electric vehicles, 2012 onwards."""
    records: list[VehicleRecord] = []
    for row in _rows(path, encoding):
        record = _common(row, source_id, Powertrain.BEV)
        record.fuelDescription = "Electricity"
        # Official kWh/100 km is published directly. It is never derived from
        # battery capacity divided by advertised range.
        record.cityKwhPer100Km = to_float(row.get("City (kWh/100 km)"))
        record.highwayKwhPer100Km = to_float(row.get("Highway (kWh/100 km)"))
        record.combinedKwhPer100Km = to_float(row.get("Combined (kWh/100 km)"))
        record.electricRangeKm = to_float(row.get("Range (km)"))
        record.totalRangeKm = record.electricRangeKm
        record.rechargeHours = to_float(row.get("Recharge time (h)"))
        motor_kw = to_float(row.get("Motor (kW)"))
        if motor_kw:
            record.fuelDescription = "Electricity"
            record.drive = None
        record.assign_id()
        records.append(record)
    return records


# ----------------------------------------------------------------------- PHEV


def _phev_kwh_per_100km(raw: str | None) -> float | None:
    """Pull the kWh/100 km figure out of NRCan's combined-Le text field.

    The column holds a litres-equivalent number followed by the real electrical
    consumption in parentheses, in one of two shapes:

        "2.5 (22.3 kWh/100 km)"
        "2.7 ([23.2 kWh + 0.1 L]/100 km)"

    Only the kWh number is wanted; the Le figure is an equivalence that would
    understate a PHEV's true electricity use if treated as consumption.
    """
    text = tidy(raw)
    if not text:
        return None
    match = _PHEV_KWH.search(text)
    return float(match.group(1)) if match else None


def parse_phev(path: str, source_id: str, encoding: str = "cp1252") -> list[VehicleRecord]:
    """Plug-in hybrids: two energy sources, two ranges, one messy column."""
    records: list[VehicleRecord] = []
    for row in _rows(path, encoding):
        record = _common(row, source_id, Powertrain.PHEV)
        record.fuelDescription = "Electricity + gasoline"
        record.engineSizeL = to_float(row.get("Engine size (L)"))
        record.cylinders = to_int(row.get("Cylinders"))

        record.combinedKwhPer100Km = _phev_kwh_per_100km(row.get("Combined Le/100 km"))
        # In charge-sustaining (engine) mode NRCan publishes ordinary L/100 km.
        record.cityLPer100Km = to_float(row.get("City (L/100 km)"))
        record.highwayLPer100Km = to_float(row.get("Highway (L/100 km)"))
        record.combinedLPer100Km = to_float(row.get("Combined (L/100 km)"))

        # Range 1 is the electric-only range; Range 2 is the combustion range.
        record.electricRangeKm = to_float(row.get("Range 1 (km)"))
        record.totalRangeKm = to_float(row.get("Range 2 (km)"))
        record.rechargeHours = to_float(row.get("Recharge time (h)"))
        record.assign_id()
        records.append(record)
    return records


def finalize(records: list[VehicleRecord]) -> list[VehicleRecord]:
    """Round stored figures to the precision the publisher actually used."""
    for record in records:
        for name in (
            "cityLPer100Km", "highwayLPer100Km", "combinedLPer100Km",
            "cityKwhPer100Km", "highwayKwhPer100Km", "combinedKwhPer100Km",
        ):
            setattr(record, name, round_or_none(getattr(record, name), 2))
        for name in ("electricRangeKm", "totalRangeKm", "co2GramsPerKm"):
            setattr(record, name, round_or_none(getattr(record, name), 1))
    return records


__all__ = [
    "parse_conventional",
    "parse_bev",
    "parse_phev",
    "finalize",
    "imperial_mpg_to_l_per_100km",
]
