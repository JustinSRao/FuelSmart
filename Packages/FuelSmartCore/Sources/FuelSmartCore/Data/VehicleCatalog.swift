import Foundation

/// The prebuilt Country → Year → Make → Model tree.
///
/// Small enough (roughly half a megabyte a country) to decode eagerly, and it
/// carries the vehicle ids at each leaf. That means drilling through the browse
/// picker never touches the multi-megabyte records file at all — the large file
/// is only read when a user actually opens a specific configuration or starts a
/// full-text search.
public struct VehicleCatalog: Codable, Sendable {
    public var schemaVersion: Int
    public var country: String
    public var datasetVersion: String
    public var years: [YearNode]

    public struct YearNode: Codable, Sendable, Identifiable, Hashable {
        public var year: Int
        public var count: Int
        public var makes: [MakeNode]
        public var id: Int { year }
    }

    public struct MakeNode: Codable, Sendable, Identifiable, Hashable {
        public var make: String
        public var count: Int
        public var models: [ModelNode]
        public var id: String { make }
    }

    public struct ModelNode: Codable, Sendable, Identifiable, Hashable {
        public var model: String
        public var count: Int
        public var powertrains: [String]
        public var ids: [String]
        public var id: String { model }

        public var resolvedPowertrains: [Powertrain] {
            powertrains.compactMap(Powertrain.init(rawValue:))
        }
    }

    // MARK: - Lookups

    public func node(forYear year: Int) -> YearNode? {
        years.first { $0.year == year }
    }

    public func makes(inYear year: Int) -> [MakeNode] {
        node(forYear: year)?.makes ?? []
    }

    public func models(inYear year: Int, make: String) -> [ModelNode] {
        makes(inYear: year).first { $0.make.caseInsensitiveCompare(make) == .orderedSame }?.models ?? []
    }

    public var availableYears: [Int] { years.map(\.year) }
}

/// The dataset's own description of itself: versions, counts, checksums and the
/// attribution text the app is required to display.
public struct DatasetManifest: Codable, Sendable {
    public var schemaVersion: Int
    public var datasetVersion: String
    public var generatedAt: String
    public var countries: [CountrySummary]
    public var attribution: [String: String]
    public var disclaimer: String

    public struct CountrySummary: Codable, Sendable, Identifiable {
        public var country: String
        public var recordCount: Int
        public var yearRange: [Int]?
        public var powertrainCounts: [String: Int]
        public var files: [String: FileInfo]
        public var sources: [SourceInfo]
        public var id: String { country }
    }

    public struct FileInfo: Codable, Sendable {
        public var name: String
        public var bytes: Int
        public var sha256: String
    }

    public struct SourceInfo: Codable, Sendable, Identifiable {
        public var id: String
        public var publisher: String
        public var dataset: String
        public var licence: String
        public var licenceUrl: String
        public var landingPage: String
    }

    public func summary(for region: Region) -> CountrySummary? {
        countries.first { $0.country == region.rawValue }
    }

    public func attribution(for region: Region) -> String? {
        attribution[region.rawValue]
    }

    /// Source metadata in the shape the results model carries.
    public func dataSources(for region: Region) -> [DataSourceMetadata] {
        (summary(for: region)?.sources ?? []).map { source in
            DataSourceMetadata(
                id: source.id,
                publisher: source.publisher,
                dataset: source.dataset,
                licence: source.licence,
                licenceURL: source.licenceUrl,
                landingPage: source.landingPage,
                datasetVersion: datasetVersion
            )
        }
    }
}
