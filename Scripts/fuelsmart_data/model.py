"""The normalized vehicle record shared by every country's importer.

One record is one *configuration* of one model year — the granularity the
governments publish and the granularity a user must pick before a comparison
means anything (a Model 3 RWD and a Model 3 Performance are not interchangeable).

Missing data stays missing. A field that the source did not publish is ``None``
and is omitted from the emitted JSON entirely, so the app can render "—" rather
than a fabricated number.
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, field, asdict
from typing import Optional


class Powertrain:
    GASOLINE = "gasoline"
    DIESEL = "diesel"
    HYBRID = "hybrid"
    PHEV = "phev"
    BEV = "bev"
    OTHER = "other"

    ALL = {GASOLINE, DIESEL, HYBRID, PHEV, BEV, OTHER}


_WHITESPACE = re.compile(r"\s+")


def tidy(value: Optional[str]) -> Optional[str]:
    """Collapse whitespace and drop the several spellings of 'no value'."""
    if value is None:
        return None
    text = _WHITESPACE.sub(" ", str(value)).strip()
    if text.lower() in ("", "n/a", "na", "-", "—", "null", "none"):
        return None
    return text


def to_float(value) -> Optional[float]:
    text = tidy(value if isinstance(value, str) else (None if value is None else str(value)))
    if text is None:
        return None
    text = text.replace(",", "")
    try:
        number = float(text)
    except ValueError:
        return None
    # Government CSVs occasionally carry 0 as a stand-in for "not measured".
    # Zero consumption or zero range is never physically meaningful, so callers
    # that care about that distinction filter it; CO2 legitimately can be 0.
    return number


def to_int(value) -> Optional[int]:
    number = to_float(value)
    return None if number is None else int(round(number))


@dataclass
class VehicleRecord:
    """A single normalized vehicle configuration.

    Consumption fields are canonical metric (L/100 km, kWh/100 km, km) regardless
    of country. ``official*`` fields preserve the publisher's own figures so the
    detail screen can show exactly what the government printed.
    """

    country: str                       # "CA" | "US"
    year: int
    make: str
    model: str
    powertrain: str
    sourceId: str

    configuration: Optional[str] = None
    vehicleClass: Optional[str] = None
    fuelDescription: Optional[str] = None
    engineSizeL: Optional[float] = None
    cylinders: Optional[int] = None
    transmission: Optional[str] = None
    drive: Optional[str] = None

    # Liquid fuel, canonical L/100 km
    cityLPer100Km: Optional[float] = None
    highwayLPer100Km: Optional[float] = None
    combinedLPer100Km: Optional[float] = None

    # Electricity, canonical kWh/100 km
    cityKwhPer100Km: Optional[float] = None
    highwayKwhPer100Km: Optional[float] = None
    combinedKwhPer100Km: Optional[float] = None

    # Range and charging
    electricRangeKm: Optional[float] = None
    totalRangeKm: Optional[float] = None
    rechargeHours: Optional[float] = None

    # Emissions and government ratings
    co2GramsPerKm: Optional[float] = None
    co2Rating: Optional[int] = None
    smogRating: Optional[int] = None
    fuelEconomyScore: Optional[int] = None

    # Publisher's own figures, for faithful display
    officialCombinedMpgImperial: Optional[float] = None
    officialCityMpgUS: Optional[float] = None
    officialHighwayMpgUS: Optional[float] = None
    officialCombinedMpgUS: Optional[float] = None
    officialCombinedKwhPer100Mi: Optional[float] = None

    id: str = field(default="", init=False)

    # ---------------------------------------------------------------- identity

    def assign_id(self) -> None:
        """Stable, content-derived id.

        Built from the identifying tuple only (never from consumption figures) so
        that a saved comparison keeps resolving to the same vehicle when the
        government revises a rating in a later dataset release.
        """
        parts = [
            self.country,
            str(self.year),
            (self.make or "").lower(),
            (self.model or "").lower(),
            (self.configuration or "").lower(),
            (self.transmission or "").lower(),
            self.powertrain,
        ]
        digest = hashlib.sha1("|".join(parts).encode("utf-8")).hexdigest()[:12]
        self.id = f"{self.country.lower()}-{self.year}-{digest}"

    # -------------------------------------------------------------- validation

    def problems(self) -> list[str]:
        """Return the reasons this record is unusable, empty if it is fine."""
        issues: list[str] = []
        if self.country not in ("CA", "US"):
            issues.append(f"unknown country {self.country!r}")
        if not (1980 <= int(self.year) <= 2100):
            issues.append(f"implausible model year {self.year!r}")
        if not self.make:
            issues.append("missing make")
        if not self.model:
            issues.append("missing model")
        if self.powertrain not in Powertrain.ALL:
            issues.append(f"unknown powertrain {self.powertrain!r}")

        has_fuel = self.combinedLPer100Km is not None
        has_electric = self.combinedKwhPer100Km is not None
        if not has_fuel and not has_electric:
            issues.append("no combined consumption figure of any kind")

        if self.powertrain == Powertrain.BEV and not has_electric:
            issues.append("BEV without electrical consumption")
        if self.powertrain == Powertrain.PHEV and not (has_fuel and has_electric):
            issues.append("PHEV missing one of its two energy figures")
        if self.powertrain in (Powertrain.GASOLINE, Powertrain.DIESEL, Powertrain.HYBRID) and not has_fuel:
            issues.append("combustion vehicle without fuel consumption")

        for name, value, ceiling in (
            ("combinedLPer100Km", self.combinedLPer100Km, 60.0),
            ("combinedKwhPer100Km", self.combinedKwhPer100Km, 100.0),
        ):
            if value is not None and not (0 < value < ceiling):
                issues.append(f"{name} out of range: {value}")

        return issues

    # ------------------------------------------------------------------ output

    def to_compact_dict(self) -> dict:
        """Drop every absent field so the bundled JSON stays small."""
        raw = asdict(self)
        raw["id"] = self.id
        return {key: value for key, value in raw.items() if value is not None and value != ""}
