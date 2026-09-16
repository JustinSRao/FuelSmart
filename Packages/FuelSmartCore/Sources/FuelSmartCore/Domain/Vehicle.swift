import Foundation

/// How a vehicle turns stored energy into motion. Drives which efficiency
/// figures are meaningful and which inputs the UI must collect.
public enum Powertrain: String, Codable, Sendable, CaseIterable, Hashable {
    case gasoline
    case diesel
    case hybrid
    case phev
    case bev
    case other

    /// True when the vehicle burns liquid fuel under any circumstances.
    public var usesLiquidFuel: Bool {
        switch self {
        case .gasoline, .diesel, .hybrid, .phev, .other: true
        case .bev: false
        }
    }

    /// True when the vehicle draws energy from the grid.
    public var usesElectricity: Bool {
        switch self {
        case .bev, .phev: true
        case .gasoline, .diesel, .hybrid, .other: false
        }
    }

    /// Which liquid fuel price applies. Nil when the vehicle burns none.
    public var liquidFuelKind: LiquidFuelKind? {
        switch self {
        case .diesel: .diesel
        case .gasoline, .hybrid, .phev, .other: .gasoline
        case .bev: nil
        }
    }

    public var displayName: String {
        switch self {
        case .gasoline: "Gasoline"
        case .diesel: "Diesel"
        case .hybrid: "Hybrid"
        case .phev: "Plug-in hybrid"
        case .bev: "Electric"
        case .other: "Other"
        }
    }
}

public enum LiquidFuelKind: String, Codable, Sendable, Hashable {
    case gasoline
    case diesel
}

/// Government-published efficiency figures for one vehicle configuration.
///
/// Every field is optional because governments genuinely omit them. A missing
/// value stays missing: the app shows "—" rather than inventing a number, and
/// the calculators fall back explicitly and visibly.
///
/// All figures are canonical metric regardless of the publishing country, so the
/// engine needs no per-region branch. `official*` values preserve the
/// publisher's own numbers for faithful display on the detail screen.
public struct VehicleEfficiency: Codable, Sendable, Hashable {

    // Liquid fuel, litres per 100 km
    public var cityLPer100Km: Double?
    public var highwayLPer100Km: Double?
    public var combinedLPer100Km: Double?

    // Electricity, kWh per 100 km. Published directly by both governments —
    // never derived from battery capacity ÷ advertised range.
    public var cityKwhPer100Km: Double?
    public var highwayKwhPer100Km: Double?
    public var combinedKwhPer100Km: Double?

    public var electricRangeKm: Double?
    public var totalRangeKm: Double?
    public var rechargeHours: Double?

    public var co2GramsPerKm: Double?
    public var co2Rating: Int?
    public var smogRating: Int?
    public var fuelEconomyScore: Int?

    public var officialCombinedMpgImperial: Double?
    public var officialCityMpgUS: Double?
    public var officialHighwayMpgUS: Double?
    public var officialCombinedMpgUS: Double?
    public var officialCombinedKwhPer100Mi: Double?

    public init(
        cityLPer100Km: Double? = nil,
        highwayLPer100Km: Double? = nil,
        combinedLPer100Km: Double? = nil,
        cityKwhPer100Km: Double? = nil,
        highwayKwhPer100Km: Double? = nil,
        combinedKwhPer100Km: Double? = nil,
        electricRangeKm: Double? = nil,
        totalRangeKm: Double? = nil,
        rechargeHours: Double? = nil,
        co2GramsPerKm: Double? = nil,
        co2Rating: Int? = nil,
        smogRating: Int? = nil,
        fuelEconomyScore: Int? = nil,
        officialCombinedMpgImperial: Double? = nil,
        officialCityMpgUS: Double? = nil,
        officialHighwayMpgUS: Double? = nil,
        officialCombinedMpgUS: Double? = nil,
        officialCombinedKwhPer100Mi: Double? = nil
    ) {
        self.cityLPer100Km = cityLPer100Km
        self.highwayLPer100Km = highwayLPer100Km
        self.combinedLPer100Km = combinedLPer100Km
        self.cityKwhPer100Km = cityKwhPer100Km
        self.highwayKwhPer100Km = highwayKwhPer100Km
        self.combinedKwhPer100Km = combinedKwhPer100Km
        self.electricRangeKm = electricRangeKm
        self.totalRangeKm = totalRangeKm
        self.rechargeHours = rechargeHours
        self.co2GramsPerKm = co2GramsPerKm
        self.co2Rating = co2Rating
        self.smogRating = smogRating
        self.fuelEconomyScore = fuelEconomyScore
        self.officialCombinedMpgImperial = officialCombinedMpgImperial
        self.officialCityMpgUS = officialCityMpgUS
        self.officialHighwayMpgUS = officialHighwayMpgUS
        self.officialCombinedMpgUS = officialCombinedMpgUS
        self.officialCombinedKwhPer100Mi = officialCombinedKwhPer100Mi
    }

    /// True when city and highway figures are both present, so a driving-mix
    /// blend is possible rather than a fall back to the combined rating.
    public var hasSplitFuelRatings: Bool {
        cityLPer100Km != nil && highwayLPer100Km != nil
    }

    public var hasSplitElectricRatings: Bool {
        cityKwhPer100Km != nil && highwayKwhPer100Km != nil
    }
}

/// One vehicle configuration as published by a government dataset, or entered by
/// hand when the dataset does not cover it.
public struct Vehicle: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var region: Region
    public var year: Int
    public var make: String
    public var model: String
    public var configuration: String?
    public var vehicleClass: String?
    public var powertrain: Powertrain
    public var fuelDescription: String?
    public var engineSizeL: Double?
    public var cylinders: Int?
    public var transmission: String?
    public var drive: String?
    public var efficiency: VehicleEfficiency
    public var sourceId: String?

    /// True when the user typed this vehicle in rather than picking it from an
    /// official dataset. Surfaced in results so an estimate is never mistaken
    /// for a government rating.
    public var isUserDefined: Bool

    public init(
        id: String,
        region: Region,
        year: Int,
        make: String,
        model: String,
        configuration: String? = nil,
        vehicleClass: String? = nil,
        powertrain: Powertrain,
        fuelDescription: String? = nil,
        engineSizeL: Double? = nil,
        cylinders: Int? = nil,
        transmission: String? = nil,
        drive: String? = nil,
        efficiency: VehicleEfficiency = VehicleEfficiency(),
        sourceId: String? = nil,
        isUserDefined: Bool = false
    ) {
        self.id = id
        self.region = region
        self.year = year
        self.make = make
        self.model = model
        self.configuration = configuration
        self.vehicleClass = vehicleClass
        self.powertrain = powertrain
        self.fuelDescription = fuelDescription
        self.engineSizeL = engineSizeL
        self.cylinders = cylinders
        self.transmission = transmission
        self.drive = drive
        self.efficiency = efficiency
        self.sourceId = sourceId
        self.isUserDefined = isUserDefined
    }

    /// "2026 Tesla Model 3"
    public var displayName: String {
        "\(year) \(make) \(model)"
    }

    /// "2026 Tesla Model 3 RWD"
    public var fullDisplayName: String {
        if let configuration, !configuration.isEmpty {
            return "\(displayName) \(configuration)"
        }
        return displayName
    }

    /// The short name used on charts and comparison rows, where the year and
    /// make are already established by context.
    public var shortDisplayName: String {
        if let configuration, !configuration.isEmpty {
            return "\(model) \(configuration)"
        }
        return model
    }
}
