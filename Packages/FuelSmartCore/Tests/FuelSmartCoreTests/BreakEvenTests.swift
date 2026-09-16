import Testing
import Foundation
@testable import FuelSmartCore

/// The break-even engine must never assume that one side is electric, cheaper,
/// or destined to catch up. Each of the five possible outcomes is exercised.
@Suite("Break-even")
struct BreakEvenTests {

    private let engine = ScenarioCalculator()

    // MARK: - Case 1: pricier up front, cheaper to run — crosses

    @Test("A vehicle that costs more up front but less to run eventually crosses")
    func crossingOccurs() {
        let result = engine.evaluate(Fixtures.hybridVersusElectric())

        #expect(result.breakEven.status == .breakEvenOccurs)
        // $5,290 of extra acquisition repaid at $964.2312 a year → 5.486 years,
        // which lands in month 66.
        #expect(result.breakEven.month == 66)
        #expect(result.breakEven.durationDescription == "5 years 6 months")
        // 18,000 km/year × 66/12 months = 99,000 km
        #expect(abs(result.breakEven.kilometres! - 99_000) < 1e-6)
        #expect(abs(result.breakEven.initialDifference - 5_290) < 1e-9)
    }

    @Test("The break-even date is derived from the start date, not the clock")
    func breakEvenDate() {
        let result = engine.evaluate(Fixtures.hybridVersusElectric())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // January 2026 + 66 months = July 2031
        let components = calendar.dateComponents([.year, .month], from: result.breakEven.estimatedDate!)
        #expect(components.year == 2031)
        #expect(components.month == 7)
    }

    @Test("A crossing beyond the chosen horizon is reported, not hidden")
    func crossingBeyondHorizon() {
        let result = engine.evaluate(Fixtures.hybridVersusElectric(horizon: .threeYears))
        #expect(result.breakEven.status == .breakEvenOccurs)
        #expect(result.breakEven.month == 66)
        #expect(result.breakEven.explanation.contains("after the 3-year horizon"))
    }

    // MARK: - Case 2: cheaper both ways — starts ahead, stays ahead

    @Test("Cheaper up front and cheaper to run means no crossover at all")
    func alwaysAhead() {
        // Hybrid costs less to buy than the thirsty diesel truck and less to run.
        let scenario = ComparisonScenario(
            mode: .buyVsBuy,
            region: .canada,
            sideA: Fixtures.side(Fixtures.dieselTruck, price: 78_000),
            sideB: Fixtures.side(Fixtures.hybridSedan, price: 41_000),
            driving: Fixtures.standardDriving,
            energyPrices: Fixtures.standardPrices,
            startDate: Fixtures.fixedStartDate
        )
        let result = engine.evaluate(scenario)

        #expect(result.breakEven.status == .vehicleBAlwaysAhead)
        #expect(result.breakEven.month == nil)
        #expect(result.breakEven.explanation.contains("no crossover point"))
    }

    // MARK: - Case 3: pricier both ways — never catches up

    @Test("More expensive up front and to run is a real answer, not an error")
    func neverCatchesUp() {
        let scenario = ComparisonScenario(
            mode: .buyVsBuy,
            region: .canada,
            sideA: Fixtures.side(Fixtures.hybridSedan, price: 41_000),
            sideB: Fixtures.side(Fixtures.dieselTruck, price: 78_000),
            driving: Fixtures.standardDriving,
            energyPrices: Fixtures.standardPrices,
            startDate: Fixtures.fixedStartDate
        )
        let result = engine.evaluate(scenario)

        #expect(result.breakEven.status == .vehicleAAlwaysAhead)
        #expect(result.breakEven.month == nil)
    }

    // MARK: - Case 4: cheaper up front but pricier to run — loses its lead

