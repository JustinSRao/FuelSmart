"""Unit conversions used by the ingestion pipeline.

The bundled dataset stores one canonical set of units so the Swift calculation
engine never needs a per-country code path:

    liquid fuel consumption  ->  L/100 km
    electrical consumption   ->  kWh/100 km
    distance                 ->  km

U.S. source figures (MPG, kWh/100 mi) are converted here, and the original
official numbers are carried alongside for display so that a U.S. user still
sees the exact figure the EPA published rather than a round-tripped one.

These constants are exact definitions, not approximations.
"""

from __future__ import annotations

KM_PER_MILE = 1.609344
LITRES_PER_US_GALLON = 3.785411784
LITRES_PER_IMPERIAL_GALLON = 4.54609

# 100 km expressed in US gallons per mile terms: 100 * L/gal / km/mi
_US_MPG_TO_L100KM = 100.0 * LITRES_PER_US_GALLON / KM_PER_MILE  # ~235.2145
_IMP_MPG_TO_L100KM = 100.0 * LITRES_PER_IMPERIAL_GALLON / KM_PER_MILE  # ~282.4809


def us_mpg_to_l_per_100km(mpg: float | None) -> float | None:
    """Convert U.S. miles-per-gallon to litres per 100 km."""
    if mpg is None or mpg <= 0:
        return None
    return _US_MPG_TO_L100KM / mpg


def l_per_100km_to_us_mpg(l100: float | None) -> float | None:
    if l100 is None or l100 <= 0:
        return None
    return _US_MPG_TO_L100KM / l100


def imperial_mpg_to_l_per_100km(mpg: float | None) -> float | None:
    """Convert Imperial (Canadian) miles-per-gallon to litres per 100 km."""
    if mpg is None or mpg <= 0:
        return None
    return _IMP_MPG_TO_L100KM / mpg


def kwh_per_100mi_to_kwh_per_100km(kwh100mi: float | None) -> float | None:
    """EPA publishes electrical consumption per 100 miles."""
    if kwh100mi is None or kwh100mi <= 0:
        return None
    return kwh100mi / KM_PER_MILE


def miles_to_km(miles: float | None) -> float | None:
    if miles is None or miles <= 0:
        return None
    return miles * KM_PER_MILE


def grams_per_mile_to_grams_per_km(gpm: float | None) -> float | None:
    if gpm is None or gpm < 0:
        return None
    return gpm / KM_PER_MILE


def round_or_none(value: float | None, places: int) -> float | None:
    """Round for storage only. Intermediate calculation values are never rounded."""
    if value is None:
        return None
    return round(value, places)
