import Foundation
@testable import FuelSmartCore

/// Deterministic test vehicles.
///
/// Hand-written rather than loaded from live government data, so a test can
/// never fail because Ottawa or the EPA republished a file. Figures are
/// realistic but fixed forever.
enum Fixtures {

    static let fixedStartDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }()

    // MARK: - Vehicles

    /// Plain gasoline sedan.
    static let gasSedan = Vehicle(
        id: "fixture-gas-sedan",
        region: .canada,
        year: 2026,
        make: "Toyota",
        model: "Corolla",
        configuration: "LE",
        powertrain: .gasoline,
        efficiency: VehicleEfficiency(
            cityLPer100Km: 7.9,
            highwayLPer100Km: 6.1,
            combinedLPer100Km: 7.1
        ),
        sourceId: "fixture"
    )

    /// Conventional hybrid — gains in the city.
    static let hybridSedan = Vehicle(
        id: "fixture-hybrid-sedan",
        region: .canada,
        year: 2026,
        make: "Toyota",
        model: "Camry",
        configuration: "Hybrid LE",
        powertrain: .hybrid,
        efficiency: VehicleEfficiency(
            cityLPer100Km: 4.9,
            highwayLPer100Km: 5.1,
            combinedLPer100Km: 5.0
        ),
        sourceId: "fixture"
    )

    /// Diesel pickup — the "more efficient isn't automatically cheaper" case.
    static let dieselTruck = Vehicle(
        id: "fixture-diesel-truck",
        region: .canada,
        year: 2026,
        make: "Ram",
        model: "1500",
        configuration: "EcoDiesel",
        powertrain: .diesel,
        efficiency: VehicleEfficiency(
            cityLPer100Km: 11.2,
            highwayLPer100Km: 8.9,
            combinedLPer100Km: 10.2
        ),
        sourceId: "fixture"
    )

    /// Plug-in hybrid — two energy sources at once.
    static let plugInHybrid = Vehicle(
        id: "fixture-phev",
        region: .canada,
        year: 2026,
        make: "Toyota",
        model: "Prius",
        configuration: "Prime",
        powertrain: .phev,
        efficiency: VehicleEfficiency(
            cityLPer100Km: 4.6,
            highwayLPer100Km: 5.0,
            combinedLPer100Km: 4.8,
            cityKwhPer100Km: 15.0,
            highwayKwhPer100Km: 17.0,
            combinedKwhPer100Km: 16.0,
            electricRangeKm: 68,
            totalRangeKm: 960
        ),
        sourceId: "fixture"
    )

    /// Battery-electric.
    static let batteryElectric = Vehicle(
        id: "fixture-bev",
        region: .canada,
        year: 2026,
        make: "Tesla",
        model: "Model 3",
        configuration: "RWD",
        powertrain: .bev,
        efficiency: VehicleEfficiency(
            cityKwhPer100Km: 13.9,
            highwayKwhPer100Km: 16.2,
            combinedKwhPer100Km: 14.9,
            electricRangeKm: 584,
            totalRangeKm: 584,
            rechargeHours: 8.25
        ),
        sourceId: "fixture"
    )

    /// A record with only a combined rating, to exercise the fallback path.
    static let combinedOnlyVehicle = Vehicle(
        id: "fixture-combined-only",
        region: .canada,
        year: 2020,
        make: "Generic",
        model: "Saloon",
        powertrain: .gasoline,
        efficiency: VehicleEfficiency(combinedLPer100Km: 8.0),
        sourceId: "fixture"
    )

    /// A record the dataset never rated, to exercise validation.
    static let unratedVehicle = Vehicle(
        id: "fixture-unrated",
        region: .canada,
        year: 2026,
        make: "Obscure",
        model: "Prototype",
        powertrain: .gasoline,
        efficiency: VehicleEfficiency(),
        sourceId: "fixture"
    )

    // MARK: - Profiles

    /// 18,000 km/year, 55% city, no real-world adjustment.
    static let standardDriving = DrivingProfile(
        annualKilometres: 18_000,
        cityHighwaySplit: Split(primaryPercent: 55),
        realWorldAdjustment: 0
    )

    /// $1.72/L gasoline, $1.85/L diesel, 80% home charging at $0.14, 20% public at $0.52.
    static let standardPrices = EnergyPriceProfile.homeAndPublic(
        gasolinePricePerLitre: 1.72,
        dieselPricePerLitre: 1.85,
        homePricePerKWh: 0.14,
        publicPricePerKWh: 0.52,
        publicShare: Split(primaryPercent: 20)
    )

    // MARK: - Scenarios

    static func side(
        _ vehicle: Vehicle,
        price: Double,
        fees: Double = 0,
        rebate: Double = 0,
        charger: Double = 0,
        tradeIn: Double = 0,
        financing: FinancingProfile = .cash,
        recurring: RecurringCostProfile = .empty,
        resale: ResaleAssumption? = nil,
        phevElectricShare: Split = Split(primaryPercent: 70),
        isAlreadyOwned: Bool = false
    ) -> ComparisonSide {
        ComparisonSide(
            vehicle: vehicle,
            acquisition: AcquisitionCost(
                purchasePrice: price,
                dealerFees: fees,
                rebate: rebate,
                tradeInValue: tradeIn,
                homeChargerInstallation: charger
            ),
            financing: financing,
            recurringCosts: recurring,
            resale: resale,
            phevElectricShare: phevElectricShare,
            isAlreadyOwned: isAlreadyOwned
        )
    }

    /// The canonical worked example: hybrid sedan versus battery-electric.
    /// Matches the example carried through the design reference.
    static func hybridVersusElectric(
        horizon: OwnershipHorizon = .fiveYears,
        driving: DrivingProfile = standardDriving,
        prices: EnergyPriceProfile = standardPrices
    ) -> ComparisonScenario {
        ComparisonScenario(
            mode: .buyVsBuy,
            region: .canada,
            sideA: side(hybridSedan, price: 41_000, fees: 2_500),
            sideB: side(batteryElectric, price: 49_990, fees: 2_600, rebate: 5_000, charger: 1_200),
            driving: driving,
            energyPrices: prices,
            horizon: horizon,
            startDate: fixedStartDate
        )
    }
}
