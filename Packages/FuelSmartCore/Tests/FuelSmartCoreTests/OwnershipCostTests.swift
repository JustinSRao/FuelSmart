import Testing
import Foundation
@testable import FuelSmartCore

@Suite("Acquisition, ownership and resale")
struct OwnershipCostTests {

    private let engine = ScenarioCalculator()

    // MARK: - Net acquisition

    @Test("Net acquisition adds costs and subtracts credits")
    func netAcquisition() {
        let cost = AcquisitionCost(
            purchasePrice: 49_990,
            salesTax: 2_600,
            dealerFees: 599,
            rebate: 5_000,
            governmentIncentive: 2_000,
            tradeInValue: 8_000,
            homeChargerInstallation: 1_200
        )
        // 49,990 + 2,600 + 599 + 1,200 = 54,389 in
        // 5,000 + 2,000 + 8,000       = 15,000 out
        #expect(cost.totalAdditions == 54_389)
        #expect(cost.totalDeductions == 15_000)
        #expect(cost.net == 39_389)
    }

    @Test("Incentives larger than the price make the car free, not profitable")
    func incentivesCannotGoNegative() {
        let cost = AcquisitionCost(purchasePrice: 10_000, rebate: 15_000)
        #expect(cost.net == 0)
    }

    @Test("Every advanced field is optional and defaults to no effect")
    func advancedFieldsAreOptional() {
        let cost = AcquisitionCost(purchasePrice: 30_000)
        #expect(cost.net == 30_000)
    }

    // MARK: - Keep vs replace

    @Test("A vehicle already owned contributes no acquisition cost")
    func sunkCostIsExcluded() {
        let kept = Fixtures.side(Fixtures.hybridSedan, price: 41_000, isAlreadyOwned: true)
        let result = OwnershipCostCalculator.simulate(
            side: kept, driving: Fixtures.standardDriving,
            prices: Fixtures.standardPrices, months: 120
        )
        #expect(result.netAcquisitionCost == 0)
        #expect(result.cost(atMonth: 0) == 0)
        // Five years of energy only: $1,544.904 × 5
        #expect(abs(result.cost(atMonth: 60) - 7_724.52) < 1e-6)
    }

    @Test("Keep vs replace charges only the replacement, net of trade-in")
    func keepVsReplace() {
        let scenario = ComparisonScenario(
            mode: .keepVsReplace,
            region: .canada,
            sideA: Fixtures.side(Fixtures.hybridSedan, price: 41_000, isAlreadyOwned: true),
            sideB: Fixtures.side(
                Fixtures.batteryElectric, price: 49_990, fees: 2_600,
                rebate: 5_000, charger: 1_200, tradeIn: 14_000
            ),
            driving: Fixtures.standardDriving,
            energyPrices: Fixtures.standardPrices,
            startDate: Fixtures.fixedStartDate
        )
        let result = engine.evaluate(scenario)

        #expect(result.sideA.netAcquisitionCost == 0)
        // 49,990 + 2,600 + 1,200 − 5,000 − 14,000 = 34,790
        #expect(result.sideB.netAcquisitionCost == 34_790)
        #expect(abs(result.breakEven.initialDifference - 34_790) < 1e-9)
    }

    @Test("A kept vehicle carries no loan even if one is configured")
    func keptVehicleHasNoFinancing() {
        let kept = Fixtures.side(
            Fixtures.hybridSedan, price: 41_000,
            financing: FinancingProfile(downPayment: 0, annualPercentageRate: 0.07, termMonths: 60),
            isAlreadyOwned: true
        )
        let result = OwnershipCostCalculator.simulate(
            side: kept, driving: Fixtures.standardDriving,
            prices: Fixtures.standardPrices, months: 120
        )
        #expect(result.financing.totalInterest == 0)
        #expect(result.financing.cumulativeInterest(atMonth: 60) == 0)
    }

    // MARK: - Recurring costs

    @Test("Recurring costs stay out of the total until the user supplies one")
    func recurringCostsAreOptional() {
        #expect(RecurringCostProfile.empty.isEnabled == false)
        #expect(RecurringCostProfile(annualInsurance: 1_200).isEnabled == true)
        // A supplied zero still counts as supplied — the user said "nothing",
        // which is different from "unknown".
        #expect(RecurringCostProfile(annualMaintenance: 0).isEnabled == true)
    }

