import Foundation

/// Filters a vehicle listing.
public struct VehicleFilter: Sendable, Hashable {
    public var powertrains: Set<Powertrain>
    public var years: Set<Int>
    public var makes: Set<String>

    public init(powertrains: Set<Powertrain> = [], years: Set<Int> = [], makes: Set<String> = []) {
        self.powertrains = powertrains
        self.years = years
        self.makes = makes
    }

    public var isEmpty: Bool { powertrains.isEmpty && years.isEmpty && makes.isEmpty }

    func accepts(_ vehicle: Vehicle) -> Bool {
        if !powertrains.isEmpty, !powertrains.contains(vehicle.powertrain) { return false }
        if !years.isEmpty, !years.contains(vehicle.year) { return false }
        if !makes.isEmpty, !makes.contains(where: { $0.caseInsensitiveCompare(vehicle.make) == .orderedSame }) { return false }
        return true
    }
}

public enum VehicleRepositoryError: Error, Sendable, Equatable {
    case datasetMissing(region: Region)
    case datasetUnreadable(region: Region, reason: String)

    public var message: String {
        switch self {
        case .datasetMissing(let region):
            "The vehicle database for \(region == .canada ? "Canada" : "the United States") is missing from this build."
        case .datasetUnreadable(_, let reason):
            "The vehicle database could not be read: \(reason)"
        }
    }
}

/// Read access to one region's vehicle database.
///
/// A protocol so features can be built and tested against an in-memory stub
/// without a bundle, and so Canada and the United States can differ in how they
/// are sourced without any caller noticing.
public protocol VehicleRepository: Sendable {
    var region: Region { get }

    /// The browse tree. Cheap — backed by the small catalog file.
    func catalog() async throws -> VehicleCatalog

    /// One configuration by id.
    func vehicle(id: String) async throws -> Vehicle?

    /// Several configurations by id, in the order given.
    func vehicles(ids: [String]) async throws -> [Vehicle]

    /// Full-text search across year, make, model and configuration.
    func search(_ query: String, filter: VehicleFilter, limit: Int) async throws -> [Vehicle]

    /// Every configuration of one model, for the final picker step.
    func configurations(year: Int, make: String, model: String) async throws -> [Vehicle]

    /// Where this region's data came from.
    func dataSources() async throws -> [DataSourceMetadata]
}

