import Foundation

/// Turns a vehicle's official ratings, the user's driving mix and the user's
/// energy prices into a cost per 100 km and a cost per year.
///
/// The whole calculator works in canonical metric units, so there is exactly one
/// implementation for both regions. A U.S. user's MPG became L/100 km at the
/// data-import boundary, and their $/gallon became $/litre at the input
/// boundary; nothing downstream knows or cares which country it is serving.
public enum EnergyCostCalculator {

    /// Blend a city and a highway rating according to the driving mix.
    ///
    ///     blended = city × cityShare + highway × highwaySplit
    ///
    /// Consumption rates in "per 100 km" form are per-distance quantities, so
    /// they blend linearly by distance share. (This is exactly why the engine
    /// stores L/100 km rather than MPG: averaging MPG by distance share would be
    /// wrong, because MPG is a reciprocal rate.)
    ///
    /// Returns `combined` when either split rating is missing — a graceful,
    /// reported fallback rather than a silent one.
    static func blend(
        city: Double?,
        highway: Double?,
        combined: Double?,
        split: Split
    ) -> (value: Double?, usedFallback: Bool) {
        if let city, let highway {
            return (city * split.primary + highway * split.secondary, false)
        }
        if let combined {
            return (combined, true)
        }
        // Some records carry only one of the two split figures; using it alone
        // is better than nothing and is still reported as a fallback.
        if let single = city ?? highway {
            return (single, true)
        }
        return (nil, false)
    }

    /// Apply the user's real-world adjustment.
    ///
    /// The adjustment raises *consumption*, which is what a cold battery or a
    /// heavy right foot actually does. It is never folded into the stored
    /// official rating — the government figure is left intact and the multiplier
    /// is reported with the result.
    static func adjusted(_ consumption: Double?, by adjustment: Double) -> Double? {
        guard let consumption else { return nil }
        return consumption * (1 + adjustment)
    }

    /// Energy economics for one side of a comparison.
    public static func breakdown(
        for side: ComparisonSide,
        driving: DrivingProfile,
        prices: EnergyPriceProfile
    ) -> EnergyCostBreakdown {
        let efficiency = side.vehicle.efficiency
        let powertrain = side.vehicle.powertrain
        let split = driving.cityHighwaySplit

        let fuelBlend = blend(
            city: efficiency.cityLPer100Km,
            highway: efficiency.highwayLPer100Km,
            combined: efficiency.combinedLPer100Km,
            split: split
        )
        let electricBlend = blend(
            city: efficiency.cityKwhPer100Km,
            highway: efficiency.highwayKwhPer100Km,
            combined: efficiency.combinedKwhPer100Km,
            split: split
        )

        let litresPer100Km = adjusted(fuelBlend.value, by: driving.realWorldAdjustment)
        let kWhPer100Km = adjusted(electricBlend.value, by: driving.realWorldAdjustment)

        let fuelPrice = powertrain.liquidFuelKind.map { prices.price(for: $0) } ?? 0
        let electricityPrice = prices.blendedElectricityPricePerKWh

        // How much of the distance runs on each energy source.
        //
        // A PHEV is the only case where both apply at once: the user declares
        // what share of distance is driven on electricity, and each energy cost
        // is charged over its own share of the distance. Everything else is
        // wholly one or the other.
        let electricDistanceShare: Double
        let fuelDistanceShare: Double
        switch powertrain {
        case .bev:
            electricDistanceShare = 1
            fuelDistanceShare = 0
        case .phev:
            electricDistanceShare = side.phevElectricShare.primary
            fuelDistanceShare = side.phevElectricShare.secondary
        case .gasoline, .diesel, .hybrid, .other:
            electricDistanceShare = 0
            fuelDistanceShare = 1
        }

        let fuelCostPer100Km = (litresPer100Km ?? 0) * fuelPrice * fuelDistanceShare
        let electricityCostPer100Km = (kWhPer100Km ?? 0) * electricityPrice * electricDistanceShare

        // Cost per 100 km → cost per year over the user's annual distance.
        let hundredsOfKmPerYear = driving.annualKilometres / 100

        return EnergyCostBreakdown(
            effectiveLitresPer100Km: powertrain.usesLiquidFuel ? litresPer100Km : nil,
            effectiveKwhPer100Km: powertrain.usesElectricity ? kWhPer100Km : nil,
            fuelCostPer100Km: fuelCostPer100Km,
            electricityCostPer100Km: electricityCostPer100Km,
            annualFuelCost: fuelCostPer100Km * hundredsOfKmPerYear,
            annualElectricityCost: electricityCostPer100Km * hundredsOfKmPerYear,
            usedCombinedFallback: (powertrain.usesLiquidFuel && fuelBlend.usedFallback)
                || (powertrain.usesElectricity && electricBlend.usedFallback)
        )
    }

    /// Estimate what share of distance a plug-in hybrid would actually drive on
    /// electricity, from daily distance, electric range and charging frequency.
    ///
    /// Modelled as: each charge provides `electricRangeKm`; the user charges
    /// `chargesPerWeek` times; electric distance is capped both by the energy
    /// available and by the distance actually driven.
    ///
    /// This is an aid only. The manual share is always available and always wins
    /// when the user sets it.
    public static func estimatePHEVElectricShare(
        dailyKilometres: Double,
        electricRangeKm: Double,
        chargesPerWeek: Double
    ) -> Split? {
        guard dailyKilometres > 0, electricRangeKm > 0, chargesPerWeek > 0 else { return nil }
        let weeklyDistance = dailyKilometres * 7
        let weeklyElectricCapacity = electricRangeKm * chargesPerWeek
        let share = min(weeklyElectricCapacity / weeklyDistance, 1)
        return Split(primary: share)
    }
}
