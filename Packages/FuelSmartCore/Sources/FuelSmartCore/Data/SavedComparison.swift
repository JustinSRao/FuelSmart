import Foundation

/// A comparison the user chose to keep.
///
/// Stores the *scenario*, not the result. Results are recomputed on open, so a
/// saved comparison automatically reflects a corrected calculation or an updated
/// dataset rather than preserving a stale answer forever.
public struct SavedComparison: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var scenario: ComparisonScenario
    public var dateCreated: Date
    public var dateModified: Date

    public init(
        id: UUID = UUID(),
        name: String,
        scenario: ComparisonScenario,
        dateCreated: Date = Date(),
        dateModified: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.scenario = scenario
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }

    public var mode: ComparisonMode { scenario.mode }
    public var region: Region { scenario.region }

    /// "Camry Hybrid vs Model 3"
    public var subtitle: String {
        "\(scenario.sideA.vehicle.shortDisplayName) vs \(scenario.sideB.vehicle.shortDisplayName)"
    }

    public func duplicated(named newName: String? = nil, now: Date = Date()) -> SavedComparison {
        SavedComparison(
            id: UUID(),
            name: newName ?? "\(name) copy",
            scenario: scenario,
            dateCreated: now,
            dateModified: now
        )
    }

    public enum SortOrder: String, Sendable, CaseIterable, Identifiable {
        case dateModified, dateCreated, name
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .dateModified: "Recently edited"
            case .dateCreated: "Recently created"
            case .name: "Name"
            }
        }
    }

    public static func sort(_ items: [SavedComparison], by order: SortOrder) -> [SavedComparison] {
        switch order {
        case .dateModified: items.sorted { $0.dateModified > $1.dateModified }
        case .dateCreated: items.sorted { $0.dateCreated > $1.dateCreated }
        case .name: items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// Case- and diacritic-insensitive match across name, vehicles and mode.
    public func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack = [name, subtitle, mode.displayName].joined(separator: " ")
        return haystack.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

// MARK: - Defaults

/// Settings that persist between sessions, so a returning user taps straight
/// through the input screens.
///
/// Nothing here is required: the app ships with sensible values and onboarding
/// can be skipped entirely.
public struct UserSettings: Codable, Sendable, Hashable {
    public var region: Region
    public var gasolinePricePerLitre: Double
    public var dieselPricePerLitre: Double
    public var homeElectricityPricePerKWh: Double
    public var publicElectricityPricePerKWh: Double
    public var publicChargingShare: Split
    public var annualKilometres: Double
    public var cityHighwaySplit: Split
    public var preferredHorizon: OwnershipHorizon
    public var theme: ThemePreference
    public var increaseContrast: Bool
    public var hasCompletedOnboarding: Bool

    public enum ThemePreference: String, Codable, Sendable, CaseIterable, Identifiable {
        case light, dark, system
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .light: "Light"
            case .dark: "Dark"
            case .system: "System"
            }
        }
    }

    public init(
        region: Region = .canada,
        gasolinePricePerLitre: Double = 1.72,
        dieselPricePerLitre: Double = 1.85,
        homeElectricityPricePerKWh: Double = 0.14,
        publicElectricityPricePerKWh: Double = 0.52,
        publicChargingShare: Split = Split(primaryPercent: 20),
        annualKilometres: Double = 18_000,
        cityHighwaySplit: Split = Split(primaryPercent: 55),
        preferredHorizon: OwnershipHorizon = .fiveYears,
        theme: ThemePreference = .system,
        increaseContrast: Bool = false,
        hasCompletedOnboarding: Bool = false
    ) {
        self.region = region
        self.gasolinePricePerLitre = gasolinePricePerLitre
        self.dieselPricePerLitre = dieselPricePerLitre
        self.homeElectricityPricePerKWh = homeElectricityPricePerKWh
        self.publicElectricityPricePerKWh = publicElectricityPricePerKWh
        self.publicChargingShare = publicChargingShare
        self.annualKilometres = annualKilometres
        self.cityHighwaySplit = cityHighwaySplit
        self.preferredHorizon = preferredHorizon
        self.theme = theme
        self.increaseContrast = increaseContrast
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    /// U.S. defaults, in canonical units: roughly $3.30/gal and 12,000 mi/year.
    public static let unitedStatesDefaults = UserSettings(
        region: .unitedStates,
        gasolinePricePerLitre: UnitConversionService.pricePerUSGallonToPerLitre(3.30),
        dieselPricePerLitre: UnitConversionService.pricePerUSGallonToPerLitre(3.95),
        homeElectricityPricePerKWh: 0.17,
        publicElectricityPricePerKWh: 0.48,
        annualKilometres: UnitConversionService.milesToKilometres(12_000)
    )

    public var energyPriceProfile: EnergyPriceProfile {
        .homeAndPublic(
            gasolinePricePerLitre: gasolinePricePerLitre,
            dieselPricePerLitre: dieselPricePerLitre,
            homePricePerKWh: homeElectricityPricePerKWh,
            publicPricePerKWh: publicElectricityPricePerKWh,
            publicShare: publicChargingShare
        )
    }

    public var drivingProfile: DrivingProfile {
        DrivingProfile(annualKilometres: annualKilometres, cityHighwaySplit: cityHighwaySplit)
    }
}