/// Loads the database that ships inside the app bundle.
///
/// An `actor` because it owns a lazily-built cache that several screens touch
/// concurrently. The expensive work — decoding the records file and building the
/// search index — happens at most once, on first use, and never on the main
/// thread. The catalog loads separately and cheaply, so browsing is available
/// immediately even if the records file has not been touched yet.
public actor BundledVehicleRepository: VehicleRepository {

    public nonisolated let region: Region

    private let bundle: Bundle
    private var cachedCatalog: VehicleCatalog?
    private var cachedManifest: DatasetManifest?

    /// Decoded records plus the index over them, built together.
    private var loadedRecords: [Vehicle]?
    private var searchIndex: VehicleSearchIndex?
    private var recordsById: [String: Int]?

    public init(region: Region, bundle: Bundle = .main) {
        self.region = region
        self.bundle = bundle
    }

    // MARK: - Files

    private func data(named name: String) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw VehicleRepositoryError.datasetMissing(region: region)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw VehicleRepositoryError.datasetUnreadable(region: region, reason: error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        let payload = try data(named: name)
        do {
            return try JSONDecoder().decode(type, from: payload)
        } catch {
            throw VehicleRepositoryError.datasetUnreadable(region: region, reason: "\(name).json: \(error)")
        }
    }

    // MARK: - Catalog and manifest

    public func catalog() throws -> VehicleCatalog {
        if let cachedCatalog { return cachedCatalog }
        let loaded = try decode(VehicleCatalog.self, from: "catalog-\(region.rawValue)")
        cachedCatalog = loaded
        return loaded
    }

    public func manifest() throws -> DatasetManifest {
        if let cachedManifest { return cachedManifest }
        let loaded = try decode(DatasetManifest.self, from: "manifest")
        cachedManifest = loaded
        return loaded
    }

    public func dataSources() throws -> [DataSourceMetadata] {
        try manifest().dataSources(for: region)
    }

    // MARK: - Records

    /// Decode the records file and build the index. Runs at most once.
    private func loadRecords() throws -> [Vehicle] {
        if let loadedRecords { return loadedRecords }

        let file = try decode(VehicleRecordFile.self, from: "vehicles-\(region.rawValue)")
        let vehicles = file.records.map { $0.toVehicle(region: region) }

        var byId: [String: Int] = [:]
        byId.reserveCapacity(vehicles.count)
        for (offset, vehicle) in vehicles.enumerated() {
            byId[vehicle.id] = offset
        }

        loadedRecords = vehicles
        recordsById = byId
        searchIndex = VehicleSearchIndex(vehicles: vehicles)
        return vehicles
    }

    public func vehicle(id: String) throws -> Vehicle? {
        let vehicles = try loadRecords()
        guard let offset = recordsById?[id] else { return nil }
        return vehicles[offset]
    }

    public func vehicles(ids: [String]) throws -> [Vehicle] {
        let vehicles = try loadRecords()
        return ids.compactMap { recordsById?[$0].map { vehicles[$0] } }
    }

    public func search(_ query: String, filter: VehicleFilter = VehicleFilter(), limit: Int = 50) throws -> [Vehicle] {
        let vehicles = try loadRecords()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // An empty query with a filter is a browse, not a search: show the most
        // recent matching vehicles rather than nothing.
        guard !trimmed.isEmpty else {
            guard !filter.isEmpty else { return [] }
            return Array(
                vehicles.lazy.filter(filter.accepts)
                    .sorted { ($0.year, $1.make) > ($1.year, $0.make) }
                    .prefix(limit)
            )
        }

        guard let searchIndex else { return [] }
        let offsets = searchIndex.matches(for: trimmed)

        let matched = offsets.lazy
            .map { vehicles[Int($0)] }
            .filter(filter.accepts)

        return matched
            .map { (vehicle: $0, score: VehicleSearchIndex.score($0, query: trimmed)) }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.vehicle.year != $1.vehicle.year { return $0.vehicle.year > $1.vehicle.year }
                return $0.vehicle.fullDisplayName < $1.vehicle.fullDisplayName
            }
            .prefix(limit)
            .map(\.vehicle)
    }

    public func configurations(year: Int, make: String, model: String) throws -> [Vehicle] {
        // The catalog already knows exactly which ids belong to this model, so
        // this is a targeted fetch rather than a scan.
        let catalog = try catalog()
        let ids = catalog.models(inYear: year, make: make)
            .first { $0.model.caseInsensitiveCompare(model) == .orderedSame }?
            .ids ?? []
        return try vehicles(ids: ids)
            .sorted { ($0.configuration ?? "") < ($1.configuration ?? "") }
    }

    /// Release the large records array under memory pressure. The catalog stays,
    /// so browsing keeps working and the records reload on next use.
    public func releaseRecordCache() {
        loadedRecords = nil
        searchIndex = nil
        recordsById = nil
    }
}

// MARK: - Wire format

/// Mirrors the JSON emitted by `Scripts/build_dataset.py`.
///
/// Kept separate from `Vehicle` so the on-disk shape can change independently of
/// the domain model, and so absent fields stay absent rather than becoming zero.
struct VehicleRecordFile: Decodable {
    var schemaVersion: Int
    var country: String
    var datasetVersion: String
    var records: [VehicleRecordDTO]
}

struct VehicleRecordDTO: Decodable {
    var id: String
    var year: Int
    var make: String
    var model: String
    var powertrain: String
    var sourceId: String?
    var configuration: String?
    var vehicleClass: String?
    var fuelDescription: String?
    var engineSizeL: Double?
    var cylinders: Int?
    var transmission: String?
    var drive: String?

