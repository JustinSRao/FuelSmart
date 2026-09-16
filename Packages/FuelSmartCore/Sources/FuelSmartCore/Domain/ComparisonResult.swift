import Foundation

/// A cost category, kept separately addressable so charts and breakdowns can
/// read any one of them without re-running the engine.
public enum CostCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case acquisition
    case financingInterest
    case fuel
    case electricity
    case insurance
    case maintenance
    case registration
    case parking
    case otherRecurring
    case oneTimeCosts
    case resale

    public var displayName: String {
        switch self {
        case .acquisition: "Acquisition"
        case .financingInterest: "Financing interest"
        case .fuel: "Fuel"
        case .electricity: "Electricity"
        case .insurance: "Insurance"
        case .maintenance: "Maintenance"
        case .registration: "Registration"
        case .parking: "Parking"
        case .otherRecurring: "Other"
        case .oneTimeCosts: "One-time costs"
        case .resale: "Resale value"
        }
    }

    /// Resale is a credit; everything else is a charge.
    public var isCredit: Bool { self == .resale }
}

/// One month of the simulation for one vehicle.
public struct CumulativeCostPoint: Codable, Sendable, Hashable {
    public var month: Int
    public var kilometres: Double
    /// Total cost incurred from month 0 through this month, inclusive.
    public var cumulativeCost: Double
    /// The same total, split by category.
    public var byCategory: [CostCategory: Double]

    public init(month: Int, kilometres: Double, cumulativeCost: Double, byCategory: [CostCategory: Double]) {
        self.month = month
        self.kilometres = kilometres
        self.cumulativeCost = cumulativeCost
        self.byCategory = byCategory
    }
}

/// Energy economics for one vehicle, independent of any other cost.
public struct EnergyCostBreakdown: Codable, Sendable, Hashable {
    /// Litres per 100 km actually used after blending and adjustment, if any.
    public var effectiveLitresPer100Km: Double?
    /// kWh per 100 km actually used after blending and adjustment, if any.
    public var effectiveKwhPer100Km: Double?

    public var fuelCostPer100Km: Double
    public var electricityCostPer100Km: Double
    public var annualFuelCost: Double
    public var annualElectricityCost: Double

    /// True when the vehicle's city/highway ratings were unavailable and the
    /// combined figure was used instead. Surfaced so the fallback is visible.
    public var usedCombinedFallback: Bool

    public var totalCostPer100Km: Double { fuelCostPer100Km + electricityCostPer100Km }
    public var annualTotal: Double { annualFuelCost + annualElectricityCost }
    public var monthlyTotal: Double { annualTotal / 12 }

    public init(
        effectiveLitresPer100Km: Double?,
        effectiveKwhPer100Km: Double?,
        fuelCostPer100Km: Double,
        electricityCostPer100Km: Double,
        annualFuelCost: Double,
        annualElectricityCost: Double,
        usedCombinedFallback: Bool
    ) {
        self.effectiveLitresPer100Km = effectiveLitresPer100Km
        self.effectiveKwhPer100Km = effectiveKwhPer100Km
        self.fuelCostPer100Km = fuelCostPer100Km
        self.electricityCostPer100Km = electricityCostPer100Km
        self.annualFuelCost = annualFuelCost
        self.annualElectricityCost = annualElectricityCost
        self.usedCombinedFallback = usedCombinedFallback
    }
}

/// Amortized loan figures.
public struct FinancingBreakdown: Codable, Sendable, Hashable {
    public var financedPrincipal: Double
    public var monthlyPayment: Double
    public var totalInterest: Double
    public var termMonths: Int
    /// Interest accrued from month 0 through each month, so a horizon shorter
    /// than the loan term charges only the interest actually paid by then.
    public var cumulativeInterestByMonth: [Double]

    public init(
        financedPrincipal: Double,
        monthlyPayment: Double,
        totalInterest: Double,
        termMonths: Int,
        cumulativeInterestByMonth: [Double]
    ) {
        self.financedPrincipal = financedPrincipal
        self.monthlyPayment = monthlyPayment
        self.totalInterest = totalInterest
        self.termMonths = termMonths
        self.cumulativeInterestByMonth = cumulativeInterestByMonth
    }

    public static let none = FinancingBreakdown(
        financedPrincipal: 0, monthlyPayment: 0, totalInterest: 0,
        termMonths: 0, cumulativeInterestByMonth: [0]
    )

