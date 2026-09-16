import Testing
import Foundation
@testable import FuelSmartCore

/// Expected values in this file were computed independently from the
/// implementation (see Documentation/CalculationMethodology.md) rather than
/// recorded from a run, so they test the maths rather than the code's memory.
@Suite("Energy cost")
struct EnergyCostTests {

    private let tolerance = 1e-9

    // MARK: - Blending

    @Test("City and highway ratings blend by distance share")
    func cityHighwayBlend() {
        // 4.9 × 0.55 + 5.1 × 0.45 = 2.695 + 2.295 = 4.99
        let (value, fallback) = EnergyCostCalculator.blend(
            city: 4.9, highway: 5.1, combined: 5.0, split: Split(primaryPercent: 55)
        )
        #expect(abs(value! - 4.99) < tolerance)
        #expect(fallback == false)
    }

    @Test("An all-city mix returns the city rating exactly")
    func allCityBlend() {
        let (value, _) = EnergyCostCalculator.blend(
            city: 4.9, highway: 5.1, combined: 5.0, split: Split(primaryPercent: 100)
        )
        #expect(abs(value! - 4.9) < tolerance)
    }

    @Test("Missing split ratings fall back to combined, and say so")
    func combinedFallback() {
        let (value, fallback) = EnergyCostCalculator.blend(
            city: nil, highway: nil, combined: 8.0, split: Split(primaryPercent: 55)
        )
        #expect(value == 8.0)
        #expect(fallback == true)
    }

    @Test("No rating at all yields no value rather than a zero")
    func noRating() {
        let (value, fallback) = EnergyCostCalculator.blend(
            city: nil, highway: nil, combined: nil, split: .evenSplit
        )
        #expect(value == nil)
        #expect(fallback == false)
    }

    // MARK: - Gasoline

    @Test("Gasoline cost per 100 km and per year")
    func gasolineCost() {
        let side = Fixtures.side(Fixtures.hybridSedan, price: 41_000)
        let breakdown = EnergyCostCalculator.breakdown(
            for: side, driving: Fixtures.standardDriving, prices: Fixtures.standardPrices
        )
        // 4.99 L/100 km × $1.72/L = $8.5828 per 100 km
        #expect(abs(breakdown.fuelCostPer100Km - 8.5828) < 1e-9)
        // $8.5828 × 180 hundred-km = $1,544.904 a year
        #expect(abs(breakdown.annualFuelCost - 1_544.904) < 1e-9)
        #expect(breakdown.annualElectricityCost == 0)
        #expect(breakdown.usedCombinedFallback == false)
    }

    @Test("Diesel is priced from the diesel rate, not the gasoline rate")
    func dieselUsesDieselPrice() {
        let side = Fixtures.side(Fixtures.dieselTruck, price: 70_000)
        let breakdown = EnergyCostCalculator.breakdown(
            for: side, driving: Fixtures.standardDriving, prices: Fixtures.standardPrices
        )
        // 11.2 × 0.55 + 8.9 × 0.45 = 6.16 + 4.005 = 10.165 L/100 km, at $1.85/L
        #expect(abs(breakdown.fuelCostPer100Km - 10.165 * 1.85) < 1e-9)
    }

    // MARK: - Electricity

    @Test("Charging sources blend by share")
    func blendedChargingRate() {
        // 0.14 × 0.80 + 0.52 × 0.20 = 0.112 + 0.104 = 0.216
        #expect(abs(Fixtures.standardPrices.blendedElectricityPricePerKWh - 0.216) < tolerance)
    }

    @Test("Shares that do not total one are normalized rather than distorting the rate")
    func sharesAreNormalized() {
        let prices = EnergyPriceProfile(
            gasolinePricePerLitre: 1.72,
            dieselPricePerLitre: 1.85,
            chargingSources: [
                .init(id: "home", name: "Home", pricePerKWh: 0.10, share: 0.4),
                .init(id: "public", name: "Public", pricePerKWh: 0.50, share: 0.4),
            ]
        )
        // Equal shares, so the blend is the simple mean regardless of the total.
        #expect(abs(prices.blendedElectricityPricePerKWh - 0.30) < tolerance)
    }

    @Test("Electric cost uses published kWh/100 km, never battery ÷ range")
    func electricCost() {
        let side = Fixtures.side(Fixtures.batteryElectric, price: 49_990)
        let breakdown = EnergyCostCalculator.breakdown(
            for: side, driving: Fixtures.standardDriving, prices: Fixtures.standardPrices
        )
        // 13.9 × 0.55 + 16.2 × 0.45 = 14.935 kWh/100 km
        #expect(abs(breakdown.effectiveKwhPer100Km! - 14.935) < 1e-9)
        // 14.935 × $0.216 = $3.22596 per 100 km
        #expect(abs(breakdown.electricityCostPer100Km - 3.22596) < 1e-9)
        // × 180 = $580.6728 a year
        #expect(abs(breakdown.annualElectricityCost - 580.6728) < 1e-9)
        #expect(breakdown.annualFuelCost == 0)
    }

