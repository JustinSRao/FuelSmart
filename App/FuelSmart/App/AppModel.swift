import Foundation
import SwiftUI
import FuelSmartCore

/// App-wide services and the active region.
///
/// Deliberately small. It owns the things that genuinely have app lifetime —
/// settings, the repositories, the VIN service — and nothing else. Screen state
/// lives in the screens, and every calculation lives in `FuelSmartCore`, so this
/// never becomes the god object that a single shared store tends to become.
@Observable
@MainActor
final class AppModel {

    let settingsStore: SettingsStore
    let vinService: VINService

    /// One repository per region, built once. Each lazily decodes its own
    /// dataset on first use, so launching with Canada selected never pays for
    /// the larger U.S. file.
    private var repositories: [Region: any VehicleRepository]

    /// Dataset metadata for the Settings and Data Sources screens.
    private(set) var manifest: DatasetManifest?
    private(set) var datasetLoadError: String?

    var settings: UserSettings { settingsStore.settings }
    var region: Region { settings.region }

    init(
        settingsStore: SettingsStore = SettingsStore(),
        vinService: VINService = VINService(),
        bundle: Bundle = .main
    ) {
        self.settingsStore = settingsStore
        self.vinService = vinService
        self.repositories = [
            .canada: VehicleRepositoryFactory.make(for: .canada, bundle: bundle),
            .unitedStates: VehicleRepositoryFactory.make(for: .unitedStates, bundle: bundle),
        ]
    }

    func repository(for region: Region) -> any VehicleRepository {
        repositories[region] ?? VehicleRepositoryFactory.make(for: region)
    }

    var currentRepository: any VehicleRepository { repository(for: region) }

    /// Load the dataset manifest. Failure is recorded, never thrown at the UI:
    /// a missing manifest costs the attribution screen, not the app.
    func loadManifest() async {
        guard manifest == nil else { return }
        do {
            if let canadian = repository(for: .canada) as? CanadianVehicleRepository {
                manifest = try await canadian.manifest()
            }
            datasetLoadError = nil
        } catch {
            datasetLoadError = (error as? VehicleRepositoryError)?.message ?? error.localizedDescription
        }
    }

    // MARK: - Derived presentation helpers

    var formatter: ValueFormatter { ValueFormatter(region: region) }
    var narrator: ResultNarrator { ResultNarrator(region: region) }

    /// Resolve the theme from the user's preference and the system scheme.
    func theme(for colorScheme: ColorScheme) -> FSTheme {
        let isDark = switch settings.theme {
        case .dark: true
        case .light: false
        case .system: colorScheme == .dark
        }
        return FSTheme(isDark: isDark, increaseContrast: settings.increaseContrast)
    }

