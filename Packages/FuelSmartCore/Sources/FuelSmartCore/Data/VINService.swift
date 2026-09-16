import Foundation

/// What a VIN decoded to, before any attempt to match it to an efficiency record.
public struct DecodedVIN: Codable, Sendable, Hashable {
    public var vin: String
    public var year: Int?
    public var make: String?
    public var model: String?
    public var trim: String?
    public var bodyClass: String?
    public var fuelTypePrimary: String?
    public var fuelTypeSecondary: String?
    public var electrificationLevel: String?
    public var engineDisplacementL: Double?
    public var engineCylinders: Int?
    public var driveType: String?
    public var transmissionStyle: String?
    public var manufacturer: String?

    public init(vin: String) { self.vin = vin }

    public var displayName: String {
        [year.map(String.init), make, model].compactMap { $0 }.joined(separator: " ")
    }

    /// Best guess at the powertrain from vPIC's several overlapping fields.
    ///
    /// vPIC describes electrification in prose ("Plug-in Hybrid Electric Vehicle
    /// (PHEV)"), so this is deliberately tolerant. It is only a hint used to
    /// narrow the match; the user confirms the final vehicle.
    public var inferredPowertrain: Powertrain? {
        let level = (electrificationLevel ?? "").lowercased()
        let primary = (fuelTypePrimary ?? "").lowercased()

        if level.contains("phev") || level.contains("plug-in") { return .phev }
        if level.contains("bev") || primary.contains("electric") && fuelTypeSecondary == nil { return .bev }
        if level.contains("hev") || level.contains("hybrid") { return .hybrid }
        if primary.contains("diesel") { return .diesel }
        if primary.contains("gasoline") || primary.contains("ethanol") { return .gasoline }
        return nil
    }
}

public enum VINError: Error, Sendable, Equatable {
    case invalidFormat(String)
    case offline
    case serviceUnavailable(status: Int)
    case decodingFailed
    case noMatch

    /// Human-readable, and never alarming: VIN lookup is optional everywhere.
    public var message: String {
        switch self {
        case .invalidFormat:
            "That doesn't look like a 17-character VIN. Check for typos, or choose the vehicle manually."
        case .offline:
            "Offline — VIN lookup unavailable. Comparing still works: the vehicle database is stored on your device."
        case .serviceUnavailable:
            "The VIN service isn't responding right now. You can choose the vehicle manually instead."
        case .decodingFailed:
            "That VIN couldn't be decoded. You can choose the vehicle manually instead."
        case .noMatch:
            "The VIN decoded, but no matching efficiency record was found. Pick the closest configuration."
        }
    }
}

