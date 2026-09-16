import Foundation

/// Region-aware presentation of every quantity the app shows.
///
/// One region is active at a time and every figure on screen belongs to it.
/// FuelSmart never mixes units and never shows a conversion in parentheses, so
/// each formatter takes the region and produces exactly one number.
///
/// Rounding happens here and nowhere else: whole currency units, except
/// per-100 km rates (2 dp) and fuel prices (2–3 dp). Intermediate calculation
/// values are never rounded.
public struct ValueFormatter: Sendable {

    public let region: Region
    private let locale: Locale

    public init(region: Region, locale: Locale? = nil) {
        self.region = region
        self.locale = locale ?? Locale(identifier: region == .canada ? "en_CA" : "en_US")
    }

    // MARK: - Money

    /// "$5,290" — whole units, the default for totals and differences.
    public func currency(_ value: Double, fractionDigits: Int = 0) -> String {
        guard value.isFinite else { return "—" }
        let magnitude = abs(value)
        let number = magnitude.formatted(
            .number.precision(.fractionLength(fractionDigits)).grouping(.automatic).locale(locale)
        )
        // A leading minus sign reads as a subtraction in a table of costs, so a
        // credit is shown with the typographic minus the design specifies.
        return (value < 0 ? "−$" : "$") + number
    }

    /// "$8.60" — two decimals, for rates per 100 km.
    public func rate(_ value: Double) -> String { currency(value, fractionDigits: 2) }

    /// "$1.72" or "$0.216" — fuel and electricity prices keep more precision,
    /// because a tenth of a cent per kWh is a meaningful difference over 10 years.
    public func energyPrice(_ value: Double, fractionDigits: Int = 2) -> String {
        currency(value, fractionDigits: fractionDigits)
    }

    public var currencyCode: String { region.currencyCode }

    // MARK: - Distance

    /// Canonical km in, region's unit out. "18,000 km" / "12,000 mi"
    public func distance(_ kilometres: Double, includeUnit: Bool = true) -> String {
        guard kilometres.isFinite else { return "—" }
        let value = UnitConversionService.kilometresToRegionDistance(kilometres, region: region)
        let number = value.rounded().formatted(.number.precision(.fractionLength(0)).locale(locale))
        return includeUnit ? "\(number) \(distanceUnit)" : number
    }

    public var distanceUnit: String { region.usesMetricDistance ? "km" : "mi" }

    /// Distance rounded to a readable step, for break-even figures where false
    /// precision would be misleading: "99,000 km", not "98,743 km".
    public func approximateDistance(_ kilometres: Double) -> String {
        guard kilometres.isFinite, kilometres > 0 else { return "—" }
        let value = UnitConversionService.kilometresToRegionDistance(kilometres, region: region)
        let step: Double = value >= 10_000 ? 100 : 10
        let rounded = (value / step).rounded() * step
        return "\(rounded.formatted(.number.precision(.fractionLength(0)).locale(locale))) \(distanceUnit)"
    }

    // MARK: - Consumption

    /// "5.0 L/100 km" / "47 MPG"
    public func fuelConsumption(_ litresPer100Km: Double?) -> String {
        guard let litresPer100Km, litresPer100Km > 0 else { return "—" }
        if region.usesMetricDistance {
            return "\(litresPer100Km.formatted(.number.precision(.fractionLength(1)).locale(locale))) L/100 km"
        }
        guard let mpg = UnitConversionService.litresPer100kmToUSMPG(litresPer100Km) else { return "—" }
        return "\(mpg.rounded().formatted(.number.precision(.fractionLength(0)).locale(locale))) MPG"
    }

    /// "14.9 kWh/100 km" / "24.0 kWh/100 mi"
    public func electricConsumption(_ kWhPer100Km: Double?) -> String {
        guard let kWhPer100Km, kWhPer100Km > 0 else { return "—" }
        if region.usesMetricDistance {
            return "\(kWhPer100Km.formatted(.number.precision(.fractionLength(1)).locale(locale))) kWh/100 km"
        }
        let per100Miles = UnitConversionService.kWhPer100kmToPer100Miles(kWhPer100Km)
        return "\(per100Miles.formatted(.number.precision(.fractionLength(1)).locale(locale))) kWh/100 mi"
    }

    /// The right consumption string for whichever energy a vehicle uses.
    public func consumption(for vehicle: Vehicle) -> String {
        switch vehicle.powertrain {
        case .bev:
            electricConsumption(vehicle.efficiency.combinedKwhPer100Km)
        case .phev:
            [
                electricConsumption(vehicle.efficiency.combinedKwhPer100Km),
                fuelConsumption(vehicle.efficiency.combinedLPer100Km),
            ].filter { $0 != "—" }.joined(separator: " · ")
        case .gasoline, .diesel, .hybrid, .other:
            fuelConsumption(vehicle.efficiency.combinedLPer100Km)
        }
    }

    // MARK: - Prices per unit of energy

    /// "$1.72 / L" or "$3.50 / gal"
    public func fuelPrice(_ perLitre: Double) -> String {
        let value = UnitConversionService.fuelPriceFromPerLitre(perLitre, region: region)
        let unit = region.usesMetricDistance ? "L" : "gal"
        return "\(energyPrice(value)) / \(unit)"
    }

    /// "$0.216 / kWh" — three decimals, because a blended rate lands between cents.
    public func electricityPrice(_ perKWh: Double) -> String {
        "\(energyPrice(perKWh, fractionDigits: 3)) / kWh"
    }