    var cityLPer100Km: Double?
    var highwayLPer100Km: Double?
    var combinedLPer100Km: Double?
    var cityKwhPer100Km: Double?
    var highwayKwhPer100Km: Double?
    var combinedKwhPer100Km: Double?

    var electricRangeKm: Double?
    var totalRangeKm: Double?
    var rechargeHours: Double?

    var co2GramsPerKm: Double?
    var co2Rating: Int?
    var smogRating: Int?
    var fuelEconomyScore: Int?

    var officialCombinedMpgImperial: Double?
    var officialCityMpgUS: Double?
    var officialHighwayMpgUS: Double?
    var officialCombinedMpgUS: Double?
    var officialCombinedKwhPer100Mi: Double?

    func toVehicle(region: Region) -> Vehicle {
        Vehicle(
            id: id,
            region: region,
            year: year,
            make: make,
            model: model,
            configuration: configuration,
            vehicleClass: vehicleClass,
            // An unrecognised powertrain degrades to `.other` rather than
            // failing the decode: one odd government row must never cost the
            // user the whole database.
            powertrain: Powertrain(rawValue: powertrain) ?? .other,
            fuelDescription: fuelDescription,
            engineSizeL: engineSizeL,
            cylinders: cylinders,
            transmission: transmission,
            drive: drive,
            efficiency: VehicleEfficiency(
                cityLPer100Km: cityLPer100Km,
                highwayLPer100Km: highwayLPer100Km,
                combinedLPer100Km: combinedLPer100Km,
                cityKwhPer100Km: cityKwhPer100Km,
                highwayKwhPer100Km: highwayKwhPer100Km,
                combinedKwhPer100Km: combinedKwhPer100Km,
                electricRangeKm: electricRangeKm,
                totalRangeKm: totalRangeKm,
                rechargeHours: rechargeHours,
                co2GramsPerKm: co2GramsPerKm,
                co2Rating: co2Rating,
                smogRating: smogRating,
                fuelEconomyScore: fuelEconomyScore,
                officialCombinedMpgImperial: officialCombinedMpgImperial,
                officialCityMpgUS: officialCityMpgUS,
                officialHighwayMpgUS: officialHighwayMpgUS,
                officialCombinedMpgUS: officialCombinedMpgUS,
                officialCombinedKwhPer100Mi: officialCombinedKwhPer100Mi
            ),
            sourceId: sourceId
        )
    }
}

// MARK: - Region-specific repositories

/// Named per-region repositories.
///
/// Both currently forward to the same bundled implementation, because both
/// governments' data is normalized to one shape by the ingestion pipeline. They
/// exist as distinct types so a region can later diverge — a different refresh
/// cadence, an extra field, a region-specific override — without any caller
/// changing.
public struct CanadianVehicleRepository: VehicleRepository {
    public nonisolated let region = Region.canada
    private let backing: BundledVehicleRepository

    public init(bundle: Bundle = .main) {
        backing = BundledVehicleRepository(region: .canada, bundle: bundle)
    }

    public func catalog() async throws -> VehicleCatalog { try await backing.catalog() }
    public func manifest() async throws -> DatasetManifest { try await backing.manifest() }
    public func vehicle(id: String) async throws -> Vehicle? { try await backing.vehicle(id: id) }
    public func vehicles(ids: [String]) async throws -> [Vehicle] { try await backing.vehicles(ids: ids) }
    public func dataSources() async throws -> [DataSourceMetadata] { try await backing.dataSources() }

    public func search(_ query: String, filter: VehicleFilter, limit: Int) async throws -> [Vehicle] {
        try await backing.search(query, filter: filter, limit: limit)
    }

    public func configurations(year: Int, make: String, model: String) async throws -> [Vehicle] {
        try await backing.configurations(year: year, make: make, model: model)
    }
}

public struct USVehicleRepository: VehicleRepository {
    public nonisolated let region = Region.unitedStates
    private let backing: BundledVehicleRepository