/// Decodes a VIN using the free NHTSA vPIC API.
///
/// Entirely optional. Every failure path returns a value the UI can explain, and
/// **a VIN failure must never prevent manual vehicle selection** — nothing in the
/// picker depends on this type succeeding.
///
/// No API key. No account. No commercial service. Results are cached locally so a
/// repeated lookup works offline.
public actor VINService {

    private let session: URLSession
    private let endpoint: String
    private var cache: [String: DecodedVIN] = [:]

    public init(
        session: URLSession = .shared,
        endpoint: String = "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues"
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    /// VIN check-digit validation (ISO 3779 / 49 CFR 565).
    ///
    /// Catches most typos before a network call is attempted, which matters
    /// because the alternative is a slow round trip that returns nothing useful.
    /// Note that this is advisory: some legitimately-issued VINs, particularly
    /// older and non-North-American ones, fail the check digit, so a failure
    /// warns rather than blocks.
    public nonisolated static func isPlausible(_ vin: String) -> Bool {
        let cleaned = vin.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count == 17 else { return false }
        // I, O and Q are never used, precisely to avoid confusion with 1 and 0.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHJKLMNPRSTUVWXYZ0123456789")
        return cleaned.unicodeScalars.allSatisfy(allowed.contains)
    }

    public nonisolated static func passesCheckDigit(_ vin: String) -> Bool {
        let cleaned = vin.uppercased()
        guard isPlausible(cleaned) else { return false }

        let values: [Character: Int] = [
            "A": 1, "B": 2, "C": 3, "D": 4, "E": 5, "F": 6, "G": 7, "H": 8,
            "J": 1, "K": 2, "L": 3, "M": 4, "N": 5, "P": 7, "R": 9,
            "S": 2, "T": 3, "U": 4, "V": 5, "W": 6, "X": 7, "Y": 8, "Z": 9,
        ]
        let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]

        var sum = 0
        for (offset, character) in cleaned.enumerated() {
            let value: Int
            if let digit = character.wholeNumberValue, character.isNumber {
                value = digit
            } else if let mapped = values[character] {
                value = mapped
            } else {
                return false
            }
            sum += value * weights[offset]
        }

        let remainder = sum % 11
        let expected: Character = remainder == 10 ? "X" : Character(String(remainder))
        return Array(cleaned)[8] == expected
    }

    /// Decode a VIN, using the local cache when possible.
    public func decode(_ vin: String) async throws -> DecodedVIN {
        let cleaned = vin.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isPlausible(cleaned) else { throw VINError.invalidFormat(cleaned) }

        if let cached = cache[cleaned] { return cached }

        guard let url = URL(string: "\(endpoint)/\(cleaned)?format=json") else {
            throw VINError.invalidFormat(cleaned)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .returnCacheDataElseLoad

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where
            error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw VINError.offline
        } catch {
            throw VINError.serviceUnavailable(status: -1)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw VINError.serviceUnavailable(status: http.statusCode)
        }

        guard let payload = try? JSONDecoder().decode(VPICResponse.self, from: data),
              let row = payload.Results.first else {
            throw VINError.decodingFailed
        }

        let decoded = row.toDecodedVIN(vin: cleaned)
        // vPIC answers 200 with empty fields for an unknown VIN.
        guard decoded.make != nil || decoded.model != nil else { throw VINError.decodingFailed }

        cache[cleaned] = decoded
        return decoded
    }

    public func cachedResult(for vin: String) -> DecodedVIN? {
        cache[vin.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    /// Seed the cache from persisted storage at launch.
    public func primeCache(with entries: [DecodedVIN]) {
        for entry in entries { cache[entry.vin] = entry }
    }

    public func cachedEntries() -> [DecodedVIN] { Array(cache.values) }
}

// MARK: - Matching a decoded VIN to an efficiency record

public enum VINMatcher {

    /// Find the efficiency records that plausibly correspond to a decoded VIN.
    ///
    /// Deliberately returns *candidates* rather than picking one. vPIC's model
    /// names do not always match the fuel-economy datasets' spellings, and a VIN
    /// does not identify a trim precisely enough to choose between
    /// configurations with different ratings. The user confirms.
    public static func candidates(
        for decoded: DecodedVIN,
        in repository: any VehicleRepository,
        limit: Int = 20
    ) async throws -> [Vehicle] {
        guard let make = decoded.make else { throw VINError.noMatch }

        var query = make
        if let model = decoded.model { query += " \(model)" }

        var filter = VehicleFilter()
        if let year = decoded.year { filter.years = [year] }
        if let powertrain = decoded.inferredPowertrain { filter.powertrains = [powertrain] }

        var matches = try await repository.search(query, filter: filter, limit: limit)

        // Progressive relaxation: the powertrain hint is the least reliable
        // field, then the exact model name. Widening beats returning nothing,
        // because the user can still see and pick the right configuration.
        if matches.isEmpty, !filter.powertrains.isEmpty {
            filter.powertrains = []
            matches = try await repository.search(query, filter: filter, limit: limit)
        }
        if matches.isEmpty {
            matches = try await repository.search(make, filter: filter, limit: limit)
        }
        if matches.isEmpty { throw VINError.noMatch }
        return matches
    }
}

// MARK: - vPIC wire format

private struct VPICResponse: Decodable {
    let Results: [VPICRow]
}

/// vPIC's `DecodeVinValues` endpoint returns one flat object of string fields,
/// using "" and "Not Applicable" for absent values.
private struct VPICRow: Decodable {
    var ModelYear: String?
    var Make: String?
    var Model: String?
    var Trim: String?
    var BodyClass: String?
    var FuelTypePrimary: String?
    var FuelTypeSecondary: String?
    var ElectrificationLevel: String?
    var DisplacementL: String?
    var EngineCylinders: String?
    var DriveType: String?
    var TransmissionStyle: String?
    var Manufacturer: String?

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.caseInsensitiveCompare("Not Applicable") != .orderedSame,
              trimmed.caseInsensitiveCompare("Not Available") != .orderedSame
        else { return nil }
        return trimmed
    }

    func toDecodedVIN(vin: String) -> DecodedVIN {
        var decoded = DecodedVIN(vin: vin)
        decoded.year = clean(ModelYear).flatMap(Int.init)
        decoded.make = clean(Make).map { $0.capitalized }
        decoded.model = clean(Model)
        decoded.trim = clean(Trim)
        decoded.bodyClass = clean(BodyClass)
        decoded.fuelTypePrimary = clean(FuelTypePrimary)
        decoded.fuelTypeSecondary = clean(FuelTypeSecondary)
        decoded.electrificationLevel = clean(ElectrificationLevel)
        decoded.engineDisplacementL = clean(DisplacementL).flatMap(Double.init)
        decoded.engineCylinders = clean(EngineCylinders).flatMap(Int.init)
        decoded.driveType = clean(DriveType)
        decoded.transmissionStyle = clean(TransmissionStyle)
        decoded.manufacturer = clean(Manufacturer)
        return decoded
    }
}