    /// "$8.60 / 100 km"
    public func costPerDistance(_ costPer100Km: Double) -> String {
        let per100 = region.usesMetricDistance
            ? costPer100Km
            : costPer100Km * UnitConversionService.kilometresPerMile
        return "\(rate(per100)) / 100 \(distanceUnit)"
    }

    // MARK: - Other

    /// "55 % city · 45 % highway"
    public func split(_ split: Split, primaryLabel: String, secondaryLabel: String) -> String {
        let primary = split.primaryPercent.rounded().formatted(.number.precision(.fractionLength(0)))
        let secondary = split.secondaryPercent.rounded().formatted(.number.precision(.fractionLength(0)))
        return "\(primary) % \(primaryLabel) · \(secondary) % \(secondaryLabel)"
    }

    public func percent(_ fraction: Double) -> String {
        "\((fraction * 100).rounded().formatted(.number.precision(.fractionLength(0)))) %"
    }

    /// "January 2033"
    public func monthAndYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    public func mediumDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }
}

// MARK: - Neutral language

/// Generates the sentences the app uses to describe a result.
///
/// Centralised so that no view can invent a claim. FuelSmart reports what the
/// numbers say under stated assumptions; it never recommends a purchase, never
/// praises a powertrain, and never calls one choice smarter than another.
///
/// Wording rules, applied uniformly:
/// - "Under these assumptions, X costs about $N less over five years."
/// - never "X saves you money", "X is the better choice", "you should buy X"
/// - "no break-even" is stated as a finding, not as a failure
public struct ResultNarrator: Sendable {

    private let formatter: ValueFormatter

    public init(region: Region, locale: Locale? = nil) {
        self.formatter = ValueFormatter(region: region, locale: locale)
    }

    /// The headline sentence for a result.
    public func headline(for result: ComparisonResult) -> String {
        let years = Int(result.scenario.horizon.years.rounded())
        let period = "\(years) year\(years == 1 ? "" : "s")"

        guard let cheaper = result.cheaperSideAtHorizon else {
            return "Over \(period), both vehicles cost about the same under these assumptions."
        }
        let name = (cheaper == .a ? result.sideA : result.sideB).vehicle.shortDisplayName
        let amount = formatter.currency(result.costDifferenceAtHorizon)
        return "Under these assumptions, the \(name) costs about \(amount) less over \(period)."
    }

    /// A short form for cards and list rows: "Model 3 · $3,180 less at 5 yr".
    public func compactSummary(for result: ComparisonResult) -> String {
        let years = Int(result.scenario.horizon.years.rounded())
        guard let cheaper = result.cheaperSideAtHorizon else {
            return "Level at \(years) yr"
        }
        let name = (cheaper == .a ? result.sideA : result.sideB).vehicle.shortDisplayName
        return "\(name) · \(formatter.currency(result.costDifferenceAtHorizon)) less at \(years) yr"
    }

    /// The break-even line, in words, for every possible status.
    public func breakEvenSummary(_ result: BreakEvenResult) -> String {
        result.explanation
    }

    /// The short chip shown on saved-comparison rows.
    public func breakEvenChip(_ result: BreakEvenResult, horizonYears: Int) -> String {
        switch result.status {
        case .breakEvenOccurs:
            "Break-even \(result.durationDescription ?? "—")"
        case .vehicleAAlwaysAhead, .vehicleBAlwaysAhead:
            "No break-even"
        case .noCrossingWithinHorizon:
            "No break-even in \(horizonYears) yr"
        case .identical:
            "Costs are level"
        case .insufficientData:
            "Not enough information"
        }
    }

    /// The assumptions footer used on the share card and the PDF.
    public func assumptionsLine(for result: ComparisonResult) -> String {
        let assumptions = result.assumptions
        var parts: [String] = [
            formatter.distance(assumptions.annualKilometres) + "/year",
            formatter.split(
                Split(primaryPercent: assumptions.cityPercent),
                primaryLabel: "city", secondaryLabel: "highway"
            ),
        ]
        if result.usesLiquidFuel {
            parts.append("gasoline \(formatter.fuelPrice(assumptions.gasolinePricePerLitre))")
        }
        if result.usesElectricity {
            parts.append("charging \(formatter.electricityPrice(assumptions.blendedElectricityPricePerKWh)) blended")
        }
        if assumptions.realWorldAdjustment != 0 {
            parts.append("real-world adjustment +\(formatter.percent(assumptions.realWorldAdjustment))")
        }
        parts.append(assumptions.includesOwnershipCosts ? "ownership costs included" : "purchase + energy only")
        parts.append(assumptions.includesResale ? "resale subtracted at horizon" : "resale excluded")
        return parts.joined(separator: " · ")
    }

    /// The disclaimer shown with results. Short by design — the full text lives
    /// in About, and warnings are not plastered everywhere.
    public static let shortDisclaimer =
        "Estimates based on your assumptions and official efficiency ratings. "
        + "Real-world consumption and future prices vary."
}

public extension ComparisonResult {
    var usesLiquidFuel: Bool {
        sideA.vehicle.powertrain.usesLiquidFuel || sideB.vehicle.powertrain.usesLiquidFuel
    }
    var usesElectricity: Bool {
        sideA.vehicle.powertrain.usesElectricity || sideB.vehicle.powertrain.usesElectricity
    }
}
