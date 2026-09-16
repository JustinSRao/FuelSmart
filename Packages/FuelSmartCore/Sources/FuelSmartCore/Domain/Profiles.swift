import Foundation

// MARK: - Driving

/// A split between two shares that is guaranteed to total 100%.
///
/// Modelled as a single stored fraction rather than two independent numbers, so
/// the invariant cannot be broken by construction — the design calls for "one
/// handle, two values; the split can't leave 100%".
public struct Split: Codable, Sendable, Hashable {
    /// The first share, clamped to 0...1.
    public private(set) var primary: Double

    public var secondary: Double { 1 - primary }

    public init(primary: Double) {
        self.primary = min(max(primary, 0), 1)
    }

    /// Build from a percentage typed by a user.
    public init(primaryPercent: Double) {
        self.init(primary: primaryPercent / 100)
    }

    public var primaryPercent: Double { primary * 100 }
    public var secondaryPercent: Double { secondary * 100 }

    public static let evenSplit = Split(primary: 0.5)
}

/// How the user actually drives. Distance is normalized to a year at the edge,
/// so the engine only ever sees annual kilometres.
public struct DrivingProfile: Codable, Sendable, Hashable {

    /// Canonical annual distance in kilometres.
    public var annualKilometres: Double

    /// City share of distance; highway is the remainder.
    public var cityHighwaySplit: Split

    /// Optional multiplier applied to *consumption*, expressed as a fraction
    /// above the official rating. 0.08 means "assume 8% more energy than the lab
    /// figure". This is a user-declared scenario assumption, never applied
    /// silently, and it is reported alongside the result.
    public var realWorldAdjustment: Double

    public init(
        annualKilometres: Double,
        cityHighwaySplit: Split = Split(primaryPercent: 55),
        realWorldAdjustment: Double = 0
    ) {
        self.annualKilometres = annualKilometres
        self.cityHighwaySplit = cityHighwaySplit
        self.realWorldAdjustment = realWorldAdjustment
    }

    /// Build from a figure typed in the region's own distance unit and period.
    public static func from(
        distance: Double,
        period: DistancePeriod,
        region: Region,
        cityHighwaySplit: Split = Split(primaryPercent: 55),
        realWorldAdjustment: Double = 0
    ) -> DrivingProfile {
        let perYearInRegionUnits = distance * period.periodsPerYear
        return DrivingProfile(
            annualKilometres: UnitConversionService.distanceToKilometres(perYearInRegionUnits, region: region),
            cityHighwaySplit: cityHighwaySplit,
            realWorldAdjustment: realWorldAdjustment
        )
    }

    /// The named presets offered by the conditions picker. Each is a declared
    /// assumption with a stated magnitude, not a hidden correction.
    public enum Conditions: String, Codable, Sendable, CaseIterable {
        case mild, mixed, coldClimate, custom

        public var adjustment: Double? {
            switch self {
            case .mild: 0
            case .mixed: 0.08
            case .coldClimate: 0.18
            case .custom: nil
            }
        }

        public var displayName: String {
            switch self {
            case .mild: "Mild"
            case .mixed: "Mixed"
            case .coldClimate: "Cold climate"
            case .custom: "Custom"
            }
        }
    }
}

// MARK: - Energy prices

/// What the user pays for energy, in canonical units ($/litre, $/kWh).
///
/// Charging is modelled as a blend from the start so that adding a third
/// category later (workplace, destination) does not require touching the
/// calculators — they only ever ask for `blendedElectricityPricePerKWh`.
public struct EnergyPriceProfile: Codable, Sendable, Hashable {

    public var gasolinePricePerLitre: Double
    public var dieselPricePerLitre: Double

    /// Where the energy comes from and what each source costs.
    public var chargingSources: [ChargingSource]

    public struct ChargingSource: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var pricePerKWh: Double
        /// Share of charging from this source, 0...1. Shares are normalized on
        /// use, so a set that does not quite total 1 cannot distort the result.
        public var share: Double

        public init(id: String, name: String, pricePerKWh: Double, share: Double) {
            self.id = id
            self.name = name
            self.pricePerKWh = pricePerKWh
            self.share = share
        }
    }

    public init(
        gasolinePricePerLitre: Double,
        dieselPricePerLitre: Double,
        chargingSources: [ChargingSource]
    ) {
        self.gasolinePricePerLitre = gasolinePricePerLitre
        self.dieselPricePerLitre = dieselPricePerLitre
        self.chargingSources = chargingSources
    }

    /// Simple mode: one electricity price, no home/public distinction.
    public init(
        gasolinePricePerLitre: Double,
        dieselPricePerLitre: Double,
        electricityPricePerKWh: Double
    ) {
        self.init(
            gasolinePricePerLitre: gasolinePricePerLitre,
            dieselPricePerLitre: dieselPricePerLitre,
            chargingSources: [
                .init(id: "single", name: "Electricity", pricePerKWh: electricityPricePerKWh, share: 1)
            ]
        )
    }

    /// Advanced mode: a home/public split.
    public static func homeAndPublic(
        gasolinePricePerLitre: Double,
        dieselPricePerLitre: Double,
        homePricePerKWh: Double,
        publicPricePerKWh: Double,
        publicShare: Split
    ) -> EnergyPriceProfile {
        EnergyPriceProfile(
            gasolinePricePerLitre: gasolinePricePerLitre,
            dieselPricePerLitre: dieselPricePerLitre,
            chargingSources: [
                .init(id: "home", name: "Home charging", pricePerKWh: homePricePerKWh, share: publicShare.secondary),
                .init(id: "public", name: "Public charging", pricePerKWh: publicPricePerKWh, share: publicShare.primary),
            ]
        )
    }

    /// Share-weighted electricity price.
    ///
    ///     blended = Σ (shareᵢ × priceᵢ) / Σ shareᵢ
    ///
    /// Dividing by the total share normalizes any set that does not sum to 1,
    /// which keeps a partially-filled advanced form from silently understating
    /// the rate.
    public var blendedElectricityPricePerKWh: Double {
        let totalShare = chargingSources.reduce(0) { $0 + max($1.share, 0) }
        guard totalShare > 0 else { return 0 }
        let weighted = chargingSources.reduce(0.0) { $0 + max($1.share, 0) * $1.pricePerKWh }
        return weighted / totalShare
    }

    public func price(for kind: LiquidFuelKind) -> Double {
        switch kind {
        case .gasoline: gasolinePricePerLitre
        case .diesel: dieselPricePerLitre
        }
    }
}

