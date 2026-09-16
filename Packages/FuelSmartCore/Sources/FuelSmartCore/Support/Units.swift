import Foundation

/// The region a comparison belongs to.
///
/// A comparison is always expressed wholly in one region's units. FuelSmart
/// never mixes units or shows a conversion in parentheses.
public enum Region: String, Codable, Sendable, CaseIterable, Hashable {
    case canada = "CA"
    case unitedStates = "US"

    public var currencyCode: String {
        switch self {
        case .canada: "CAD"
        case .unitedStates: "USD"
        }
    }

    /// Canada measures fuel use as litres per 100 km; the U.S. as miles per gallon.
    public var usesMetricDistance: Bool { self == .canada }
}

/// How the user prefers to type a distance. Everything is normalized to a year.
public enum DistancePeriod: String, Codable, Sendable, CaseIterable, Hashable {
    case day, week, month, year

    /// Periods per year. 365.25 absorbs leap years so a "per day" entry does not
    /// quietly differ from the same figure entered per year.
    public var periodsPerYear: Double {
        switch self {
        case .day: 365.25
        case .week: 52.1775
        case .month: 12
        case .year: 1
        }
    }
}

/// Exact unit conversions.
///
/// Every constant here is a definition, not a measurement, so these conversions
/// are lossless in both directions. The calculation engine works only in the
/// canonical units; conversion happens at the edges, on input and on display.
///
/// Canonical units: distance in kilometres, liquid fuel in litres per 100 km,
/// electricity in kWh per 100 km, money in the region's own currency.
public enum UnitConversionService {

    // MARK: - Definitions

    public static let kilometresPerMile = 1.609344
    public static let litresPerUSGallon = 3.785411784
    public static let litresPerImperialGallon = 4.54609

    /// 100 × litres-per-gallon ÷ km-per-mile. Multiply-or-divide by this to move
    /// between U.S. MPG and L/100 km — the relationship is reciprocal, not linear,
    /// which is precisely why the engine never stores MPG.
    public static let usMPGToLitresPer100km = 100.0 * litresPerUSGallon / kilometresPerMile

    public static let imperialMPGToLitresPer100km = 100.0 * litresPerImperialGallon / kilometresPerMile

    // MARK: - Distance

    public static func milesToKilometres(_ miles: Double) -> Double { miles * kilometresPerMile }
    public static func kilometresToMiles(_ km: Double) -> Double { km / kilometresPerMile }

    /// Convert a distance typed in the region's own unit into canonical kilometres.
    public static func distanceToKilometres(_ value: Double, region: Region) -> Double {
        region.usesMetricDistance ? value : milesToKilometres(value)
    }

    /// Convert canonical kilometres into the region's display unit.
    public static func kilometresToRegionDistance(_ km: Double, region: Region) -> Double {
        region.usesMetricDistance ? km : kilometresToMiles(km)
    }

    // MARK: - Fuel economy

    /// U.S. MPG → L/100 km. Returns nil for non-positive input, which is not a
    /// physically meaningful economy figure.
    public static func usMPGToLitresPer100km(_ mpg: Double) -> Double? {
        guard mpg > 0 else { return nil }
        return usMPGToLitresPer100km / mpg
    }

    public static func litresPer100kmToUSMPG(_ litresPer100km: Double) -> Double? {
        guard litresPer100km > 0 else { return nil }
        return usMPGToLitresPer100km / litresPer100km
    }

    public static func imperialMPGToLitresPer100km(_ mpg: Double) -> Double? {
        guard mpg > 0 else { return nil }
        return imperialMPGToLitresPer100km / mpg
    }

    // MARK: - Fuel price

    /// A price typed per U.S. gallon becomes a price per litre.
    public static func pricePerUSGallonToPerLitre(_ price: Double) -> Double {
        price / litresPerUSGallon
    }

    public static func pricePerLitreToPerUSGallon(_ price: Double) -> Double {
        price * litresPerUSGallon
    }

    /// Convert a fuel price typed in the region's own unit into canonical $/litre.
    public static func fuelPriceToPerLitre(_ value: Double, region: Region) -> Double {
        region.usesMetricDistance ? value : pricePerUSGallonToPerLitre(value)
    }

    public static func fuelPriceFromPerLitre(_ perLitre: Double, region: Region) -> Double {
        region.usesMetricDistance ? perLitre : pricePerLitreToPerUSGallon(perLitre)
    }

    // MARK: - Electricity

    /// The EPA publishes electrical consumption per 100 miles.
    public static func kWhPer100MilesToPer100km(_ value: Double) -> Double {
        value / kilometresPerMile
    }

    public static func kWhPer100kmToPer100Miles(_ value: Double) -> Double {
        value * kilometresPerMile
    }

    // MARK: - Emissions

    public static func gramsPerMileToGramsPerKilometre(_ value: Double) -> Double {
        value / kilometresPerMile
    }
}
