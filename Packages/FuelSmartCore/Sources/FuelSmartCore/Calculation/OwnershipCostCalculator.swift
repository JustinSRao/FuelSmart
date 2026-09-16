import Foundation

/// Builds the month-by-month cumulative cost curve for one vehicle.
///
/// The curve is the single source of truth for the chart, the totals, the
/// breakdown and the break-even search — everything reads the same simulation,
/// so no two parts of the app can disagree about a number.
///
/// Shape of the model, per the design's stated rules:
///
///     cost(month) = net acquisition                      (charged at month 0)
///                 + cumulative financing interest(month)
///                 + energy × month/12
///                 + recurring × month/12
///
/// Resale is deliberately *not* here. It is a single credit applied once at the
/// horizon, never amortized into the curve, because amortizing it would make a
/// vehicle look progressively cheaper to run than it is.
public enum OwnershipCostCalculator {

    public static func simulate(
        side: ComparisonSide,
        driving: DrivingProfile,
        prices: EnergyPriceProfile,
        months: Int
    ) -> SideResult {
        let totalMonths = max(months, 0)

        let energy = EnergyCostCalculator.breakdown(for: side, driving: driving, prices: prices)

        // Sunk-cost rule: a vehicle the user already owns contributes no
        // acquisition cost at all, and therefore carries no loan either.
        let acquisition = side.chargeableAcquisition
        let financing = side.isAlreadyOwned
            ? FinancingBreakdown.none
            : FinancingCalculator.breakdown(acquisition: acquisition, financing: side.financing, months: totalMonths)

        let recurring = side.recurringCosts

        // Monthly rates. Annual figures are divided by twelve rather than
        // charged in a lump, so the curve is smooth and a partial year is
        // charged proportionally.
        let monthlyFuel = energy.annualFuelCost / 12
        let monthlyElectricity = energy.annualElectricityCost / 12
        let monthlyInsurance = (recurring.annualInsurance ?? 0) / 12
        let monthlyMaintenance = (recurring.annualMaintenance ?? 0) / 12
        let monthlyRegistration = (recurring.annualRegistration ?? 0) / 12
        let monthlyParking = (recurring.annualParking ?? 0) / 12
        let monthlyOther = (recurring.annualOther ?? 0) / 12
        let monthlyKilometres = driving.annualKilometres / 12

        // One-time costs that are part of acquisition are already inside
        // `acquisition.net`; tracked separately here only so the breakdown chart
        // can show them apart from the vehicle price itself.
        let oneTimeExtras = side.isAlreadyOwned
            ? 0
            : side.acquisition.homeChargerInstallation
                + side.acquisition.electricalPanelUpgrade
                + side.acquisition.otherOneTimeCost
        let acquisitionOnly = acquisition - oneTimeExtras

        var points: [CumulativeCostPoint] = []
        points.reserveCapacity(totalMonths + 1)

        for month in 0...max(totalMonths, 0) {
            let elapsed = Double(month)
            var categories: [CostCategory: Double] = [
                .acquisition: acquisitionOnly,
                .oneTimeCosts: oneTimeExtras,
                .financingInterest: financing.cumulativeInterest(atMonth: month),
                .fuel: monthlyFuel * elapsed,
                .electricity: monthlyElectricity * elapsed,
            ]
            if recurring.annualInsurance != nil { categories[.insurance] = monthlyInsurance * elapsed }
            if recurring.annualMaintenance != nil { categories[.maintenance] = monthlyMaintenance * elapsed }
            if recurring.annualRegistration != nil { categories[.registration] = monthlyRegistration * elapsed }
            if recurring.annualParking != nil { categories[.parking] = monthlyParking * elapsed }
            if recurring.annualOther != nil { categories[.otherRecurring] = monthlyOther * elapsed }

            let total = categories.reduce(0) { $0 + $1.value }
            points.append(CumulativeCostPoint(
                month: month,
                kilometres: monthlyKilometres * elapsed,
                cumulativeCost: total,
                byCategory: categories
            ))
        }

        // The resale credit only exists if the user supplied one and asked for
        // it to be counted. FuelSmart never invents a depreciation curve.
        let resaleCredit: Double = {
            guard let resale = side.resale, resale.isIncludedInTotals else { return 0 }
            return max(resale.expectedValue, 0)
        }()

        return SideResult(
            vehicle: side.vehicle,
            netAcquisitionCost: acquisition,
            energy: energy,
            financing: financing,
            annualRecurringCost: recurring.annualTotal,
            resaleCredit: resaleCredit,
            cumulativePoints: points
        )
    }

    /// Rebuild a side's curve counting only acquisition and energy.
    ///
    /// Used for the energy-only break-even, which lets the user see the core
    /// gas-versus-electricity economics separately from softer assumptions like
    /// insurance and maintenance.
    public static func simulateEnergyOnly(
        side: ComparisonSide,
        driving: DrivingProfile,
        prices: EnergyPriceProfile,
        months: Int
    ) -> SideResult {
        var stripped = side
        stripped.recurringCosts = .empty
        stripped.resale = nil
        stripped.financing = .cash
        return simulate(side: stripped, driving: driving, prices: prices, months: months)
    }
}
