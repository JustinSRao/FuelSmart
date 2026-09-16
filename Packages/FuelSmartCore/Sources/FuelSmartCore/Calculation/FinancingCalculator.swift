import Foundation

/// Standard amortized-loan mathematics.
///
/// The critical rule this type exists to enforce: **only interest is a cost.**
/// The principal is already counted in net acquisition, so adding loan payments
/// to the cumulative curve would charge the user for the car twice. The monthly
/// payment is computed for display, and the *interest* portion alone feeds the
/// cost model.
public enum FinancingCalculator {

    /// Build the amortization schedule for one side.
    ///
    /// - Parameters:
    ///   - acquisition: the net acquisition cost the loan is taken against.
    ///   - financing: the user's loan terms. A zero term means a cash purchase.
    ///   - months: how many months of cumulative interest to tabulate.
    public static func breakdown(
        acquisition: Double,
        financing: FinancingProfile,
        months: Int
    ) -> FinancingBreakdown {
        let tabulated = max(months, 0)

        // A cash purchase, a zero-length term, or a down payment that already
        // covers the price: no loan exists, so no interest is charged.
        guard financing.isFinanced else {
            return FinancingBreakdown(
                financedPrincipal: 0, monthlyPayment: 0, totalInterest: 0,
                termMonths: 0, cumulativeInterestByMonth: Array(repeating: 0, count: tabulated + 1)
            )
        }

        let principal = max(acquisition - financing.downPayment, 0)
        guard principal > 0 else {
            return FinancingBreakdown(
                financedPrincipal: 0, monthlyPayment: 0, totalInterest: 0,
                termMonths: financing.termMonths,
                cumulativeInterestByMonth: Array(repeating: 0, count: tabulated + 1)
            )
        }

        let term = financing.termMonths
        let monthlyRate = financing.annualPercentageRate / 12

        // 0% APR is a real and common promotional offer, and the amortization
        // formula divides by zero there, so it gets its own branch.
        guard monthlyRate > 0 else {
            let payment = principal / Double(term)
            return FinancingBreakdown(
                financedPrincipal: principal,
                monthlyPayment: payment,
                totalInterest: 0,
                termMonths: term,
                cumulativeInterestByMonth: Array(repeating: 0, count: tabulated + 1)
            )
        }

        // Standard amortized payment:
        //     P = principal × r / (1 − (1 + r)^−n)
        let growth = pow(1 + monthlyRate, Double(term))
        let payment = principal * monthlyRate * growth / (growth - 1)

        // Walk the schedule month by month. Interest each month is charged on
        // the balance outstanding at the start of that month, so a horizon
        // shorter than the term charges only the interest actually accrued —
        // which is front-loaded, not linear.
        var balance = principal
        var interestToDate: Double = 0
        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(tabulated + 1)

        for month in 1...max(tabulated, 1) {
            if month <= term, balance > 0 {
                let interest = balance * monthlyRate
                let principalPortion = payment - interest
                interestToDate += interest
                balance = max(balance - principalPortion, 0)
            }
            if month <= tabulated {
                cumulative.append(interestToDate)
            }
        }
        while cumulative.count <= tabulated {
            cumulative.append(interestToDate)
        }

        // Total interest over the full term, independent of the tabulated window.
        let totalInterest = payment * Double(term) - principal

        return FinancingBreakdown(
            financedPrincipal: principal,
            monthlyPayment: payment,
            totalInterest: max(totalInterest, 0),
            termMonths: term,
            cumulativeInterestByMonth: cumulative
        )
    }

    /// Outstanding balance after a number of payments, for display.
    public static func remainingBalance(
        principal: Double,
        annualPercentageRate: Double,
        termMonths: Int,
        afterMonths months: Int
    ) -> Double {
        guard principal > 0, termMonths > 0, months < termMonths else { return 0 }
        guard months > 0 else { return principal }

        let rate = annualPercentageRate / 12
        guard rate > 0 else {
            return max(principal - principal / Double(termMonths) * Double(months), 0)
        }
        let growthTerm = pow(1 + rate, Double(termMonths))
        let growthPaid = pow(1 + rate, Double(months))
        // Balance = P × ((1+r)^n − (1+r)^m) / ((1+r)^n − 1)
        return max(principal * (growthTerm - growthPaid) / (growthTerm - 1), 0)
    }
}