    // MARK: - Plug-in hybrid

    @Test("A PHEV charges each energy source over its own share of the distance")
    func phevBlendedEnergy() {
        let side = Fixtures.side(
            Fixtures.plugInHybrid, price: 40_000,
            phevElectricShare: Split(primaryPercent: 70)
        )
        let breakdown = EnergyCostCalculator.breakdown(
            for: side, driving: Fixtures.standardDriving, prices: Fixtures.standardPrices
        )
        // Fuel:  4.78 L/100 km × $1.72 × 30% distance = $2.46648
        #expect(abs(breakdown.fuelCostPer100Km - 2.46648) < 1e-9)
        // Power: 15.9 kWh/100 km × $0.216 × 70% distance = $2.40408
        #expect(abs(breakdown.electricityCostPer100Km - 2.40408) < 1e-9)
        // Annual total over 18,000 km
        #expect(abs(breakdown.annualTotal - 876.7008) < 1e-6)
    }

    @Test("A PHEV driven entirely on electricity burns no fuel")
    func phevAllElectric() {
        let side = Fixtures.side(
            Fixtures.plugInHybrid, price: 40_000,
            phevElectricShare: Split(primaryPercent: 100)
        )
        let breakdown = EnergyCostCalculator.breakdown(
            for: side, driving: Fixtures.standardDriving, prices: Fixtures.standardPrices
        )
        #expect(breakdown.fuelCostPer100Km == 0)
        #expect(breakdown.electricityCostPer100Km > 0)
    }

    @Test("PHEV electric share can be estimated from daily driving")
    func phevShareEstimate() {
        // 49 km/day, 68 km electric range, charged nightly: capacity exceeds
        // distance, so the share caps at 100%.
        let nightly = EnergyCostCalculator.estimatePHEVElectricShare(
            dailyKilometres: 49, electricRangeKm: 68, chargesPerWeek: 7
        )
        #expect(nightly?.primary == 1.0)

        // Charged twice a week: 68 × 2 = 136 km of the 343 km driven → ~39.7%.
        let twiceWeekly = EnergyCostCalculator.estimatePHEVElectricShare(
            dailyKilometres: 49, electricRangeKm: 68, chargesPerWeek: 2
        )
        #expect(abs(twiceWeekly!.primary - (136.0 / 343.0)) < 1e-9)
    }

    // MARK: - Real-world adjustment

    @Test("The real-world adjustment raises consumption without touching the rating")
    func realWorldAdjustment() {
        let driving = DrivingProfile(
            annualKilometres: 18_000,
            cityHighwaySplit: Split(primaryPercent: 55),
            realWorldAdjustment: 0.10
        )
        let side = Fixtures.side(Fixtures.hybridSedan, price: 41_000)
        let breakdown = EnergyCostCalculator.breakdown(
            for: side, driving: driving, prices: Fixtures.standardPrices
        )
        // 4.99 × 1.10 = 5.489
        #expect(abs(breakdown.effectiveLitresPer100Km! - 5.489) < 1e-9)
        // The official rating on the vehicle itself is untouched.
        #expect(side.vehicle.efficiency.cityLPer100Km == 4.9)
    }

    // MARK: - Degenerate inputs

    @Test("Zero annual distance produces zero annual cost, not a crash")
    func zeroDistance() {
        let driving = DrivingProfile(annualKilometres: 0)
        let side = Fixtures.side(Fixtures.hybridSedan, price: 41_000)
        let breakdown = EnergyCostCalculator.breakdown(
            for: side, driving: driving, prices: Fixtures.standardPrices
        )
        #expect(breakdown.annualTotal == 0)
        #expect(breakdown.fuelCostPer100Km > 0)
    }

    @Test("A zero energy price yields zero running cost without dividing by anything")
    func zeroEnergyPrice() {
        let prices = EnergyPriceProfile(
            gasolinePricePerLitre: 0, dieselPricePerLitre: 0, electricityPricePerKWh: 0
        )
        let side = Fixtures.side(Fixtures.batteryElectric, price: 49_990)
        let breakdown = EnergyCostCalculator.breakdown(
            for: side, driving: Fixtures.standardDriving, prices: prices
        )
        #expect(breakdown.annualTotal == 0)
    }

    @Test("A vehicle with no rating produces no consumption figure")
    func unratedVehicle() {
        let side = Fixtures.side(Fixtures.unratedVehicle, price: 20_000)
        let breakdown = EnergyCostCalculator.breakdown(
            for: side, driving: Fixtures.standardDriving, prices: Fixtures.standardPrices
        )
        #expect(breakdown.effectiveLitresPer100Km == nil)
        #expect(breakdown.annualTotal == 0)
    }
}