    /// Interest paid by a given month, clamped to the end of the loan.
    public func cumulativeInterest(atMonth month: Int) -> Double {
        guard !cumulativeInterestByMonth.isEmpty else { return 0 }
        let index = min(max(month, 0), cumulativeInterestByMonth.count - 1)
        return cumulativeInterestByMonth[index]
    }
}

/// What the break-even analysis concluded. Never forced into a date.
public enum BreakEvenStatus: String, Codable, Sendable, Hashable {
    /// The curves cross inside the simulated period.
    case breakEvenOccurs
    /// A starts cheaper and stays cheaper for the whole period.
    case vehicleAAlwaysAhead
    /// B starts cheaper and stays cheaper for the whole period.
    case vehicleBAlwaysAhead
    /// A crossing exists mathematically but falls beyond the simulated period.
    case noCrossingWithinHorizon
    /// The two are indistinguishable.
    case identical
    /// Inputs were insufficient to say anything — zero distance, no prices.
    case insufficientData
}

public struct BreakEvenResult: Codable, Sendable, Hashable {
    public var status: BreakEvenStatus
    /// Month at which the cumulative curves cross, when they do.
    public var month: Int?
    /// Distance driven by that month.
    public var kilometres: Double?
    public var estimatedDate: Date?
    /// Cumulative cost of both vehicles at the crossing.
    public var costAtIntersection: Double?
    /// How far apart the two start: B's acquisition minus A's.
    public var initialDifference: Double
    /// Plain-language explanation, written to avoid implying a winner.
    public var explanation: String

    public init(
        status: BreakEvenStatus,
        month: Int? = nil,
        kilometres: Double? = nil,
        estimatedDate: Date? = nil,
        costAtIntersection: Double? = nil,
        initialDifference: Double,
        explanation: String
    ) {
        self.status = status
        self.month = month
        self.kilometres = kilometres
        self.estimatedDate = estimatedDate
        self.costAtIntersection = costAtIntersection
        self.initialDifference = initialDifference
        self.explanation = explanation
    }

    /// "5 years 6 months", or nil when there is no crossing.
    public var durationDescription: String? {
        guard let month else { return nil }
        let years = month / 12
        let months = month % 12
        switch (years, months) {
        case (0, 0): return "Immediately"
        case (0, _): return "\(months) month\(months == 1 ? "" : "s")"
        case (_, 0): return "\(years) year\(years == 1 ? "" : "s")"
        default: return "\(years) year\(years == 1 ? "" : "s") \(months) month\(months == 1 ? "" : "s")"
        }
    }
}

/// Everything one side of the comparison produced.
public struct SideResult: Codable, Sendable, Hashable {
    public var vehicle: Vehicle
    public var netAcquisitionCost: Double
    public var energy: EnergyCostBreakdown
    public var financing: FinancingBreakdown
    public var annualRecurringCost: Double
    public var resaleCredit: Double
    public var cumulativePoints: [CumulativeCostPoint]

    public init(
        vehicle: Vehicle,
        netAcquisitionCost: Double,
        energy: EnergyCostBreakdown,
        financing: FinancingBreakdown,
        annualRecurringCost: Double,
        resaleCredit: Double,
        cumulativePoints: [CumulativeCostPoint]
    ) {
        self.vehicle = vehicle
        self.netAcquisitionCost = netAcquisitionCost
        self.energy = energy
        self.financing = financing
        self.annualRecurringCost = annualRecurringCost
        self.resaleCredit = resaleCredit
        self.cumulativePoints = cumulativePoints
    }

    /// Cumulative cost at a month, without the end-of-horizon resale credit.
    public func cost(atMonth month: Int) -> Double {
        guard !cumulativePoints.isEmpty else { return 0 }
        let index = min(max(month, 0), cumulativePoints.count - 1)
        return cumulativePoints[index].cumulativeCost
    }

    public func categoryTotals(atMonth month: Int) -> [CostCategory: Double] {
        guard !cumulativePoints.isEmpty else { return [:] }
        let index = min(max(month, 0), cumulativePoints.count - 1)
        return cumulativePoints[index].byCategory
    }
}

/// The assumptions that shaped a result, carried with it so a shared card or a
/// PDF can state them without reconstructing the scenario.
public struct ResultAssumptions: Codable, Sendable, Hashable {
    public var annualKilometres: Double
    public var cityPercent: Double
    public var highwayPercent: Double
    public var gasolinePricePerLitre: Double
    public var dieselPricePerLitre: Double
    public var blendedElectricityPricePerKWh: Double
    public var realWorldAdjustment: Double
    public var includesOwnershipCosts: Bool
    public var includesResale: Bool
    public var costLabel: String
    public var region: Region
    public var mode: ComparisonMode