    /// The colour scheme to force, or nil to follow the system.
    var preferredColorScheme: ColorScheme? {
        switch settings.theme {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

// MARK: - Comparison draft

/// The comparison currently being edited.
///
/// A mutable working copy of a `ComparisonScenario` plus the UI-only state that
/// surrounds it (which side is being edited, whether advanced sections are
/// open). Results are computed on demand from the scenario, never stored, so the
/// screen cannot show a figure that disagrees with the inputs.
@Observable
@MainActor
final class ComparisonDraft {

    var mode: ComparisonMode
    var region: Region

    var vehicleA: Vehicle?
    var vehicleB: Vehicle?

    var acquisitionA = AcquisitionCost()
    var acquisitionB = AcquisitionCost()
    var financingA = FinancingProfile.cash
    var financingB = FinancingProfile.cash
    var recurringA = RecurringCostProfile.empty
    var recurringB = RecurringCostProfile.empty
    var resaleA: ResaleAssumption?
    var resaleB: ResaleAssumption?
    var phevShareA = Split(primaryPercent: 70)
    var phevShareB = Split(primaryPercent: 70)

    var driving: DrivingProfile
    var energyPrices: EnergyPriceProfile
    var horizon: OwnershipHorizon
    var conditions: DrivingProfile.Conditions = .mild

    /// Distance as the user typed it, preserved so the field does not reformat
    /// under them when they switch period.
    var distanceEntry: Double
    var distancePeriod: DistancePeriod = .year

    /// Set when editing an existing saved comparison.
    var editingSavedId: UUID?
    var name: String = ""

    private let engine = ScenarioCalculator()
    private var startDate: Date

    init(settings: UserSettings, mode: ComparisonMode = .buyVsBuy, startDate: Date = Date()) {
        self.mode = mode
        self.region = settings.region
        self.driving = settings.drivingProfile
        self.energyPrices = settings.energyPriceProfile
        self.horizon = settings.preferredHorizon
        self.startDate = startDate
        self.distanceEntry = UnitConversionService.kilometresToRegionDistance(
            settings.annualKilometres, region: settings.region
        )
    }

    /// Rebuild a draft from a saved comparison, for editing.
    convenience init(saved: SavedComparison, settings: UserSettings) {
        self.init(settings: settings, mode: saved.scenario.mode, startDate: saved.scenario.startDate)
        let scenario = saved.scenario
        region = scenario.region
        vehicleA = scenario.sideA.vehicle
        vehicleB = scenario.sideB.vehicle
        acquisitionA = scenario.sideA.acquisition
        acquisitionB = scenario.sideB.acquisition
        financingA = scenario.sideA.financing
        financingB = scenario.sideB.financing
        recurringA = scenario.sideA.recurringCosts
        recurringB = scenario.sideB.recurringCosts
        resaleA = scenario.sideA.resale
        resaleB = scenario.sideB.resale
        phevShareA = scenario.sideA.phevElectricShare
        phevShareB = scenario.sideB.phevElectricShare
        driving = scenario.driving
        energyPrices = scenario.energyPrices
        horizon = scenario.horizon
        distanceEntry = UnitConversionService.kilometresToRegionDistance(
            scenario.driving.annualKilometres, region: scenario.region
        )
        editingSavedId = saved.id
        name = saved.name
    }

    // MARK: - Distance entry

    /// Re-normalize the annual distance whenever the entry or period changes.
    func applyDistanceEntry() {
        driving = DrivingProfile.from(
            distance: distanceEntry,
            period: distancePeriod,
            region: region,
            cityHighwaySplit: driving.cityHighwaySplit,
            realWorldAdjustment: driving.realWorldAdjustment
        )
    }

    // MARK: - Conditions

    func applyConditions(_ conditions: DrivingProfile.Conditions) {
        self.conditions = conditions
        if let adjustment = conditions.adjustment {
            driving.realWorldAdjustment = adjustment
        }
    }

    // MARK: - Scenario

    /// True when both sides have a vehicle, which is the minimum for a result.
    var isReadyToCompare: Bool { vehicleA != nil && vehicleB != nil }

    /// Build the immutable scenario the engine consumes.
    ///
    /// In keep-vs-replace, side A is the vehicle already owned. The flag is set
    /// here, in one place, rather than being the caller's responsibility.
    func makeScenario() -> ComparisonScenario? {
        guard let vehicleA, let vehicleB else { return nil }

        let sideA = ComparisonSide(
            vehicle: vehicleA,
            acquisition: acquisitionA,
            financing: financingA,
            recurringCosts: recurringA,
            resale: resaleA,
            phevElectricShare: phevShareA,
            isAlreadyOwned: mode == .keepVsReplace
        )
        let sideB = ComparisonSide(
            vehicle: vehicleB,
            acquisition: acquisitionB,
            financing: financingB,
            recurringCosts: recurringB,
            resale: resaleB,
            phevElectricShare: phevShareB,
            isAlreadyOwned: false
        )
        return ComparisonScenario(
            mode: mode, region: region,
            sideA: sideA, sideB: sideB,
            driving: driving, energyPrices: energyPrices,
            horizon: horizon, startDate: startDate
        )
    }

    /// Evaluate the current draft. Cheap enough to call from a view body —
    /// a 120-month simulation of two vehicles is a few thousand additions —
    /// but callers that drag a slider should hold the result in state instead of
    /// recomputing per frame.
    func evaluate(dataSources: [DataSourceMetadata] = []) -> FuelSmartCore.ComparisonResult? {
        guard let scenario = makeScenario() else { return nil }
        return engine.evaluate(scenario, dataSources: dataSources)
    }

    var validationIssues: [ScenarioValidationIssue] {
        guard let scenario = makeScenario() else { return [] }
        return ScenarioValidator.validate(scenario)
    }

    var blockingIssues: [ScenarioValidationIssue] {
        validationIssues.filter(\.isBlocking)
    }

    // MARK: - Saving

    func makeSavedComparison(now: Date = Date()) -> SavedComparison? {
        guard let scenario = makeScenario() else { return nil }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return SavedComparison(
            id: editingSavedId ?? UUID(),
            name: title.isEmpty ? defaultName : title,
            scenario: scenario,
            dateCreated: now,
            dateModified: now
        )
    }

    var defaultName: String {
        guard let a = vehicleA, let b = vehicleB else { return "New comparison" }
        return "\(a.shortDisplayName) vs \(b.shortDisplayName)"
    }

    // MARK: - Side accessors
    //
    // Screens are written once and pointed at a side, so there is no duplicated
    // "if A else B" logic scattered through the input forms.

    func acquisition(for side: ComparisonSideIdentifier) -> AcquisitionCost {
        side == .a ? acquisitionA : acquisitionB
    }

    func setAcquisition(_ value: AcquisitionCost, for side: ComparisonSideIdentifier) {
        if side == .a { acquisitionA = value } else { acquisitionB = value }
    }

    func financing(for side: ComparisonSideIdentifier) -> FinancingProfile {
        side == .a ? financingA : financingB
    }

    func setFinancing(_ value: FinancingProfile, for side: ComparisonSideIdentifier) {
        if side == .a { financingA = value } else { financingB = value }
    }

    func recurring(for side: ComparisonSideIdentifier) -> RecurringCostProfile {
        side == .a ? recurringA : recurringB
    }

    func setRecurring(_ value: RecurringCostProfile, for side: ComparisonSideIdentifier) {
        if side == .a { recurringA = value } else { recurringB = value }
    }

    func vehicle(for side: ComparisonSideIdentifier) -> Vehicle? {
        side == .a ? vehicleA : vehicleB
    }

    func setVehicle(_ vehicle: Vehicle?, for side: ComparisonSideIdentifier) {
        if side == .a { vehicleA = vehicle } else { vehicleB = vehicle }
    }

    func phevShare(for side: ComparisonSideIdentifier) -> Split {
        side == .a ? phevShareA : phevShareB
    }

    func setPhevShare(_ value: Split, for side: ComparisonSideIdentifier) {
        if side == .a { phevShareA = value } else { phevShareB = value }
    }

    /// The label for a side, which differs by mode: keep-vs-replace calls them
    /// "Your vehicle" and "Replacement" rather than A and B.
    func label(for side: ComparisonSideIdentifier) -> String {
        switch (mode, side) {
        case (.buyVsBuy, .a): "Vehicle A"
        case (.buyVsBuy, .b): "Vehicle B"
        case (.keepVsReplace, .a): "Your vehicle"
        case (.keepVsReplace, .b): "Replacement"
        }
    }
}
