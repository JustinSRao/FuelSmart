import Testing
import Foundation
@testable import FuelSmartCore

@Suite("Financing")
struct FinancingTests {

    @Test("A cash purchase has no loan and no interest")
    func cashPurchase() {
        let breakdown = FinancingCalculator.breakdown(
            acquisition: 48_790, financing: .cash, months: 120
        )
        #expect(breakdown.financedPrincipal == 0)
        #expect(breakdown.monthlyPayment == 0)
        #expect(breakdown.totalInterest == 0)
        #expect(breakdown.cumulativeInterest(atMonth: 120) == 0)
    }

    @Test("Standard amortized loan: payment and total interest")
    func amortizedLoan() {
        // $48,790 net acquisition, $8,000 down → $40,790 financed
        // 5.9% APR over 60 months.
        let financing = FinancingProfile(downPayment: 8_000, annualPercentageRate: 0.059, termMonths: 60)
        let breakdown = FinancingCalculator.breakdown(
            acquisition: 48_790, financing: financing, months: 120
        )
        #expect(breakdown.financedPrincipal == 40_790)
        // P = 40790 × r / (1 − (1+r)^−60), r = 0.059/12
        #expect(abs(breakdown.monthlyPayment - 786.689684) < 1e-5)
        #expect(abs(breakdown.totalInterest - 6_411.381067) < 1e-4)
    }

    @Test("Interest is front-loaded, so a short horizon charges less than a linear share")
    func interestIsFrontLoaded() {
        let financing = FinancingProfile(downPayment: 8_000, annualPercentageRate: 0.059, termMonths: 60)
        let breakdown = FinancingCalculator.breakdown(
            acquisition: 48_790, financing: financing, months: 120
        )
        let atThreeYears = breakdown.cumulativeInterest(atMonth: 36)
        #expect(abs(atThreeYears - 5_298.861511) < 1e-4)

        // 36/60 of the term has elapsed but more than 60% of the interest is paid.
        let linearShare = breakdown.totalInterest * 36.0 / 60.0
        #expect(atThreeYears > linearShare)
    }

    @Test("Interest stops accruing once the loan is repaid")
    func interestStopsAtTermEnd() {
        let financing = FinancingProfile(downPayment: 0, annualPercentageRate: 0.059, termMonths: 60)
        let breakdown = FinancingCalculator.breakdown(
            acquisition: 30_000, financing: financing, months: 120
        )
        #expect(abs(breakdown.cumulativeInterest(atMonth: 60) - breakdown.cumulativeInterest(atMonth: 120)) < 1e-6)
    }

    @Test("Zero percent APR spreads the principal evenly and charges nothing")
    func zeroInterestLoan() {
        let financing = FinancingProfile(downPayment: 0, annualPercentageRate: 0, termMonths: 60)
        let breakdown = FinancingCalculator.breakdown(
            acquisition: 30_000, financing: financing, months: 120
        )
        #expect(breakdown.monthlyPayment == 500)
        #expect(breakdown.totalInterest == 0)
        #expect(breakdown.cumulativeInterest(atMonth: 60) == 0)
    }

    @Test("A down payment covering the whole price leaves nothing to finance")
    func fullyCoveredByDownPayment() {
        let financing = FinancingProfile(downPayment: 60_000, annualPercentageRate: 0.059, termMonths: 60)
        let breakdown = FinancingCalculator.breakdown(
            acquisition: 48_790, financing: financing, months: 120
        )
        #expect(breakdown.financedPrincipal == 0)
        #expect(breakdown.totalInterest == 0)
    }

    @Test("Only interest reaches the cost model; the principal is never charged twice")
    func principalIsNotDoubleCounted() {
        let financed = Fixtures.side(
            Fixtures.batteryElectric, price: 49_990, fees: 2_600, rebate: 5_000, charger: 1_200,
            financing: FinancingProfile(downPayment: 8_000, annualPercentageRate: 0.059, termMonths: 60)
        )
        let cash = Fixtures.side(
            Fixtures.batteryElectric, price: 49_990, fees: 2_600, rebate: 5_000, charger: 1_200
        )

        let financedResult = OwnershipCostCalculator.simulate(
            side: financed, driving: Fixtures.standardDriving, prices: Fixtures.standardPrices, months: 120
        )
        let cashResult = OwnershipCostCalculator.simulate(
            side: cash, driving: Fixtures.standardDriving, prices: Fixtures.standardPrices, months: 120
        )

        // Both start at the same net acquisition: financing changes when money
        // is paid, not how much car is bought.
        #expect(abs(financedResult.cost(atMonth: 0) - cashResult.cost(atMonth: 0)) < 1e-9)

        // The entire difference at any later month is exactly the interest.
        let delta = financedResult.cost(atMonth: 60) - cashResult.cost(atMonth: 60)
        #expect(abs(delta - financedResult.financing.cumulativeInterest(atMonth: 60)) < 1e-6)
    }

    @Test("Remaining balance falls from the full principal to zero at term end")
    func remainingBalance() {
        let start = FinancingCalculator.remainingBalance(
            principal: 40_790, annualPercentageRate: 0.059, termMonths: 60, afterMonths: 0
        )
        #expect(start == 40_790)

        let end = FinancingCalculator.remainingBalance(
            principal: 40_790, annualPercentageRate: 0.059, termMonths: 60, afterMonths: 60
        )
        #expect(end == 0)

        let midway = FinancingCalculator.remainingBalance(
            principal: 40_790, annualPercentageRate: 0.059, termMonths: 60, afterMonths: 30
        )
        #expect(midway > 0 && midway < 40_790)
        // Because interest is front-loaded, more than half the principal is
        // still outstanding halfway through the term.
        #expect(midway > 40_790 / 2)
    }
}