    @Test("The headline is labelled honestly according to what was entered")
    func costLabelling() {
        let plain = Fixtures.hybridVersusElectric()
        #expect(plain.costLabel == "Purchase + energy cost")

        var withOwnership = plain
        withOwnership.sideA.recurringCosts = RecurringCostProfile(annualInsurance: 1_420)
        #expect(withOwnership.costLabel == "Estimated ownership cost")
    }

    @Test("Recurring costs accumulate monthly, not as a year-end lump")
    func recurringAccrual() {
        let side = Fixtures.side(
            Fixtures.hybridSedan, price: 41_000,
            recurring: RecurringCostProfile(annualInsurance: 1_200)
        )
        let result = OwnershipCostCalculator.simulate(
            side: side, driving: Fixtures.standardDriving,
            prices: Fixtures.standardPrices, months: 120
        )
        let insuranceAtSixMonths = result.categoryTotals(atMonth: 6)[.insurance]!
        #expect(abs(insuranceAtSixMonths - 600) < 1e-9)
    }

    // MARK: - Resale

    @Test("Resale is credited once at the horizon, never amortized into the curve")
    func resaleIsAnEndpointCredit() {
        var scenario = Fixtures.hybridVersusElectric()
        scenario.sideA.resale = ResaleAssumption(expectedValue: 21_500)

        let result = engine.evaluate(scenario)
        let plain = engine.evaluate(Fixtures.hybridVersusElectric())

        // The curve itself is unchanged at every month...
        #expect(abs(result.sideA.cost(atMonth: 60) - plain.sideA.cost(atMonth: 60)) < 1e-9)
        #expect(abs(result.sideA.cost(atMonth: 24) - plain.sideA.cost(atMonth: 24)) < 1e-9)
        // ...and the credit applies only to the horizon total.
        #expect(abs(result.totalA - (plain.totalA - 21_500)) < 1e-9)
    }

    @Test("A resale figure recorded but switched off changes nothing")
    func resaleCanBeExcluded() {
        var scenario = Fixtures.hybridVersusElectric()
        scenario.sideA.resale = ResaleAssumption(expectedValue: 21_500, isIncludedInTotals: false)

        let result = engine.evaluate(scenario)
        #expect(result.sideA.resaleCredit == 0)
        #expect(result.assumptions.includesResale == false)
    }

    // MARK: - Totals

    @Test("Horizon totals match a hand calculation")
    func horizonTotals() {
        let result = engine.evaluate(Fixtures.hybridVersusElectric(horizon: .fiveYears))

        // A: 43,500 acquisition + 1,544.904 × 5 = 51,224.52
        #expect(abs(result.totalA - 51_224.52) < 1e-6)
        // B: 48,790 acquisition +   580.6728 × 5 = 51,693.364
        #expect(abs(result.totalB - 51_693.364) < 1e-6)
        #expect(abs(result.costDifferenceAtHorizon - 468.844) < 1e-6)
        // A is still marginally cheaper at five years — the crossover is later.
        #expect(result.cheaperSideAtHorizon == .a)
    }

    @Test("Milestone totals are available for every standard horizon")
    func milestoneTotals() {
        let result = engine.evaluate(Fixtures.hybridVersusElectric())
        for years in [3, 5, 8, 10] {
            #expect(result.total(for: result.sideA, atYears: years) > 0)
            #expect(result.total(for: result.sideB, atYears: years) > 0)
        }
        // At ten years the electric side has pulled ahead.
        #expect(result.total(for: result.sideB, atYears: 10) < result.total(for: result.sideA, atYears: 10))
    }

    @Test("The simulation always covers at least ten years so a late crossing is visible")
    func simulationLength() {
        let short = Fixtures.hybridVersusElectric(horizon: .threeYears)
        #expect(short.simulationMonths == 120)

        var long = Fixtures.hybridVersusElectric()
        long.horizon = .years(15)
        #expect(long.simulationMonths == 180)
    }
}
