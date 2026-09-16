import Foundation

/// The versioned on-disk format for exported comparisons.
///
/// `schemaVersion` is the first field for a reason: it lets a future build
/// recognise and migrate an older file instead of failing to decode it. Imported
/// files are never trusted — every field is validated before anything reaches
/// the app's storage.
public struct FuelSmartDocument: Codable, Sendable {

    /// Bumped whenever the shape changes incompatibly. Readers accept anything
    /// from `minimumSupportedVersion` up to `currentVersion`.
    public static let currentVersion = 1
    public static let minimumSupportedVersion = 1

    public static let fileExtension = "fuelsmart"
    public static let uniformTypeIdentifier = "com.fuelsmart.comparison"

    public var schemaVersion: Int
    public var exportedAt: Date
    /// Informational only. Never used to decide how to parse.
    public var appVersion: String?
    public var comparisons: [SavedComparison]

    public init(
        schemaVersion: Int = FuelSmartDocument.currentVersion,
        exportedAt: Date = Date(),
        appVersion: String? = nil,
        comparisons: [SavedComparison]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.comparisons = comparisons
    }
}

public enum ImportError: Error, Sendable, Equatable {
    case notFuelSmartData
    case unsupportedVersion(found: Int, supported: ClosedRange<Int>)
    case corrupt(detail: String)
    case empty
    case validationFailed(reasons: [String])

    public var message: String {
        switch self {
        case .notFuelSmartData:
            "That file isn't a FuelSmart export."
        case .unsupportedVersion(let found, let supported):
            "This file was made by a newer version of FuelSmart (format \(found); this build reads \(supported.lowerBound)–\(supported.upperBound)). Update the app to open it."
        case .corrupt(let detail):
            "That file is damaged and couldn't be read. (\(detail))"
        case .empty:
            "That file doesn't contain any comparisons."
        case .validationFailed(let reasons):
            "That file contains values FuelSmart can't use: \(reasons.prefix(3).joined(separator: "; "))."
        }
    }
}

public enum ComparisonExporter {

    public static func encode(_ comparisons: [SavedComparison], appVersion: String? = nil) throws -> Data {
        let document = FuelSmartDocument(appVersion: appVersion, comparisons: comparisons)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    /// Suggested filename: `FuelSmart-Commuter-decision-2026-09-15.fuelsmart`
    public static func suggestedFilename(for comparisons: [SavedComparison], date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: date)

        let middle: String
        if comparisons.count == 1, let only = comparisons.first {
            let safe = only.name
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
            middle = safe.isEmpty ? "comparison" : safe
        } else {
            middle = "\(comparisons.count)-comparisons"
        }
        return "FuelSmart-\(middle)-\(stamp).\(FuelSmartDocument.fileExtension)"
    }
}

public enum ComparisonImporter {

    /// Decode and validate an imported document.
    ///
    /// Nothing here trusts the file. A document that decodes structurally can
    /// still carry values that would produce nonsense or crash a chart — a
    /// negative price, a zero-length horizon, a NaN — so every comparison is
    /// checked and sanitised before it is handed back.
    public static func decode(_ data: Data) throws -> [SavedComparison] {
        guard !data.isEmpty else { throw ImportError.empty }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Read the version before the body, so a newer file produces a helpful
        // message rather than a decoding error about some unrelated field.
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else {
            throw ImportError.notFuelSmartData
        }
        let supported = FuelSmartDocument.minimumSupportedVersion...FuelSmartDocument.currentVersion
        guard supported.contains(probe.schemaVersion) else {
            throw ImportError.unsupportedVersion(found: probe.schemaVersion, supported: supported)
        }

        let document: FuelSmartDocument
        do {
            document = try decoder.decode(FuelSmartDocument.self, from: data)
        } catch let error as DecodingError {
            throw ImportError.corrupt(detail: Self.describe(error))
        } catch {
            throw ImportError.corrupt(detail: error.localizedDescription)
        }

        guard !document.comparisons.isEmpty else { throw ImportError.empty }

        var accepted: [SavedComparison] = []
        var reasons: [String] = []
        for comparison in document.comparisons {
            switch sanitise(comparison) {
            case .success(let clean): accepted.append(clean)
            case .failure(let failure): reasons.append(failure.reason)
            }
        }

        guard !accepted.isEmpty else { throw ImportError.validationFailed(reasons: reasons) }
        return accepted
    }

    /// Why one comparison in an imported file could not be used.
    ///
    /// A named error type rather than a bare `String`: `Result`'s failure type
    /// must conform to `Error`, and the reason is surfaced to the user verbatim.
    struct SanitisationFailure: Error {
        let reason: String
    }

    /// Repair what can be repaired; reject what cannot.
    private static func sanitise(_ comparison: SavedComparison) -> Result<SavedComparison, SanitisationFailure> {
        var clean = comparison
        let label = comparison.name.isEmpty ? "an unnamed comparison" : "\"\(comparison.name)\""

        if clean.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clean.name = "Imported comparison"
        }
        if clean.name.count > 200 {
            clean.name = String(clean.name.prefix(200))
        }

        // A non-finite number anywhere would poison every downstream figure and
        // break the chart, and cannot be meaningfully repaired.
        let numbers: [Double] = [
            clean.scenario.driving.annualKilometres,
            clean.scenario.driving.realWorldAdjustment,
            clean.scenario.energyPrices.gasolinePricePerLitre,
            clean.scenario.energyPrices.dieselPricePerLitre,
            clean.scenario.sideA.acquisition.purchasePrice,
            clean.scenario.sideB.acquisition.purchasePrice,
        ] + clean.scenario.energyPrices.chargingSources.map(\.pricePerKWh)

        guard numbers.allSatisfy({ $0.isFinite }) else {
            return .failure(SanitisationFailure(reason: "\(label) contains an invalid number"))
        }
        guard numbers.allSatisfy({ $0 >= 0 }) else {
            return .failure(SanitisationFailure(reason: "\(label) contains a negative price or distance"))
        }
        guard clean.scenario.sideA.acquisition.purchasePrice <= ScenarioValidator.maximumPlausiblePrice,
              clean.scenario.sideB.acquisition.purchasePrice <= ScenarioValidator.maximumPlausiblePrice else {
            return .failure(SanitisationFailure(reason: "\(label) contains a price outside the supported range"))
        }
        guard clean.scenario.horizon.months_ > 0 else {
            return .failure(SanitisationFailure(reason: "\(label) has no ownership period"))
        }
        // Guard against a hostile or corrupt file asking for a simulation so
        // long it would exhaust memory.
        guard clean.scenario.horizon.months_ <= 1_200 else {
            return .failure(SanitisationFailure(reason: "\(label) has an ownership period longer than 100 years"))
        }

        for (identifier, side) in [(ComparisonSideIdentifier.a, clean.scenario.sideA), (.b, clean.scenario.sideB)] {
            if side.vehicle.make.isEmpty && side.vehicle.model.isEmpty {
                return .failure(SanitisationFailure(reason: "\(label) is missing vehicle \(identifier.rawValue.uppercased())"))
            }
        }

        return .success(clean)
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): "missing field \"\(key.stringValue)\""
        case .typeMismatch(_, let context): "unexpected value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(_, let context): "empty value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context): context.debugDescription
        @unknown default: "unrecognised problem"
        }
    }
}

private struct VersionProbe: Decodable {
    let schemaVersion: Int
}
