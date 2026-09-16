import Testing
import Foundation
@testable import FuelSmartCore

@Suite("Export and import")
struct ExportImportTests {

    private func sample(name: String = "Commuter decision") -> SavedComparison {
        SavedComparison(name: name, scenario: Fixtures.hybridVersusElectric())
    }

    // MARK: - Round trip

    @Test("A saved comparison survives a round trip unchanged")
    func roundTrip() throws {
        let original = sample()
        let data = try ComparisonExporter.encode([original])
        let restored = try ComparisonImporter.decode(data)

        #expect(restored.count == 1)
        #expect(restored[0].name == original.name)
        #expect(restored[0].scenario.mode == original.scenario.mode)
        #expect(restored[0].scenario.region == original.scenario.region)
        #expect(restored[0].scenario.sideB.vehicle.id == original.scenario.sideB.vehicle.id)
        #expect(restored[0].scenario.driving.annualKilometres == original.scenario.driving.annualKilometres)
    }

    @Test("A round trip preserves the calculated result exactly")
    func roundTripPreservesResult() throws {
        let original = sample()
        let data = try ComparisonExporter.encode([original])
        let restored = try ComparisonImporter.decode(data)

        let engine = ScenarioCalculator()
        let before = engine.evaluate(original.scenario)
        let after = engine.evaluate(restored[0].scenario)

        #expect(abs(before.totalA - after.totalA) < 1e-9)
        #expect(abs(before.totalB - after.totalB) < 1e-9)
        #expect(before.breakEven.month == after.breakEven.month)
    }

    @Test("Several comparisons export and import together")
    func multipleComparisons() throws {
        let items = [sample(name: "First"), sample(name: "Second"), sample(name: "Third")]
        let data = try ComparisonExporter.encode(items)
        let restored = try ComparisonImporter.decode(data)
        #expect(restored.map(\.name) == ["First", "Second", "Third"])
    }