    @Test("A cheap-to-buy, costly-to-run vehicle can lose its early lead")
    func earlyLeadIsLost() {
        // The truck is $2,000 cheaper to buy but far costlier to run, so the
        // hybrid overtakes it — the crossing runs the opposite direction to the
        // usual EV story.
        let scenario = ComparisonScenario(
            mode: .buyVsBuy,
            region: .canada,
            sideA: Fixtures.side(Fixtures.hybridSedan, price: 43_000),
            sideB: Fixtures.side(Fixtures.dieselTruck, price: 41_000),
            driving: Fixtures.standardDriving,
            energyPrices: Fixtures.standardPrices,
            startDate: Fixtures.fixedStartDate
        )
        let result = engine.evaluate(scenario)

        #expect(result.breakEven.status == .breakEvenOccurs)
        #expect(result.breakEven.month! > 0)
        // B starts $2,000 cheaper, so the initial difference is negative.
        #expect(result.breakEven.initialDifference < 0)
        // The vehicle that catches up here is A, the hybrid.
        #expect(result.breakEven.explanation.contains(Fixtures.hybridSedan.shortDisplayName))
    }

    // MARK: - Case 5: identical

    @Test("Two identical vehicles are reported as identical, not as an instant break-even")
    func identicalVehicles() {
        let scenario = ComparisonScenario(
            mode: .buyVsBuy,
            region: .canada,
            sideA: Fixtures.side(Fixtures.hybridSedan, price: 41_000),
            sideB: Fixtures.side(Fixtures.hybridSedan, price: 41_000),
            driving: Fixtures.standardDriving,
            energyPrices: Fixtures.standardPrices,
            startDate: Fixtures.fixedStartDate
        )
        let result = engine.evaluate(scenario)

        #expect(result.breakEven.status == .identical)
        #expect(result.costDifferenceAtHorizon < 0.005)
        #expect(result.cheaperSideAtHorizon == nil)
    }

    // MARK: - Insufficient data

    @Test("Zero annual distance is refused rather than answered with a confident zero")
    func zeroDistanceIsInsufficient() {
        let scenario = Fixtures.hybridVersusElectric(
            driving: DrivingProfile(annualKilometres: 0)
        )
        let result = engine.evaluate(scenario)

        #expect(result.breakEven.status == .insufficientData)
        #expect(result.breakEven.month == nil)
        #expect(ScenarioValidator.validate(scenario).contains(.zeroAnnualDistance))
    }

    @Test("A gap that narrows without closing is distinguished from one that never closes")
    func convergingButNotCrossing() {
        // A huge acquisition gap with a small running-cost advantage: the curves
        // converge but do not meet inside the simulated ten years.
        let scenario = ComparisonScenario(
            mode: .buyVsBuy,
            region: .canada,
            sideA: Fixtures.side(Fixtures.hybridSedan, price: 30_000),
            sideB: Fixtures.side(Fixtures.batteryElectric, price: 95_000),
            driving: Fixtures.standardDriving,
            energyPrices: Fixtures.standardPrices,
            startDate: Fixtures.fixedStartDate
        )
        let result = engine.evaluate(scenario)

        #expect(result.breakEven.status == .noCrossingWithinHorizon)
        #expect(result.breakEven.explanation.contains("narrowing"))
    }

    // MARK: - Energy-only analysis

    @Test("Energy-only break-even ignores recurring costs and financing")
    func energyOnlyIsIndependent() {
        var scenario = Fixtures.hybridVersusElectric()
        scenario.sideA.recurringCosts = RecurringCostProfile(annualInsurance: 1_420, annualMaintenance: 620)
        scenario.sideB.recurringCosts = RecurringCostProfile(annualInsurance: 1_740, annualMaintenance: 310)

        let result = engine.evaluate(scenario)
        let plain = engine.evaluate(Fixtures.hybridVersusElectric())

        // The full analysis now reflects the extra costs...
        #expect(result.breakEven.month != plain.breakEven.month)
        // ...while the energy-only view matches the untouched comparison.
        #expect(result.energyOnlyBreakEven.month == plain.energyOnlyBreakEven.month)
        #expect(result.energyOnlyBreakEven.month == 66)
    }
}
