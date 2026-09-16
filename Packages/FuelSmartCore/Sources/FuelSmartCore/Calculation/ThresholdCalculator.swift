import Foundation

/// Answers questions in reverse: *what value would put these two vehicles level
/// at the selected horizon?*
///
/// A closed form exists only when the model is linear in the variable, and it
/// stops being linear the moment financing interest or a resale credit is
/// involved. Rather than maintain two versions of the truth, every threshold
/// here is found by numerically solving the *same* engine the results screen
/// uses. That is slower — a few dozen evaluations — and always correct.
///
/// Every answer is a sensitivity, not a prediction. FuelSmart contains no
/// forecast of fuel prices, electricity prices or depreciation.
public struct ThresholdCalculator: Sendable {

    private let engine = ScenarioCalculator()

    public init() {}

    /// What a threshold search concluded.
    public enum Outcome: Sendable, Hashable {
        /// A value inside the searched range makes the two level.
        case solution(Double)
        /// No value in the range levels them; the named side stays cheaper
        /// across the whole range.
        case noSolutionInRange(cheaperThroughout: ComparisonSideIdentifier, searched: ClosedRange<Double>)
        /// They are already level, or the inputs cannot support a search.
        case alreadyLevel
        case insufficientData
    }

    /// The variable being solved for.
    public enum Variable: Sendable, Hashable, CaseIterable {
        case gasolinePricePerLitre
        case blendedElectricityPricePerKWh
        case annualKilometres
        case purchasePriceB
        case purchasePriceA

        public var displayName: String {
            switch self {
            case .gasolinePricePerLitre: "Break-even gas price"
            case .blendedElectricityPricePerKWh: "Break-even electricity price"
            case .annualKilometres: "Break-even distance"
            case .purchasePriceB: "Break-even purchase price"
            case .purchasePriceA: "Break-even purchase price"
            }
        }

        /// The range searched, in canonical units. Wide enough to cover any
        /// realistic market, narrow enough that a solution outside it is better
        /// reported as "no solution" than as a fantasy number.
        var searchRange: ClosedRange<Double> {
            switch self {
            case .gasolinePricePerLitre: 0...10
            case .blendedElectricityPricePerKWh: 0...3
            case .annualKilometres: 0...200_000
            case .purchasePriceB, .purchasePriceA: 0...ScenarioValidator.maximumPlausiblePrice
            }
        }
    }

    /// Solve for the value of `variable` that levels the two vehicles at the
    /// scenario's horizon.
    public func solve(for variable: Variable, in scenario: ComparisonScenario) -> Outcome {
        guard scenario.driving.annualKilometres > 0 || variable == .annualKilometres else {
            return .insufficientData
        }

        let range = variable.searchRange

        /// Signed gap at the horizon: positive means A costs more.
        func gap(at value: Double) -> Double {
            let result = engine.evaluate(apply(value, of: variable, to: scenario))
            return result.totalA - result.totalB
        }

        let low = gap(at: range.lowerBound)
        let high = gap(at: range.upperBound)

        if abs(gap(at: currentValue(of: variable, in: scenario))) < 0.5 {
            return .alreadyLevel
        }

        // A sign change across the range is what guarantees a crossing inside it.
        guard (low < 0 && high > 0) || (low > 0 && high < 0) else {
            // The same side is cheaper at both ends, so it is cheaper throughout
            // for any monotonic relationship — which all of these are.
            let cheaper: ComparisonSideIdentifier = low > 0 ? .b : .a
            return .noSolutionInRange(cheaperThroughout: cheaper, searched: range)
        }

        // Bisection: robust, needs no derivative, and cannot diverge. Fifty
        // iterations resolve any of these ranges to well below a cent.
        var lower = range.lowerBound
        var upper = range.upperBound
        var lowerGap = low

        for _ in 0..<50 {
            let midpoint = (lower + upper) / 2
            let midGap = gap(at: midpoint)
            if abs(midGap) < 0.01 || (upper - lower) < 1e-6 {
                return .solution(midpoint)
            }
            if (midGap < 0) == (lowerGap < 0) {
                lower = midpoint
                lowerGap = midGap
            } else {
                upper = midpoint
            }
        }
        return .solution((lower + upper) / 2)
    }

    // MARK: - Variable plumbing

    private func currentValue(of variable: Variable, in scenario: ComparisonScenario) -> Double {
        switch variable {
        case .gasolinePricePerLitre: scenario.energyPrices.gasolinePricePerLitre
        case .blendedElectricityPricePerKWh: scenario.energyPrices.blendedElectricityPricePerKWh
        case .annualKilometres: scenario.driving.annualKilometres
        case .purchasePriceB: scenario.sideB.acquisition.purchasePrice
        case .purchasePriceA: scenario.sideA.acquisition.purchasePrice
        }
    }

    private func apply(_ value: Double, of variable: Variable, to scenario: ComparisonScenario) -> ComparisonScenario {
        var updated = scenario
        switch variable {
        case .gasolinePricePerLitre:
            updated.energyPrices.gasolinePricePerLitre = value
        case .blendedElectricityPricePerKWh:
            // Scale every charging source so the *blend* lands on the target
            // while the home/public ratio the user chose is preserved.
            let current = scenario.energyPrices.blendedElectricityPricePerKWh
            if current > 0 {
                let factor = value / current
                updated.energyPrices.chargingSources = scenario.energyPrices.chargingSources.map {
                    var source = $0
                    source.pricePerKWh *= factor
                    return source
                }
            } else {
                updated.energyPrices.chargingSources = scenario.energyPrices.chargingSources.map {
                    var source = $0
                    source.pricePerKWh = value
                    return source
                }
            }
        case .annualKilometres:
            updated.driving.annualKilometres = value
        case .purchasePriceB:
            updated.sideB.acquisition.purchasePrice = value
        case .purchasePriceA:
            updated.sideA.acquisition.purchasePrice = value
        }
        return updated
    }

    /// Solve for the ownership duration at which the two are level.
    ///
    /// Handled separately because the horizon is a whole number of months rather
    /// than a continuous quantity, so this is a scan of the existing curve rather
    /// than a bisection.
    public func breakEvenDuration(in scenario: ComparisonScenario) -> BreakEvenResult {
        engine.evaluate(scenario).breakEven
    }
}
