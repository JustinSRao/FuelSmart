#!/usr/bin/env python3
"""Tests for the data-ingestion pipeline.

    python Scripts/test_pipeline.py

Standard library ``unittest`` only. Parsing is tested against small inline
fixtures rather than the live government downloads, so a test can never fail
because Ottawa or the EPA republished a file. A separate, clearly-marked group
of checks runs against the real CSVs when they are present locally.
"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from fuelsmart_data import emit, epa, nrcan, units, validate  # noqa: E402
from fuelsmart_data.model import Powertrain, VehicleRecord, tidy, to_float  # noqa: E402


def write_csv(text: str, encoding: str = "cp1252") -> str:
    handle = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding=encoding, newline="")
    handle.write(text)
    handle.close()
    return handle.name


# --------------------------------------------------------------------- units


class UnitTests(unittest.TestCase):

    def test_us_mpg_round_trip(self):
        litres = units.us_mpg_to_l_per_100km(30)
        self.assertAlmostEqual(litres, 7.840486111, places=8)
        self.assertAlmostEqual(units.l_per_100km_to_us_mpg(litres), 30, places=9)

    def test_imperial_differs_from_us(self):
        # An Imperial gallon is larger than a U.S. one, so covering the same
        # number of miles on one means burning more fuel: the identical MPG
        # figure is the *worse* economy when it is Imperial. Confusing the two
        # would misstate NRCan's mpg column by about 20%.
        self.assertGreater(
            units.imperial_mpg_to_l_per_100km(30),
            units.us_mpg_to_l_per_100km(30),
        )

    def test_non_positive_economy_has_no_conversion(self):
        self.assertIsNone(units.us_mpg_to_l_per_100km(0))
        self.assertIsNone(units.us_mpg_to_l_per_100km(-4))

    def test_kwh_per_100_miles_to_km(self):
        # 24 kWh/100 mi over 160.9344 km is a smaller per-km figure.
        self.assertAlmostEqual(units.kwh_per_100mi_to_kwh_per_100km(24), 14.912908614, places=8)


# --------------------------------------------------------------------- model


class RecordTests(unittest.TestCase):

    def make(self, **overrides) -> VehicleRecord:
        base = dict(
            country="CA", year=2026, make="Tesla", model="Model 3",
            powertrain=Powertrain.BEV, sourceId="test",
            combinedKwhPer100Km=14.9,
        )
        base.update(overrides)
        record = VehicleRecord(**base)
        record.assign_id()
        return record

    def test_tidy_normalises_absent_values(self):
        for absent in ("", "  ", "n/a", "N/A", "-", "—", "null"):
            self.assertIsNone(tidy(absent))
        self.assertEqual(tidy("  Model   3 "), "Model 3")

    def test_to_float_handles_thousands_separators(self):
        self.assertEqual(to_float("1,234.5"), 1234.5)
        self.assertIsNone(to_float("not a number"))

    def test_id_is_stable_and_identity_derived(self):
        first = self.make()
        second = self.make()
        self.assertEqual(first.id, second.id)

        # A revised consumption figure must not change the id, or saved
        # comparisons would stop resolving after a dataset refresh.
        revised = self.make(combinedKwhPer100Km=15.4)
        self.assertEqual(first.id, revised.id)

        # A different configuration must change it.
        other = self.make(configuration="Long Range AWD")
        self.assertNotEqual(first.id, other.id)

    def test_id_is_namespaced_by_country_and_year(self):
        record = self.make()
        self.assertTrue(record.id.startswith("ca-2026-"))

    def test_bev_without_consumption_is_rejected(self):
        record = self.make(combinedKwhPer100Km=None)
        self.assertIn("BEV without electrical consumption", record.problems())

    def test_phev_needs_both_energy_figures(self):
        record = self.make(powertrain=Powertrain.PHEV, combinedLPer100Km=None)
        self.assertTrue(any("PHEV missing" in p for p in record.problems()))

    def test_absurd_consumption_is_rejected(self):
        record = self.make(combinedKwhPer100Km=900)
        self.assertTrue(any("out of range" in p for p in record.problems()))

    def test_compact_dict_omits_absent_fields(self):
        payload = self.make().to_compact_dict()
        self.assertNotIn("cityLPer100Km", payload)
        self.assertIn("combinedKwhPer100Km", payload)
        self.assertIn("id", payload)


# ---------------------------------------------------------------- NRCan CSVs


CONVENTIONAL_CSV = (
    "Model year,Make,Model,Vehicle class,Engine size (L),Cylinders,Transmission,Fuel type,"
    "City (L/100 km),Highway (L/100 km),Combined (L/100 km),Combined (mpg),"
    "CO2 emissions (g/km),CO2 rating,Smog rating\n"
    "2026,Acura,Integra A-SPEC,Full-size,1.5,4,AV7,Z,8.0,6.3,7.3,39,171,6,6\n"
    "2026,Toyota,Camry Hybrid LE,Mid-size,2.5,4,AV,X,4.9,5.1,5.0,56,117,8,7\n"
    "2026,Chevrolet,Silverado Diesel,Pickup truck: Standard,3.0,6,A10,D,11.2,8.9,10.2,28,272,4,5\n"
    "\n"
    "Footnote row that must be ignored\n"
)

BEV_CSV = (
    "Model year,Make,Model,Vehicle class,Motor (kW),Transmission,Fuel type,"
    "City (kWh/100 km),Highway (kWh/100 km),Combined (kWh/100 km),"
    "City (Le/100 km),Highway (Le/100 km),Combined (Le/100 km),Range (km),"
    "CO2 emissions (g/km),CO2 rating ,Smog rating,Recharge time (h)\n"
    "2026,Tesla,Model 3 RWD,Mid-size,208,A1,B,13.9,16.2,14.9,1.6,1.8,1.7,584,0,n/a,n/a,8\n"
)

PHEV_CSV = (
    "Model year,Make,Model,Vehicle class,Motor (kW),Engine size (L),Cylinders,Transmission,"
    "Fuel type 1,Combined Le/100 km,Range 1 (km),Recharge time (h),Fuel type 2,"
    "City (L/100 km),Highway (L/100 km),Combined (L/100 km),Range 2 (km),"
    "CO2 emissions (g/km),CO2 rating,Smog rating\n"
    "2026,Toyota,Prius Prime,Mid-size,120,2.0,4,AV,B,2.5 (22.3 kWh/100 km),72,4,X,"
    "4.6,5.0,4.8,960,44,n/a,n/a\n"
    "2026,Ford,Escape PHEV,Sport utility vehicle: Small,97,2.5,4,AV,B/X,"
    "2.7 ([23.2 kWh + 0.1 L]/100 km),61,3.5,X,5.8,6.5,6.1,832,80,n/a,n/a\n"
)


class NRCanTests(unittest.TestCase):

    def test_conventional_parsing_and_fuel_codes(self):
        records = nrcan.parse_conventional(write_csv(CONVENTIONAL_CSV), "nrcan-conventional")
        self.assertEqual(len(records), 3)

        integra, camry, silverado = records
        self.assertEqual(integra.make, "Acura")
        self.assertEqual(integra.model, "Integra")
        self.assertEqual(integra.configuration, "A-SPEC")
        self.assertEqual(integra.fuelDescription, "Premium gasoline")
        self.assertEqual(integra.powertrain, Powertrain.GASOLINE)
        self.assertEqual(integra.combinedLPer100Km, 7.3)
        # NRCan's mpg column is Imperial, kept only for display.
        self.assertEqual(integra.officialCombinedMpgImperial, 39)

        # A hybrid is only identifiable from the model name in this file.
        self.assertEqual(camry.powertrain, Powertrain.HYBRID)
        self.assertEqual(silverado.powertrain, Powertrain.DIESEL)

    def test_blank_and_footnote_rows_are_skipped(self):
        records = nrcan.parse_conventional(write_csv(CONVENTIONAL_CSV), "nrcan-conventional")
        self.assertTrue(all(r.year == 2026 for r in records))

    def test_bev_parsing_tolerates_trailing_space_in_header(self):
        records = nrcan.parse_bev(write_csv(BEV_CSV), "nrcan-bev")
        self.assertEqual(len(records), 1)
        record = records[0]
        self.assertEqual(record.powertrain, Powertrain.BEV)
        self.assertEqual(record.combinedKwhPer100Km, 14.9)
        self.assertEqual(record.electricRangeKm, 584)
        # "CO2 rating " carries a trailing space in the real file, and its value
        # is "n/a" here, which must normalise to absent rather than crash.
        self.assertIsNone(record.co2Rating)

    def test_phev_extracts_kwh_from_the_packed_column(self):
        records = nrcan.parse_phev(write_csv(PHEV_CSV), "nrcan-phev")
        prius, escape = records

        # "2.5 (22.3 kWh/100 km)" -> 22.3, not 2.5
        self.assertEqual(prius.combinedKwhPer100Km, 22.3)
        # "2.7 ([23.2 kWh + 0.1 L]/100 km)" -> 23.2
        self.assertEqual(escape.combinedKwhPer100Km, 23.2)

        # Both energy figures survive, and the two ranges are not confused.
        self.assertEqual(prius.combinedLPer100Km, 4.8)
        self.assertEqual(prius.electricRangeKm, 72)
        self.assertEqual(prius.totalRangeKm, 960)

    def test_phev_kwh_extraction_returns_none_when_absent(self):
        self.assertIsNone(nrcan._phev_kwh_per_100km("2.5"))
        self.assertIsNone(nrcan._phev_kwh_per_100km(None))
        self.assertIsNone(nrcan._phev_kwh_per_100km("n/a"))


# ------------------------------------------------------------------ EPA CSV


EPA_CSV_HEADER = (
    "year,make,model,baseModel,VClass,trany,trans_dscr,drive,displ,cylinders,"
    "fuelType,fuelType1,fuelType2,atvType,eng_dscr,"
    "city08,highway08,comb08,cityE,highwayE,combE,"
    "range,rangeA,charge240,co2TailpipeGpm,feScore,ghgScore\n"
)
EPA_CSV = EPA_CSV_HEADER + (
    "2026,Tesla,Model 3 RWD,Model 3,Midsize Cars,Automatic (A1),,Rear-Wheel Drive,,,"
    "Electricity,Electricity,,EV,,132,120,126,25.6,28.1,26.7,"
    "363,,8.3,0.0,10,10\n"
    "2026,Toyota,Camry Hybrid,Camry,Midsize Cars,Automatic (AV-S6),,Front-Wheel Drive,2.5,4,"
    "Regular Gasoline,Regular Gasoline,,Hybrid,,53,50,51,,,,"
    ",,,171.0,9,9\n"
    "2026,Toyota,Prius Prime,Prius,Midsize Cars,Automatic (AV-S6),,Front-Wheel Drive,2.0,4,"
    "Regular Gas and Electricity,Regular Gasoline,Electricity,Plug-in Hybrid,,"
    "52,49,50,,,25.0,600,44,4.0,155.0,9,9\n"
    "1998,Ford,Taurus,Taurus,Midsize Cars,Automatic 4-spd,,Front-Wheel Drive,3.0,6,"
    "Regular Gasoline,Regular Gasoline,,,,18,26,21,,,,"
    ",,,423.0,,\n"
)


class EPATests(unittest.TestCase):

    def parse(self, min_year=2000):
        return epa.parse_vehicles(write_csv(EPA_CSV, encoding="utf-8"), "epa-vehicles", min_year=min_year)

    def test_min_year_trims_the_bundle(self):
        self.assertEqual(len(self.parse(min_year=2000)), 3)
        self.assertEqual(len(self.parse(min_year=1990)), 4)

    def test_classification(self):
        tesla, camry, prius = self.parse()
        self.assertEqual(tesla.powertrain, Powertrain.BEV)
        self.assertEqual(camry.powertrain, Powertrain.HYBRID)
        self.assertEqual(prius.powertrain, Powertrain.PHEV)

    def test_electricity_uses_published_kwh_not_mpge(self):
        tesla = self.parse()[0]
        # 26.7 kWh/100 mi -> 16.59 kWh/100 km. MPGe (126) is never consulted.
        self.assertAlmostEqual(tesla.combinedKwhPer100Km, 26.7 / 1.609344, places=2)
        self.assertEqual(tesla.officialCombinedKwhPer100Mi, 26.7)

    def test_mpg_normalised_to_metric_with_official_values_kept(self):
        camry = self.parse()[1]
        self.assertAlmostEqual(camry.combinedLPer100Km, 235.214583 / 51, places=2)
        self.assertEqual(camry.officialCombinedMpgUS, 51)
        self.assertEqual(camry.officialCityMpgUS, 53)

    def test_bev_has_no_fuel_figures(self):
        tesla = self.parse()[0]
        self.assertIsNone(tesla.combinedLPer100Km)

    def test_phev_carries_both_ranges(self):
        prius = self.parse()[2]
        self.assertIsNotNone(prius.combinedLPer100Km)
        self.assertIsNotNone(prius.combinedKwhPer100Km)
        # rangeA (44 mi) is the electric range; range (600 mi) is the total.
        self.assertAlmostEqual(prius.electricRangeKm, 44 * 1.609344, places=2)
        self.assertAlmostEqual(prius.totalRangeKm, 600 * 1.609344, places=2)

    def test_base_model_and_configuration_are_split(self):
        tesla = self.parse()[0]
        self.assertEqual(tesla.model, "Model 3")
        self.assertEqual(tesla.configuration, "RWD")

    def test_zero_ghg_score_is_treated_as_absent(self):
        # The 1998 row has empty scores; absent must not become 0.
        old = self.parse(min_year=1990)[-1]
        self.assertIsNone(old.co2Rating)


# ---------------------------------------------------------------- validation


class ValidationTests(unittest.TestCase):

    def record(self, **overrides) -> VehicleRecord:
        base = dict(country="CA", year=2026, make="A", model="B",
                    powertrain=Powertrain.GASOLINE, sourceId="t", combinedLPer100Km=8.0)
        base.update(overrides)
        record = VehicleRecord(**base)
        record.assign_id()
        return record

    def test_filter_splits_good_from_bad(self):
        good, bad = validate.filter_valid([
            self.record(),
            self.record(combinedLPer100Km=None),
        ])
        self.assertEqual(len(good), 1)
        self.assertEqual(len(bad), 1)

    def test_deduplicate_keeps_the_first_occurrence(self):
        first = self.record(combinedLPer100Km=8.0)
        second = self.record(combinedLPer100Km=9.0)
        self.assertEqual(first.id, second.id)

        unique, duplicates = validate.deduplicate([first, second])
        self.assertEqual(duplicates, 1)
        self.assertEqual(len(unique), 1)
        self.assertEqual(unique[0].combinedLPer100Km, 8.0)

    def test_dataset_gate_rejects_a_thin_dataset(self):
        with self.assertRaises(validate.DatasetValidationError):
            validate.assert_dataset_sane("CA", [self.record()], min_records=100)

    def test_dataset_gate_requires_every_powertrain(self):
        records = [self.record(make=f"M{i}") for i in range(200)]
        with self.assertRaises(validate.DatasetValidationError) as caught:
            validate.assert_dataset_sane("CA", records, min_records=10)
        self.assertIn("no bev records", str(caught.exception))

    def test_a_single_bad_government_row_never_fails_the_build(self):
        records = [self.record(make=f"M{i}") for i in range(50)]
        records.append(self.record(make="Broken", combinedLPer100Km=None))
        good, bad = validate.filter_valid(records)
        self.assertEqual(len(good), 50)
        self.assertEqual(len(bad), 1)


# -------------------------------------------------------------------- output


class EmitTests(unittest.TestCase):

    def records(self):
        made = []
        for index, (make, model, powertrain) in enumerate([
            ("Tesla", "Model 3", Powertrain.BEV),
            ("Tesla", "Model Y", Powertrain.BEV),
            ("Toyota", "Camry", Powertrain.HYBRID),
        ]):
            record = VehicleRecord(
                country="CA", year=2026 - (index % 2), make=make, model=model,
                powertrain=powertrain, sourceId="t",
                combinedKwhPer100Km=15.0 if powertrain == Powertrain.BEV else None,
                combinedLPer100Km=None if powertrain == Powertrain.BEV else 5.0,
            )
            record.assign_id()
            made.append(record)
        return made

    def test_catalog_is_a_sorted_year_make_model_tree(self):
        catalog = emit.build_catalog(self.records())
        years = [entry["year"] for entry in catalog["years"]]
        self.assertEqual(years, sorted(years, reverse=True))

        first = catalog["years"][0]
        self.assertEqual(first["count"], sum(m["count"] for m in first["makes"]))
        makes = [m["make"] for m in first["makes"]]
        self.assertEqual(makes, sorted(makes, key=str.casefold))

    def test_catalog_carries_ids_so_browsing_never_scans_the_records_file(self):
        catalog = emit.build_catalog(self.records())
        every_id = [
            vehicle_id
            for year in catalog["years"]
            for make in year["makes"]
            for model in make["models"]
            for vehicle_id in model["ids"]
        ]
        self.assertEqual(len(every_id), 3)

    def test_emit_writes_files_with_checksums(self):
        with tempfile.TemporaryDirectory() as directory:
            summary = emit.emit_country(directory, "CA", self.records(), [], "2026.9")
            for role in ("records", "catalog"):
                info = summary["files"][role]
                self.assertTrue(os.path.exists(os.path.join(directory, info["name"])))
                self.assertEqual(len(info["sha256"]), 64)
                self.assertGreater(info["bytes"], 0)
            self.assertEqual(summary["recordCount"], 3)


# ------------------------------------------- checks against the real datasets


@unittest.skipUnless(
    os.path.exists(os.path.join(REPO, "GeneratedData", "manifest.json")),
    "generated data not present; run Scripts/build_dataset.py first",
)
class GeneratedOutputTests(unittest.TestCase):
    """Sanity checks on real generated output, when it exists."""

    @classmethod
    def setUpClass(cls):
        import json
        with open(os.path.join(REPO, "GeneratedData", "manifest.json"), encoding="utf-8") as handle:
            cls.manifest = json.load(handle)

    def test_both_countries_present_with_attribution(self):
        countries = {entry["country"] for entry in self.manifest["countries"]}
        self.assertEqual(countries, {"CA", "US"})
        self.assertIn("Natural Resources Canada", self.manifest["attribution"]["CA"])
        self.assertIn("Department of Energy", self.manifest["attribution"]["US"])

    def test_every_record_set_carries_a_source(self):
        for country in self.manifest["countries"]:
            self.assertTrue(country["sources"], f"{country['country']} has no source metadata")
            for source in country["sources"]:
                for field in ("publisher", "dataset", "licence", "licenceUrl"):
                    self.assertTrue(source.get(field), f"{source['id']} missing {field}")

    def test_every_powertrain_is_represented(self):
        for country in self.manifest["countries"]:
            counts = country["powertrainCounts"]
            for required in ("gasoline", "bev", "phev"):
                self.assertGreater(counts.get(required, 0), 0, f"{country['country']} has no {required}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