    public init(
        annualKilometres: Double, cityPercent: Double, highwayPercent: Double,
        gasolinePricePerLitre: Double, dieselPricePerLitre: Double,
        blendedElectricityPricePerKWh: Double, realWorldAdjustment: Double,
        includesOwnershipCosts: Bool, includesResale: Bool,
        costLabel: String, region: Region, mode: ComparisonMode
    ) {
        self.annualKilometres = annualKilometres
        self.cityPercent = cityPercent
        self.highwayPercent = highwayPercent
        self.gasolinePricePerLitre = gasolinePricePerLitre
        self.dieselPricePerLitre = dieselPricePerLitre
        self.blendedElectricityPricePerKWh = blendedElectricityPricePerKWh
        self.realWorldAdjustment = realWorldAdjustment
        self.includesOwnershipCosts = includesOwnershipCosts
        self.includesResale = includesResale
        self.costLabel = costLabel
        self.region = region
        self.mode = mode
    }
}

/// The complete output of one comparison.
public struct ComparisonResult: Codable, Sendable, Hashable {
    public var scenario: ComparisonScenario
    public var sideA: SideResult
    public var sideB: SideResult

    /// Break-even on the full enabled cost model.
    public var breakEven: BreakEvenResult
    /// Break-even on acquisition + energy only, always computed, so the core
    /// economics can be read separately from softer assumptions.
    public var energyOnlyBreakEven: BreakEvenResult

    public var assumptions: ResultAssumptions
    public var dataSources: [DataSourceMetadata]

    public init(
        scenario: ComparisonScenario,
        sideA: SideResult,
        sideB: SideResult,
        breakEven: BreakEvenResult,
        energyOnlyBreakEven: BreakEvenResult,
        assumptions: ResultAssumptions,
        dataSources: [DataSourceMetadata]
    ) {
        self.scenario = scenario
        self.sideA = sideA
        self.sideB = sideB
        self.breakEven = breakEven
        self.energyOnlyBreakEven = energyOnlyBreakEven
        self.assumptions = assumptions
        self.dataSources = dataSources
    }

    // MARK: - Headline figures

    public var horizonMonths: Int { scenario.horizon.months_ }

    /// Total for a side at the selected horizon, including the resale credit,
    /// which is applied once at the endpoint and never amortized into the curve.
    public func total(for side: SideResult) -> Double {
        side.cost(atMonth: horizonMonths) - side.resaleCredit
    }

    public var totalA: Double { total(for: sideA) }
    public var totalB: Double { total(for: sideB) }

    /// Always non-negative. Direction is given by `cheaperSideAtHorizon`.
    public var costDifferenceAtHorizon: Double { abs(totalA - totalB) }

    public var energyCostDifferencePerYear: Double {
        abs(sideA.energy.annualTotal - sideB.energy.annualTotal)
    }

    /// Which side costs less at the horizon, or nil when they are level.
    public var cheaperSideAtHorizon: ComparisonSideIdentifier? {
        let delta = totalA - totalB
        if abs(delta) < 0.005 { return nil }
        return delta > 0 ? .b : .a
    }

    /// Totals at each standard milestone, for the results table.
    public func total(for side: SideResult, atYears years: Int) -> Double {
        let months = years * 12
        let base = side.cost(atMonth: months)
        // Resale only applies at the chosen horizon, not at every milestone.
        return months == horizonMonths ? base - side.resaleCredit : base
    }
}

public enum ComparisonSideIdentifier: String, Codable, Sendable, Hashable, Identifiable {
    case a, b

    public var id: String { rawValue }
}

/// Where a vehicle record came from, so attribution can be displayed and a
/// result can state which dataset produced it.
public struct DataSourceMetadata: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var publisher: String
    public var dataset: String
    public var licence: String
    public var licenceURL: String?
    public var landingPage: String?
    public var datasetVersion: String?
    public var retrievedAt: Date?

    public init(
        id: String, publisher: String, dataset: String, licence: String,
        licenceURL: String? = nil, landingPage: String? = nil,
        datasetVersion: String? = nil, retrievedAt: Date? = nil
    ) {
        self.id = id
        self.publisher = publisher
        self.dataset = dataset
        self.licence = licence
        self.licenceURL = licenceURL
        self.landingPage = landingPage
        self.datasetVersion = datasetVersion
        self.retrievedAt = retrievedAt
    }
}