    public init(bundle: Bundle = .main) {
        backing = BundledVehicleRepository(region: .unitedStates, bundle: bundle)
    }

    public func catalog() async throws -> VehicleCatalog { try await backing.catalog() }
    public func manifest() async throws -> DatasetManifest { try await backing.manifest() }
    public func vehicle(id: String) async throws -> Vehicle? { try await backing.vehicle(id: id) }
    public func vehicles(ids: [String]) async throws -> [Vehicle] { try await backing.vehicles(ids: ids) }
    public func dataSources() async throws -> [DataSourceMetadata] { try await backing.dataSources() }

    public func search(_ query: String, filter: VehicleFilter, limit: Int) async throws -> [Vehicle] {
        try await backing.search(query, filter: filter, limit: limit)
    }

    public func configurations(year: Int, make: String, model: String) async throws -> [Vehicle] {
        try await backing.configurations(year: year, make: make, model: model)
    }
}

/// Builds the right repository for a region.
public enum VehicleRepositoryFactory {
    public static func make(for region: Region, bundle: Bundle = .main) -> any VehicleRepository {
        switch region {
        case .canada: CanadianVehicleRepository(bundle: bundle)
        case .unitedStates: USVehicleRepository(bundle: bundle)
        }
    }
}

/// An in-memory repository for tests, previews and DEBUG tooling.
public actor InMemoryVehicleRepository: VehicleRepository {
    public nonisolated let region: Region
    private let vehicles: [Vehicle]
    private let sources: [DataSourceMetadata]
    private lazy var index = VehicleSearchIndex(vehicles: vehicles)

    public init(region: Region, vehicles: [Vehicle], sources: [DataSourceMetadata] = []) {
        self.region = region
        self.vehicles = vehicles
        self.sources = sources
    }

    public func catalog() throws -> VehicleCatalog {
        let grouped = Dictionary(grouping: vehicles, by: \.year)
        let years = grouped.keys.sorted(by: >).map { year -> VehicleCatalog.YearNode in
            let byMake = Dictionary(grouping: grouped[year] ?? [], by: \.make)
            let makes = byMake.keys.sorted().map { make -> VehicleCatalog.MakeNode in
                let byModel = Dictionary(grouping: byMake[make] ?? [], by: \.model)
                let models = byModel.keys.sorted().map { model in
                    let entries = byModel[model] ?? []
                    return VehicleCatalog.ModelNode(
                        model: model,
                        count: entries.count,
                        powertrains: Array(Set(entries.map(\.powertrain.rawValue))).sorted(),
                        ids: entries.map(\.id)
                    )
                }
                return VehicleCatalog.MakeNode(make: make, count: (byMake[make] ?? []).count, models: models)
            }
            return VehicleCatalog.YearNode(year: year, count: (grouped[year] ?? []).count, makes: makes)
        }
        return VehicleCatalog(schemaVersion: 1, country: region.rawValue, datasetVersion: "test", years: years)
    }

    public func vehicle(id: String) throws -> Vehicle? { vehicles.first { $0.id == id } }

    public func vehicles(ids: [String]) throws -> [Vehicle] {
        ids.compactMap { id in vehicles.first { $0.id == id } }
    }

    public func dataSources() throws -> [DataSourceMetadata] { sources }

    public func search(_ query: String, filter: VehicleFilter, limit: Int) throws -> [Vehicle] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(vehicles.filter(filter.accepts).prefix(limit)) }
        return index.matches(for: trimmed)
            .map { vehicles[Int($0)] }
            .filter(filter.accepts)
            .sorted { VehicleSearchIndex.score($0, query: trimmed) > VehicleSearchIndex.score($1, query: trimmed) }
            .prefix(limit)
            .map { $0 }
    }

    public func configurations(year: Int, make: String, model: String) throws -> [Vehicle] {
        vehicles.filter {
            $0.year == year
                && $0.make.caseInsensitiveCompare(make) == .orderedSame
                && $0.model.caseInsensitiveCompare(model) == .orderedSame
        }
    }
}