// MARK: - Money in and out

/// Everything paid once, at acquisition.
///
/// Every field beyond `purchasePrice` is optional in the UI and defaults to
/// zero here, so an empty advanced section changes nothing.
public struct AcquisitionCost: Codable, Sendable, Hashable {
    public var purchasePrice: Double
    public var salesTax: Double
    public var dealerFees: Double
    public var otherOneTimeFees: Double
    public var rebate: Double
    public var governmentIncentive: Double
    public var manufacturerIncentive: Double
    public var tradeInValue: Double
    public var homeChargerInstallation: Double
    public var electricalPanelUpgrade: Double
    public var otherOneTimeCost: Double

    public init(
        purchasePrice: Double = 0,
        salesTax: Double = 0,
        dealerFees: Double = 0,
        otherOneTimeFees: Double = 0,
        rebate: Double = 0,
        governmentIncentive: Double = 0,
        manufacturerIncentive: Double = 0,
        tradeInValue: Double = 0,
        homeChargerInstallation: Double = 0,
        electricalPanelUpgrade: Double = 0,
        otherOneTimeCost: Double = 0
    ) {
        self.purchasePrice = purchasePrice
        self.salesTax = salesTax
        self.dealerFees = dealerFees
        self.otherOneTimeFees = otherOneTimeFees
        self.rebate = rebate
        self.governmentIncentive = governmentIncentive
        self.manufacturerIncentive = manufacturerIncentive
        self.tradeInValue = tradeInValue
        self.homeChargerInstallation = homeChargerInstallation
        self.electricalPanelUpgrade = electricalPanelUpgrade
        self.otherOneTimeCost = otherOneTimeCost
    }

    public var totalAdditions: Double {
        purchasePrice + salesTax + dealerFees + otherOneTimeFees
            + homeChargerInstallation + electricalPanelUpgrade + otherOneTimeCost
    }

    public var totalDeductions: Double {
        rebate + governmentIncentive + manufacturerIncentive + tradeInValue
    }

    /// Net cash required to acquire the vehicle.
    ///
    /// Clamped at zero: incentives exceeding the price make the transaction free,
    /// not a source of income, and a negative acquisition would corrupt the
    /// cumulative curve.
    public var net: Double {
        max(totalAdditions - totalDeductions, 0)
    }
}

/// Optional yearly costs, kept strictly separate from energy so the result can
/// be labelled honestly.
public struct RecurringCostProfile: Codable, Sendable, Hashable {
    public var annualInsurance: Double?
    public var annualMaintenance: Double?
    public var annualRegistration: Double?
    public var annualParking: Double?
    public var annualOther: Double?

    public init(
        annualInsurance: Double? = nil,
        annualMaintenance: Double? = nil,
        annualRegistration: Double? = nil,
        annualParking: Double? = nil,
        annualOther: Double? = nil
    ) {
        self.annualInsurance = annualInsurance
        self.annualMaintenance = annualMaintenance
        self.annualRegistration = annualRegistration
        self.annualParking = annualParking
        self.annualOther = annualOther
    }

    /// True when the user supplied at least one figure. Drives whether the
    /// result is called "Purchase + energy" or "Estimated ownership cost".
    public var isEnabled: Bool {
        allValues.contains { $0 != nil }
    }

    public var annualTotal: Double {
        // Summed by reduce rather than as one long `??` chain: five coalescing
        // operators in a single arithmetic expression exceeds what the Swift
        // expression type-checker will solve in reasonable time.
        allValues.reduce(0) { $0 + ($1 ?? 0) }
    }

    /// Every optional field, in one place, so `isEnabled` and `annualTotal`
    /// cannot fall out of step as fields are added.
    private var allValues: [Double?] {
        [annualInsurance, annualMaintenance, annualRegistration, annualParking, annualOther]
    }

    public static let empty = RecurringCostProfile()
}

/// An optional amortized loan.
public struct FinancingProfile: Codable, Sendable, Hashable {
    /// Paid up front and therefore never financed.
    public var downPayment: Double
    /// Annual percentage rate as a fraction: 0.059 for 5.9%.
    public var annualPercentageRate: Double
    public var termMonths: Int

    public init(downPayment: Double = 0, annualPercentageRate: Double = 0, termMonths: Int = 0) {
        self.downPayment = downPayment
        self.annualPercentageRate = annualPercentageRate
        self.termMonths = termMonths
    }

    /// A cash purchase: no loan at all.
    public static let cash = FinancingProfile()

    public var isFinanced: Bool { termMonths > 0 }
}

/// The user's own resale assumption. FuelSmart never forecasts depreciation.
public struct ResaleAssumption: Codable, Sendable, Hashable {
    public var expectedValue: Double
    /// When false the figure is recorded but excluded from totals.
    public var isIncludedInTotals: Bool

    public init(expectedValue: Double, isIncludedInTotals: Bool = true) {
        self.expectedValue = expectedValue
        self.isIncludedInTotals = isIncludedInTotals
    }
}
