import Foundation

/// The one entry point to the calculation engine.
///
/// Deterministic and free of any dependency on UI, storage, the network or the
/// system clock — the scenario carries its own start date. The same scenario
/// always produces the same result, which is what makes the model auditable and
/// the tests meaningful.
public struct ScenarioCalculator: Sendable {

    public init() {}

    public func evaluate(
        _ scenario: ComparisonScenario,
        dataSources: [DataSourceMetadata] = []
    ) -> ComparisonResult {
        let months = scenario.simulationMonths

        let sideA = OwnershipCostCalculator.simulate(
            side: scenario.sideA, driving: scenario.driving,
            prices: scenario.energyPrices, months: months
        )
        let sideB = OwnershipCostCalculator.simulate(
            side: scenario.sideB, driving: scenario.driving,
            prices: scenario.energyPrices, months: months
        )

        let breakEven = BreakEvenCalculator.analyse(
            sideA: sideA, sideB: sideB,
            driving: scenario.driving, startDate: scenario.startDate,
            horizonMonths: scenario.horizon.months_
        )

        // The same analysis on acquisition + energy alone, so the user can see
        // the core energy economics without insurance, maintenance or financing
        // assumptions mixed in.
        let energyOnlyA = OwnershipCostCalculator.simulateEnergyOnly(
            side: scenario.sideA, driving: scenario.driving,
            prices: scenario.energyPrices, months: months
        )
        let energyOnlyB = OwnershipCostCalculator.simulateEnergyOnly(
            side: scenario.sideB, driving: scenario.driving,
            prices: scenario.energyPrices, months: months
        )
        let energyOnlyBreakEven = BreakEvenCalculator.analyse(
            sideA: energyOnlyA, sideB: energyOnlyB,
            driving: scenario.driving, startDate: scenario.startDate,
            horizonMonths: scenario.horizon.months_
        )

        let assumptions = ResultAssumptions(
            annualKilometres: scenario.driving.annualKilometres,
            cityPercent: scenario.driving.cityHighwaySplit.primaryPercent,
            highwayPercent: scenario.driving.cityHighwaySplit.secondaryPercent,
            gasolinePricePerLitre: scenario.energyPrices.gasolinePricePerLitre,
            dieselPricePerLitre: scenario.energyPrices.dieselPricePerLitre,
            blendedElectricityPricePerKWh: scenario.energyPrices.blendedElectricityPricePerKWh,
            realWorldAdjustment: scenario.driving.realWorldAdjustment,
            includesOwnershipCosts: scenario.includesOwnershipCosts,
            includesResale: sideA.resaleCredit > 0 || sideB.resaleCredit > 0,
            costLabel: scenario.costLabel,
            region: scenario.region,
            mode: scenario.mode
        )

        return ComparisonResult(
            scenario: scenario,
            sideA: sideA,
            sideB: sideB,
            breakEven: breakEven,
            energyOnlyBreakEven: energyOnlyBreakEven,
            assumptions: assumptions,
            dataSources: dataSources
        )
    }
}

// MARK: - Input validation

/// Problems the engine can detect before it runs, so the UI can explain them in
/// human terms instead of showing a nonsense result.
public enum ScenarioValidationIssue: Sendable, Hashable, Identifiable {
    case zeroAnnualDistance
    case negativePrice(side: ComparisonSideIdentifier)
    case implausiblePrice(side: ComparisonSideIdentifier, value: Double)
    case missingEfficiency(side: ComparisonSideIdentifier, vehicleName: String)
    case negativeEnergyPrice
    case zeroEnergyPrice(fuel: String)
    case horizonShorterThanLoan

    public var id: String { message }

    public var message: String {
        switch self {
        case .zeroAnnualDistance:
            "Enter a distance above zero to compare."
        case .negativePrice:
            "A vehicle price can't be negative."
        case .implausiblePrice(_, let value):
            "\(Int(value).formatted()) is outside the range FuelSmart can chart. Check for an extra digit."
        case .missingEfficiency(_, let name):
            "The dataset doesn't list consumption for the \(name). Pick a similar configuration or enter the rating yourself."
        case .negativeEnergyPrice:
            "An energy price can't be negative."
        case .zeroEnergyPrice(let fuel):
            "\(fuel) is priced at zero, so running costs for that vehicle will show as free."
        case .horizonShorterThanLoan:
            "Your ownership horizon is shorter than the loan term, so only the interest paid by then is counted."
        }
    }

    /// Whether the issue prevents a result or merely qualifies it.
    public var isBlocking: Bool {
        switch self {
        case .zeroAnnualDistance, .negativePrice, .implausiblePrice, .missingEfficiency, .negativeEnergyPrice:
            true
        case .zeroEnergyPrice, .horizonShorterThanLoan:
            false
        }
    }
}

public enum ScenarioValidator {

    /// Anything beyond this is far more likely to be a typo than a car.
    static let maximumPlausiblePrice: Double = 2_000_000

    public static func validate(_ scenario: ComparisonScenario) -> [ScenarioValidationIssue] {
        var issues: [ScenarioValidationIssue] = []

        if scenario.driving.annualKilometres <= 0 {
            issues.append(.zeroAnnualDistance)
        }

        for (identifier, side) in [(ComparisonSideIdentifier.a, scenario.sideA), (.b, scenario.sideB)] {
            let price = side.acquisition.purchasePrice
            if price < 0 {
                issues.append(.negativePrice(side: identifier))
            } else if price > maximumPlausiblePrice {
                issues.append(.implausiblePrice(side: identifier, value: price))
            }

            let efficiency = side.vehicle.efficiency
            let hasFuel = efficiency.combinedLPer100Km != nil || efficiency.cityLPer100Km != nil
            let hasElectric = efficiency.combinedKwhPer100Km != nil || efficiency.cityKwhPer100Km != nil
            let satisfied = switch side.vehicle.powertrain {
            case .bev: hasElectric
            case .phev: hasFuel && hasElectric
            case .gasoline, .diesel, .hybrid, .other: hasFuel
            }
            if !satisfied {
                issues.append(.missingEfficiency(side: identifier, vehicleName: side.vehicle.shortDisplayName))
            }

            if side.financing.isFinanced, side.financing.termMonths > scenario.horizon.months_ {
                issues.append(.horizonShorterThanLoan)
            }
        }

        let prices = scenario.energyPrices
        if prices.gasolinePricePerLitre < 0 || prices.dieselPricePerLitre < 0
            || prices.chargingSources.contains(where: { $0.pricePerKWh < 0 }) {
            issues.append(.negativeEnergyPrice)
        }

        // A zero price is legal — some people genuinely charge for free — but it
        // is worth saying out loud rather than quietly producing a $0 running cost.
        let needsGas = [scenario.sideA, scenario.sideB].contains { $0.vehicle.powertrain.usesLiquidFuel }
        if needsGas, prices.gasolinePricePerLitre == 0 {
            issues.append(.zeroEnergyPrice(fuel: "Gasoline"))
        }
        let needsElectricity = [scenario.sideA, scenario.sideB].contains { $0.vehicle.powertrain.usesElectricity }
        if needsElectricity, prices.blendedElectricityPricePerKWh == 0 {
            issues.append(.zeroEnergyPrice(fuel: "Electricity"))
        }

        return Array(Set(issues)).sorted { $0.message < $1.message }
    }
}