    @Test("The document carries a schema version as its first-class field")
    func schemaVersionIsWritten() throws {
        let data = try ComparisonExporter.encode([sample()])
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["schemaVersion"] as? Int == FuelSmartDocument.currentVersion)
    }

    @Test("Filenames are safe and dated")
    func filename() {
        let name = ComparisonExporter.suggestedFilename(
            for: [sample(name: "Commuter decision / 2026")],
            date: Date(timeIntervalSince1970: 1_788_000_000)
        )
        #expect(name.hasSuffix(".fuelsmart"))
        #expect(!name.contains("/"))
        #expect(name.contains("Commuter-decision-2026"))
    }

    // MARK: - Rejecting untrusted input

    @Test("Empty data is rejected")
    func emptyData() {
        #expect(throws: ImportError.empty) {
            try ComparisonImporter.decode(Data())
        }
    }

    @Test("Unrelated JSON is not mistaken for a FuelSmart file")
    func foreignJSON() {
        let data = Data(#"{"hello":"world"}"#.utf8)
        #expect(throws: ImportError.notFuelSmartData) {
            try ComparisonImporter.decode(data)
        }
    }

    @Test("A newer schema version is refused with a helpful message")
    func newerSchemaVersion() {
        let data = Data(#"{"schemaVersion":99,"exportedAt":"2026-01-01T00:00:00Z","comparisons":[]}"#.utf8)
        do {
            _ = try ComparisonImporter.decode(data)
            Issue.record("expected the import to fail")
        } catch let error as ImportError {
            guard case .unsupportedVersion(let found, _) = error else {
                Issue.record("expected unsupportedVersion, got \(error)")
                return
            }
            #expect(found == 99)
            #expect(error.message.contains("newer version"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("A structurally valid file with no comparisons is refused")
    func noComparisons() {
        let data = Data(#"{"schemaVersion":1,"exportedAt":"2026-01-01T00:00:00Z","comparisons":[]}"#.utf8)
        #expect(throws: ImportError.empty) {
            try ComparisonImporter.decode(data)
        }
    }

    @Test("Truncated JSON is reported as corrupt rather than crashing")
    func truncated() throws {
        let data = try ComparisonExporter.encode([sample()])
        let half = data.prefix(data.count / 2)
        #expect(throws: (any Error).self) {
            try ComparisonImporter.decode(Data(half))
        }
    }

    @Test("A negative price is rejected rather than charted")
    func negativePrice() throws {
        var item = sample()
        item.scenario.sideB.acquisition.purchasePrice = -5_000
        let data = try ComparisonExporter.encode([item])

        do {
            _ = try ComparisonImporter.decode(data)
            Issue.record("expected validation to reject a negative price")
        } catch let error as ImportError {
            guard case .validationFailed = error else {
                Issue.record("expected validationFailed, got \(error)")
                return
            }
        }
    }

    @Test("An absurd price is rejected")
    func absurdPrice() throws {
        var item = sample()
        item.scenario.sideA.acquisition.purchasePrice = 4_990_000
        let data = try ComparisonExporter.encode([item])
        #expect(throws: (any Error).self) {
            try ComparisonImporter.decode(data)
        }
    }

    @Test("A zero-length ownership period is rejected")
    func zeroHorizon() throws {
        var item = sample()
        item.scenario.horizon = .months(0)
        let data = try ComparisonExporter.encode([item])
        #expect(throws: (any Error).self) {
            try ComparisonImporter.decode(data)
        }
    }

    @Test("An absurdly long horizon is refused rather than allocating for it")
    func absurdHorizon() throws {
        var item = sample()
        item.scenario.horizon = .years(5_000)
        let data = try ComparisonExporter.encode([item])
        #expect(throws: (any Error).self) {
            try ComparisonImporter.decode(data)
        }
    }

    @Test("A blank name is repaired rather than rejected")
    func blankNameIsRepaired() throws {
        let item = SavedComparison(name: "   ", scenario: Fixtures.hybridVersusElectric())
        let data = try ComparisonExporter.encode([item])
        let restored = try ComparisonImporter.decode(data)
        #expect(restored[0].name == "Imported comparison")
    }

    @Test("One bad comparison does not discard the good ones beside it")
    func partialImport() throws {
        var bad = sample(name: "Broken")
        bad.scenario.sideA.acquisition.purchasePrice = -1
        let good = sample(name: "Fine")

        let data = try ComparisonExporter.encode([bad, good])
        let restored = try ComparisonImporter.decode(data)

        #expect(restored.count == 1)
        #expect(restored[0].name == "Fine")
    }

    // MARK: - Saved comparison behaviour

    @Test("Duplicating produces a new identity and a distinct name")
    func duplicate() {
        let original = sample()
        let copy = original.duplicated()
        #expect(copy.id != original.id)
        #expect(copy.name == "Commuter decision copy")
        #expect(copy.scenario == original.scenario)
    }

    @Test("Search matches name, vehicles and mode, ignoring case and accents")
    func search() {
        let item = sample()
        #expect(item.matches(searchText: ""))
        #expect(item.matches(searchText: "commuter"))
        #expect(item.matches(searchText: "Model 3"))
        #expect(item.matches(searchText: "buy vs buy"))
        #expect(!item.matches(searchText: "Silverado"))
    }

    @Test("Sorting honours each order")
    func sorting() {
        let early = SavedComparison(
            name: "Zebra", scenario: Fixtures.hybridVersusElectric(),
            dateCreated: .distantPast, dateModified: .distantPast
        )
        let late = SavedComparison(
            name: "Alpha", scenario: Fixtures.hybridVersusElectric(),
            dateCreated: .distantFuture, dateModified: .distantFuture
        )
        #expect(SavedComparison.sort([early, late], by: .dateModified).first?.name == "Alpha")
        #expect(SavedComparison.sort([early, late], by: .name).first?.name == "Alpha")
        #expect(SavedComparison.sort([late, early], by: .dateCreated).first?.name == "Alpha")
    }

    // MARK: - Settings

    @Test("U.S. defaults are stored in canonical units")
    func usDefaults() {
        let settings = UserSettings.unitedStatesDefaults
        #expect(settings.region == .unitedStates)
        // $3.30/gal ÷ 3.785411784 ≈ $0.8718/L
        #expect(abs(settings.gasolinePricePerLitre - 3.30 / 3.785411784) < 1e-9)
        // 12,000 mi ≈ 19,312.128 km
        #expect(abs(settings.annualKilometres - 19_312.128) < 1e-6)
    }

    @Test("Settings produce a usable energy and driving profile")
    func settingsProfiles() {
        let settings = UserSettings()
        #expect(settings.energyPriceProfile.blendedElectricityPricePerKWh > 0)
        #expect(settings.drivingProfile.annualKilometres == 18_000)
        // 80% home at $0.14, 20% public at $0.52 → $0.216
        #expect(abs(settings.energyPriceProfile.blendedElectricityPricePerKWh - 0.216) < 1e-9)
    }
}
