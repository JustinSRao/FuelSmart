import Testing
import Foundation
@testable import FuelSmartCore

@Suite("Unit conversion")
struct UnitConversionTests {

    @Test("Distance conversions round-trip exactly")
    func distanceRoundTrip() {
        let miles = 12_500.0
        let km = UnitConversionService.milesToKilometres(miles)
        #expect(abs(km - 20_116.8) < 1e-9)
        #expect(abs(UnitConversionService.kilometresToMiles(km) - miles) < 1e-9)
    }

    @Test("U.S. MPG converts to L/100 km and back")
    func mpgRoundTrip() {
        // 30 MPG → 235.214583… / 30 = 7.840486… L/100 km
        let litres = UnitConversionService.usMPGToLitresPer100km(30)!
        #expect(abs(litres - 7.840486111) < 1e-8)
        #expect(abs(UnitConversionService.litresPer100kmToUSMPG(litres)! - 30) < 1e-9)
    }

    @Test("Imperial MPG is not U.S. MPG")
    func imperialIsDistinct() {
        let us = UnitConversionService.usMPGToLitresPer100km(30)!
        let imperial = UnitConversionService.imperialMPGToLitresPer100km(30)!
        // An Imperial gallon is larger than a U.S. one, so covering the same
        // number of miles on one means burning more fuel: the identical MPG
        // figure is the *worse* economy when it is Imperial. Confusing the two
        // would misstate NRCan's mpg column by about 20%.
        #expect(imperial > us)
        #expect(abs(imperial - 9.416031211) < 1e-8)
    }

    @Test("Non-positive economy figures have no conversion")
    func invalidEconomy() {
        #expect(UnitConversionService.usMPGToLitresPer100km(0) == nil)
        #expect(UnitConversionService.usMPGToLitresPer100km(-5) == nil)
        #expect(UnitConversionService.litresPer100kmToUSMPG(0) == nil)
    }

    @Test("Fuel price converts between per-gallon and per-litre")
    func fuelPrice() {
        // $3.50/gal ÷ 3.785411784 ≈ $0.92460/L
        let perLitre = UnitConversionService.pricePerUSGallonToPerLitre(3.50)
        #expect(abs(perLitre - 0.924602183) < 1e-8)
        #expect(abs(UnitConversionService.pricePerLitreToPerUSGallon(perLitre) - 3.50) < 1e-9)
    }

    @Test("Electricity consumption converts from per-100-miles to per-100-km")
    func electricity() {
        // EPA publishes kWh/100 mi; 100 mi is 160.9344 km, so the per-km figure
        // is smaller.
        let perKm = UnitConversionService.kWhPer100MilesToPer100km(24.0)
        #expect(abs(perKm - 14.912908614) < 1e-8)
        #expect(perKm < 24.0)
        #expect(abs(UnitConversionService.kWhPer100kmToPer100Miles(perKm) - 24.0) < 1e-9)
    }

    @Test("Region-aware helpers pick the right unit")
    func regionAware() {
        #expect(UnitConversionService.distanceToKilometres(100, region: .canada) == 100)
        #expect(abs(UnitConversionService.distanceToKilometres(100, region: .unitedStates) - 160.9344) < 1e-9)
        #expect(UnitConversionService.fuelPriceToPerLitre(1.72, region: .canada) == 1.72)
        #expect(abs(UnitConversionService.fuelPriceToPerLitre(3.50, region: .unitedStates) - 0.924602183) < 1e-8)
    }

    // MARK: - Driving profile normalization

    @Test("Distance normalizes to a year from any period")
    func periodNormalization() {
        let perYear = DrivingProfile.from(distance: 18_000, period: .year, region: .canada)
        #expect(perYear.annualKilometres == 18_000)

        let perMonth = DrivingProfile.from(distance: 1_500, region: .canada, period: .month)
        #expect(perMonth.annualKilometres == 18_000)
    }

    @Test("A U.S. figure typed in miles becomes canonical kilometres")
    func usDistanceNormalization() {
        let profile = DrivingProfile.from(distance: 12_000, period: .year, region: .unitedStates)
        #expect(abs(profile.annualKilometres - 19_312.128) < 1e-6)
    }

    @Test("Daily entry uses 365.25 days so it agrees with an annual entry")
    func leapYearHandling() {
        let daily = DrivingProfile.from(distance: 100, period: .day, region: .canada)
        #expect(abs(daily.annualKilometres - 36_525) < 1e-9)
    }

    // MARK: - Split

    @Test("A split always totals one hundred percent")
    func splitInvariant() {
        let split = Split(primaryPercent: 55)
        #expect(abs(split.primaryPercent - 55) < 1e-9)
        #expect(abs(split.secondaryPercent - 45) < 1e-9)
        #expect(abs(split.primary + split.secondary - 1) < 1e-12)
    }

    @Test("Out-of-range shares are clamped rather than breaking the invariant")
    func splitClamping() {
        #expect(Split(primaryPercent: 140).primary == 1)
        #expect(Split(primaryPercent: -20).primary == 0)
        #expect(Split(primaryPercent: 140).secondary == 0)
    }
}

// Convenience overload so the tests above read naturally.
private extension DrivingProfile {
    static func from(distance: Double, region: Region, period: DistancePeriod) -> DrivingProfile {
        .from(distance: distance, period: period, region: region)
    }
}
