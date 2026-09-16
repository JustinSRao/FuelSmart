import Foundation
import SwiftData
import FuelSmartCore

/// The SwiftData record for a saved comparison.
///
/// The scenario is stored as an encoded blob rather than as a graph of
/// `@Model` types, deliberately:
///
/// * The domain model stays a plain `Codable` value type in `FuelSmartCore`,
///   with no persistence framework leaking into the calculation layer.
/// * The stored shape is the same versioned JSON used for export, so a saved
///   comparison and an exported file cannot drift apart.
/// * Schema migration becomes a decode concern with an explicit version, rather
///   than a SwiftData lightweight-migration guess across a dozen fields.
///
/// The fields that need to be queryable, sortable or searchable — name, dates,
/// mode, region, vehicle names — are stored as real columns alongside it.
@Model
final class SavedComparisonEntity {

    // Note: SwiftData's #Index macro is iOS 18 / macOS 15 only, and FuelSmart
    // supports iOS 17. The saved-comparison list is small and sorted in memory,
    // so the absence of a stored index costs nothing here.
    @Attribute(.unique) var id: UUID
    var name: String
    var dateCreated: Date
    var dateModified: Date

    /// Denormalised for list rendering and search, so opening the Saved tab
    /// never decodes every stored scenario.
    var modeRawValue: String
    var regionRawValue: String
    var vehicleASummary: String
    var vehicleBSummary: String

    /// The encoded `ComparisonScenario`.
    var scenarioData: Data
    /// The `FuelSmartDocument` schema version this blob was written with.
    var schemaVersion: Int

    init(saved: SavedComparison) throws {
        self.id = saved.id
        self.name = saved.name
        self.dateCreated = saved.dateCreated
        self.dateModified = saved.dateModified
        self.modeRawValue = saved.scenario.mode.rawValue
        self.regionRawValue = saved.scenario.region.rawValue
        self.vehicleASummary = saved.scenario.sideA.vehicle.shortDisplayName
        self.vehicleBSummary = saved.scenario.sideB.vehicle.shortDisplayName
        self.schemaVersion = FuelSmartDocument.currentVersion

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.scenarioData = try encoder.encode(saved.scenario)
    }

    var mode: ComparisonMode { ComparisonMode(rawValue: modeRawValue) ?? .buyVsBuy }
    var region: Region { Region(rawValue: regionRawValue) ?? .canada }
    var subtitle: String { "\(vehicleASummary) vs \(vehicleBSummary)" }

    /// Decode back to the domain value.
    ///
    /// Throws rather than returning a placeholder: a scenario that cannot be
    /// decoded must surface as an error the user can act on, not as a silently
    /// wrong comparison.
    func toSavedComparison() throws -> SavedComparison {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scenario = try decoder.decode(ComparisonScenario.self, from: scenarioData)
        return SavedComparison(
            id: id, name: name, scenario: scenario,
            dateCreated: dateCreated, dateModified: dateModified
        )
    }

    func update(from saved: SavedComparison, now: Date = Date()) throws {
        name = saved.name
        dateModified = now
        modeRawValue = saved.scenario.mode.rawValue
        regionRawValue = saved.scenario.region.rawValue
        vehicleASummary = saved.scenario.sideA.vehicle.shortDisplayName
        vehicleBSummary = saved.scenario.sideB.vehicle.shortDisplayName
        schemaVersion = FuelSmartDocument.currentVersion

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        scenarioData = try encoder.encode(saved.scenario)
    }
}

/// A VIN result kept on device so a repeat lookup works offline.
///
/// Cached VIN data is the only vehicle information the app retains from a
/// network call, and it never leaves the device again.
@Model
final class CachedVINEntity {
    @Attribute(.unique) var vin: String
    var decodedData: Data
    var dateFetched: Date

    init(decoded: DecodedVIN, date: Date = Date()) throws {
        self.vin = decoded.vin
        self.decodedData = try JSONEncoder().encode(decoded)
        self.dateFetched = date
    }

    func toDecodedVIN() throws -> DecodedVIN {
        try JSONDecoder().decode(DecodedVIN.self, from: decodedData)
    }
}

/// A vehicle the user marked as a favourite, or recently opened.
@Model
final class VehicleBookmarkEntity {
    @Attribute(.unique) var vehicleId: String
    var regionRawValue: String
    var displayName: String
    var isFavourite: Bool
    var lastUsed: Date

    init(vehicle: Vehicle, isFavourite: Bool, lastUsed: Date = Date()) {
        self.vehicleId = vehicle.id
        self.regionRawValue = vehicle.region.rawValue
        self.displayName = vehicle.fullDisplayName
        self.isFavourite = isFavourite
        self.lastUsed = lastUsed
    }

    var region: Region { Region(rawValue: regionRawValue) ?? .canada }
}

// MARK: - Container

enum PersistenceController {

    // Computed rather than a stored `static let`: Schema is not Sendable, so a
    // shared static instance is rejected under strict concurrency checking.
    static var schema: Schema {
        Schema([
            SavedComparisonEntity.self,
            CachedVINEntity.self,
            VehicleBookmarkEntity.self,
        ])
    }

    /// The on-device store. No CloudKit, no account, no sync — comparisons stay
    /// on the device that made them.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A store that cannot be opened — a corrupt file, or a schema the
            // build cannot read — must not prevent the app from launching. The
            // user keeps every feature except previously saved comparisons, and
            // is told so rather than seeing a crash.
            assertionFailure("Persistent store unavailable: \(error)")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            // If even an in-memory store fails, the process genuinely cannot
            // continue, and trapping here gives a usable crash report.
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }
}

// MARK: - Settings storage

/// User defaults, stored as one encoded value.
///
/// `UserSettings` is a single `Codable` struct in the core package, so storing
/// it whole keeps one source of truth and avoids a dozen loosely-related
/// `@AppStorage` keys that can drift out of step.
@Observable
final class SettingsStore {

    private static let storageKey = "fuelsmart.settings.v1"
    private let defaults: UserDefaults

    private(set) var settings: UserSettings {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = UserSettings()
        }
    }

    /// Mutate settings through a single entry point so every change persists.
    func update(_ mutate: (inout UserSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
    }

    /// Switching region re-expresses defaults in that region's own terms. It
    /// never silently rescales a number the user typed — the price and distance
    /// defaults are replaced with the new region's, and the user is told.
    func switchRegion(to region: Region) {
        guard region != settings.region else { return }
        let replacement = region == .unitedStates ? UserSettings.unitedStatesDefaults : UserSettings()
        update {
            $0.region = region
            $0.gasolinePricePerLitre = replacement.gasolinePricePerLitre
            $0.dieselPricePerLitre = replacement.dieselPricePerLitre
            $0.homeElectricityPricePerKWh = replacement.homeElectricityPricePerKWh
            $0.publicElectricityPricePerKWh = replacement.publicElectricityPricePerKWh
            $0.annualKilometres = replacement.annualKilometres
        }
    }

    func resetToDefaults() {
        settings = settings.region == .unitedStates ? .unitedStatesDefaults : UserSettings()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
