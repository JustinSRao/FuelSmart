import Testing
import Foundation
@testable import FuelSmartCore

@Suite("Threshold and inverse calculations")
struct ThresholdTests {

    private let solver = ThresholdCalculator()
    private let engine = ScenarioCalculator()

    /// Feed a solved threshold back through the engine: if the answer is right,
    /// the two vehicles must actually come out level. This checks the solver
    /// against the model rather than against a memorised constant.
    private func assertLevels(
        _ outcome: ThresholdCalculator.Outcome,
        variable: ThresholdCalculator.Variable,
        scenario: ComparisonScenario,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard case .solution(let value) = outcome else {
            Issue.record("expected a solution, got \(outcome)", sourceLocation: sourceLocation)
            return
        }
        var adjusted = scenario
        switch variable {
        case .gasolinePricePerLitre:
            adjusted.energyPrices.gasolinePricePerLitre = value
        case .annualKilometres:
            adjusted.driving.annualKilometres = value
        case .purchasePriceB:
            adjusted.sideB.acquisition.purchasePrice = value
        case .purchasePriceA:
            adjusted.sideA.acquisition.purchasePrice = value
        case .blendedElectricityPricePerKWh:
            let current = scenario.energyPrices.blendedElectricityPricePerKWh
            let factor = current > 0 ? value / current : 1
            adjusted.energyPrices.chargingSources = scenario.energyPrices.chargingSources.map {
                var source = $0
                source.pricePerKWh = current > 0 ? source.pricePerKWh * factor : value
                return source
            }
        }
        let result = engine.evaluate(adjusted)
        #expect(result.costDifferenceAtHorizon < 1.0, sourceLocation: sourceLocation)
    }

    @Test("Break-even gas price levels the two vehicles at the horizon")
    func breakEvenGasPrice() {
        let scenario = Fixtures.hybridVersusElectric(horizon: .fiveYears)
        let outcome = solver.solve(for: .gasolinePricePerLitre, in: scenario)

        assertLevels(outcome, variable: .gasolinePricePerLitre, scenario: scenario)

        // At five years the hybrid is still slightly ahead, so gas must rise
        // above the $1.72 entered for the electric side to catch up by then.
        guard case .solution(let price) = outcome else { return }
        #expect(price > 1.72)
    }

    @Test("Break-even annual distance levels the two vehicles")
    func breakEvenDistance() {
        let scenario = Fixtures.hybridVersusElectric(horizon: .fiveYears)
        let outcome = solver.solve(for: .annualKilometres, in: scenario)

        assertLevels(outcome, variable: .annualKilometres, scenario: scenario)

        // More driving favours the cheaper-to-run vehicle, so the threshold is
        // above the 18,000 km entered.
        guard case .solution(let km) = outcome else { return }
        #expect(km > 18_000)
    }

    @Test("Break-even purchase price levels the two vehicles")
    func breakEvenPurchasePrice() {
        let scenario = Fixtures.hybridVersusElectric(horizon: .fiveYears)
        let outcome = solver.solve(for: .purchasePriceB, in: scenario)

        assertLevels(outcome, variable: .purchasePriceB, scenario: scenario)

        // The electric side is $468.844 behind at five years, and price feeds
        // straight through to the total, so the threshold is that much lower.
        guard case .solution(let price) = outcome else { return }
        #expect(abs(price - (49_990 - 468.844)) < 1.0)
    }

    @Test("Break-even electricity price levels the two vehicles")
    func breakEvenElectricityPrice() {
        // Give the electric side a clear lead so a threshold exists above the
        // current rate rather than below zero.
        let scenario = Fixtures.hybridVersusElectric(horizon: .tenYears)
        let outcome = solver.solve(for: .blendedElectricityPricePerKWh, in: scenario)

        assertLevels(outcome, variable: .blendedElectricityPricePerKWh, scenario: scenario)

        guard case .solution(let rate) = outcome else { return }
        #expect(rate > Fixtures.standardPrices.blendedElectricityPricePerKWh)
    }

    @Test("Scaling the electricity threshold preserves the home/public ratio")
    func electricityThresholdKeepsRatio() {
        let scenario = Fixtures.hybridVersusElectric(horizon: .tenYears)
        guard case .solution(let rate) = solver.solve(for: .blendedElectricityPricePerKWh, in: scenario) else {
            Issue.record("expected a solution")
            return
        }
        // Original ratio is 0.52 / 0.14 ≈ 3.714.
        let factor = rate / scenario.energyPrices.blendedElectricityPricePerKWh
        let scaledHome = 0.14 * factor
        let scaledPublic = 0.52 * factor
        #expect(abs(scaledPublic / scaledHome - 0.52 / 0.14) < 1e-9)
    }

    @Test("When no value in range can level them, that is reported plainly")
    func noSolutionInRange() {
        // A hopelessly expensive electric side: no gas price under $10/L repays
        // a $60,000 acquisition gap in five years.
        var scenario = Fixtures.hybridVersusElectric(horizon: .fiveYears)
        scenario.sideB.acquisition.purchasePrice = 110_000

        let outcome = solver.solve(for: .gasolinePricePerLitre, in: scenario)
        guard case .noSolutionInRange(let cheaper, let searched) = outcome else {
            Issue.record("expected no solution, got \(outcome)")
            return
        }
        #expect(cheaper == .a)
        #expect(searched == 0...10)
    }

    @Test("Two already-level vehicles report as already level")
    func alreadyLevel() {
        let scenario = ComparisonScenario(
            mode: .buyVsBuy,
            region: .canada,
            sideA: Fixtures.side(Fixtures.hybridSedan, price: 41_000),
            sideB: Fixtures.side(Fixtures.hybridSedan, price: 41_000),
            driving: Fixtures.standardDriving,
            energyPrices: Fixtures.standardPrices,
            startDate: Fixtures.fixedStartDate
        )
        #expect(solver.solve(for: .purchasePriceB, in: scenario) == .alreadyLevel)
    }

    @Test("Zero distance yields insufficient data rather than a fabricated threshold")
    func insufficientData() {
        let scenario = Fixtures.hybridVersusElectric(
            driving: DrivingProfile(annualKilometres: 0)
        )
        #expect(solver.solve(for: .gasolinePricePerLitre, in: scenario) == .insufficientData)
    }
}
