import Foundation

/// Finds the point, if any, at which two cumulative cost curves cross.
///
/// Deliberately makes no assumption about which vehicle is which. Neither side
/// is presumed to be electric, cheaper, more efficient, or destined to catch up.
/// Five genuinely different outcomes are possible and all five are real answers:
///
/// 1. B costs more up front but less to run — it may cross, or may not within
///    the period.
/// 2. B costs less up front *and* less to run — it starts ahead and stays ahead.
/// 3. B costs more up front *and* more to run — it never catches up.
/// 4. B costs less up front but more to run — its early lead can be lost, so the
///    crossing runs the other way.
/// 5. The two are identical.
///
/// The search walks the simulated curves rather than solving Δacquisition ÷
/// Δannual, because financing interest is front-loaded and non-linear: the
/// closed form silently gives the wrong month whenever a loan is involved.
public enum BreakEvenCalculator {

    /// Below this, two costs are the same money.
    private static let tolerance = 0.005

    public static func analyse(
        sideA: SideResult,
        sideB: SideResult,
        driving: DrivingProfile,
        startDate: Date,
        horizonMonths: Int,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> BreakEvenResult {

        let initialDifference = sideB.netAcquisitionCost - sideA.netAcquisitionCost
        let months = min(sideA.cumulativePoints.count, sideB.cumulativePoints.count) - 1

        guard months > 0 else {
            return BreakEvenResult(
                status: .insufficientData,
                initialDifference: initialDifference,
                explanation: "There isn't enough information yet to compare these vehicles over time."
            )
        }

        // Zero distance makes every per-distance figure undefined, and a
        // break-even distance meaningless. The UI blocks this at input; the
        // engine refuses it rather than returning a confident zero.
        guard driving.annualKilometres > 0 else {
            return BreakEvenResult(
                status: .insufficientData,
                initialDifference: initialDifference,
                explanation: "Enter an annual driving distance above zero to compare running costs."
            )
        }

        func difference(at month: Int) -> Double {
            sideA.cost(atMonth: month) - sideB.cost(atMonth: month)
        }

        let startDelta = difference(at: 0)
        let endDelta = difference(at: months)

        // Identical throughout: check the endpoints and the midpoint, which is
        // enough for two curves that are each monotonic in month.
        if abs(startDelta) < tolerance,
           abs(endDelta) < tolerance,
           abs(difference(at: months / 2)) < tolerance {
            return BreakEvenResult(
                status: .identical,
                month: 0,
                kilometres: 0,
                estimatedDate: startDate,
                costAtIntersection: sideA.cost(atMonth: 0),
                initialDifference: initialDifference,
                explanation: "Both vehicles cost the same under these assumptions, at every point in the period."
            )
        }

        // Look for a sign change in the difference between the two curves.
        var crossingMonth: Int?
        var previous = startDelta
        for month in 1...months {
            let current = difference(at: month)
            let crossed = (previous < -tolerance && current >= -tolerance)
                || (previous > tolerance && current <= tolerance)
            if crossed {
                // Pick whichever of the two bracketing months is nearer to level,
                // so the reported month is the one the user would recognise.
                crossingMonth = abs(current) <= abs(previous) ? month : month - 1
                break
            }
            previous = current
        }

        if let crossingMonth {
            let kilometres = driving.annualKilometres * Double(crossingMonth) / 12
            let date = calendar.date(byAdding: .month, value: crossingMonth, to: startDate)
            let cost = (sideA.cost(atMonth: crossingMonth) + sideB.cost(atMonth: crossingMonth)) / 2

            // `startDelta` is A minus B, so a positive value means A is the one
            // that begins more expensive — and therefore the one doing the
            // catching up. Getting this backwards would name the wrong vehicle
            // in every break-even sentence the app prints.
            let catchingUp: SideResult = startDelta > 0 ? sideA : sideB
            let result = BreakEvenResult(
                status: .breakEvenOccurs,
                month: crossingMonth,
                kilometres: kilometres,
                estimatedDate: date,
                costAtIntersection: cost,
                initialDifference: initialDifference,
                explanation: ""
            )
            var described = result
            described.explanation = explanationForCrossing(
                catchingUp: catchingUp,
                duration: result.durationDescription ?? "the crossover point",
                kilometres: kilometres,
                date: date,
                horizonMonths: horizonMonths,
                crossingMonth: crossingMonth,
                calendar: calendar
            )
            return described
        }

        // No crossing inside the simulated period. Distinguish "will never
        // happen" from "happens later than we simulated" by asking whether the
        // gap is closing.
        let converging = abs(endDelta) < abs(startDelta) - tolerance
        let cheaperThroughout: ComparisonSideIdentifier = startDelta > 0 ? .b : .a
        let cheaperName = (cheaperThroughout == .a ? sideA : sideB).vehicle.shortDisplayName
        let otherName = (cheaperThroughout == .a ? sideB : sideA).vehicle.shortDisplayName

        if converging {
            return BreakEvenResult(
                status: .noCrossingWithinHorizon,
                initialDifference: initialDifference,
                explanation: "The gap is narrowing, but the \(otherName) does not catch up with the "
                    + "\(cheaperName) within \(months / 12) years under these assumptions."
            )
        }

        return BreakEvenResult(
            status: cheaperThroughout == .a ? .vehicleAAlwaysAhead : .vehicleBAlwaysAhead,
            initialDifference: initialDifference,
            explanation: "The \(cheaperName) costs less at the start and stays less expensive for the "
                + "whole period. The \(otherName) costs more up front and more to run, so there is no "
                + "crossover point."
        )
    }

    private static func explanationForCrossing(
        catchingUp: SideResult,
        duration: String,
        kilometres: Double,
        date: Date?,
        horizonMonths: Int,
        crossingMonth: Int,
        calendar: Calendar
    ) -> String {
        let name = catchingUp.vehicle.shortDisplayName
        var sentence = "The \(name) catches up after about \(duration.lowercased())"

        let distance = Int((kilometres / 100).rounded() * 100)
        if distance > 0 {
            sentence += " — around \(distance.formatted(.number.grouping(.automatic))) km"
        }
        if let date {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.dateFormat = "LLLL yyyy"
            sentence += ", roughly \(formatter.string(from: date))"
        }
        sentence += "."

        if crossingMonth > horizonMonths {
            sentence += " That is after the \(horizonMonths / 12)-year horizon you selected."
        }
        return sentence
    }
}
