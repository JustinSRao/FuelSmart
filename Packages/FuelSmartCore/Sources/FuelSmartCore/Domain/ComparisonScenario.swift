import Foundation

/// Which question the user is asking. The distinction changes the arithmetic,
/// not just the wording.
public enum ComparisonMode: String, Codable, Sendable, CaseIterable, Hashable {
    /// Two vehicles, neither owned. Both acquisition costs count.
    case buyVsBuy
    /// Vehicle A is already owned. What was paid for it is sunk and is never
    /// charged again; only what happens next counts.
    case keepVsReplace

    public var displayName: String {
        switch self {
        case .buyVsBuy: "Buy vs buy"
        case .keepVsReplace: "Keep vs replace"
        }
    }
}

/// How long the user intends to keep the vehicle.
public enum OwnershipHorizon: Codable, Sendable, Hashable {
    case years(Int)
    case months(Int)

    public var months_: Int {
        switch self {
        case .years(let y): max(y, 0) * 12
        case .months(let m): max(m, 0)
        }
    }

    public var years: Double { Double(months_) / 12 }

    public static let threeYears = OwnershipHorizon.years(3)
    public static let fiveYears = OwnershipHorizon.years(5)
    public static let eightYears = OwnershipHorizon.years(8)
    public static let tenYears = OwnershipHorizon.years(10)

    public static let presets: [OwnershipHorizon] = [.threeYears, .fiveYears, .eightYears, .tenYears]
}

/// Everything about one side of a comparison.
public struct ComparisonSide: Codable, Sendable, Hashable {
    public var vehicle: Vehicle
    public var acquisition: AcquisitionCost
    public var financing: FinancingProfile
    public var recurringCosts: RecurringCostProfile
    public var resale: ResaleAssumption?

    /// Share of distance driven on electricity, for a PHEV only. 0...1.
    public var phevElectricShare: Split

    /// True when this side is a vehicle the user already owns, in keep-vs-replace.
    /// Its acquisition cost is treated as sunk and excluded entirely.
    public var isAlreadyOwned: Bool

    public init(
        vehicle: Vehicle,
        acquisition: AcquisitionCost = AcquisitionCost(),
        financing: FinancingProfile = .cash,
        recurringCosts: RecurringCostProfile = .empty,
        resale: ResaleAssumption? = nil,
        phevElectricShare: Split = Split(primaryPercent: 70),
        isAlreadyOwned: Bool = false
    ) {
        self.vehicle = vehicle
        self.acquisition = acquisition
        self.financing = financing
        self.recurringCosts = recurringCosts
        self.resale = resale
        self.phevElectricShare = phevElectricShare
        self.isAlreadyOwned = isAlreadyOwned
    }

    /// Net acquisition actually charged against this side.
    ///
    /// The sunk-cost rule lives here, once: a vehicle the user already owns
    /// contributes zero, no matter what its `acquisition` record says.
    public var chargeableAcquisition: Double {
        isAlreadyOwned ? 0 : acquisition.net
    }
}

/// A complete, self-contained description of one comparison. Feeding the same
/// scenario to the engine always produces the same result.
public struct ComparisonScenario: Codable, Sendable, Hashable {
    public var mode: ComparisonMode
    public var region: Region
    public var sideA: ComparisonSide
    public var sideB: ComparisonSide
    public var driving: DrivingProfile
    public var energyPrices: EnergyPriceProfile
    public var horizon: OwnershipHorizon

    /// The date the comparison starts from, used to turn a break-even month into
    /// a calendar date. Injected rather than read from the clock so results are
    /// reproducible and testable.
    public var startDate: Date

    public init(
        mode: ComparisonMode,
        region: Region,
        sideA: ComparisonSide,
        sideB: ComparisonSide,
        driving: DrivingProfile,
        energyPrices: EnergyPriceProfile,
        horizon: OwnershipHorizon = .fiveYears,
        startDate: Date = Date()
    ) {
        self.mode = mode
        self.region = region
        self.sideA = sideA
        self.sideB = sideB
        self.driving = driving
        self.energyPrices = energyPrices
        self.horizon = horizon
        self.startDate = startDate
    }

    /// True when either side has supplied a recurring cost, which changes what
    /// the result may honestly be called.
    public var includesOwnershipCosts: Bool {
        sideA.recurringCosts.isEnabled || sideB.recurringCosts.isEnabled
    }

    /// The label the UI must use for the headline figure.
    public var costLabel: String {
        includesOwnershipCosts ? "Estimated ownership cost" : "Purchase + energy cost"
    }

    /// How far the simulation should run: always at least ten years so the chart
    /// can show a crossover that falls beyond a short chosen horizon.
    public var simulationMonths: Int {
        max(horizon.months_, 120)
    }
}
