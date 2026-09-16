import Foundation

/// A prefix index over the vehicle database, built once and reused.
///
/// The requirement is that typing feels instant across tens of thousands of
/// records. Scanning every record on every keystroke would be roughly 25,000
/// string comparisons per character; instead each record is tokenised once into
/// a small set of lowercase, diacritic-folded terms, and a dictionary maps each
/// term to the records containing it.
///
/// Memory cost is modest — the postings hold `Int32` offsets into the record
/// array rather than copies of anything — and lookup is a dictionary hit per
/// query token plus a set intersection.
public struct VehicleSearchIndex: Sendable {

    /// term → offsets of records containing it
    private let postings: [String: [Int32]]
    /// Every distinct term, sorted, so prefix matches can be found by binary search.
    private let sortedTerms: [String]
    private let recordCount: Int

    /// Longer prefixes are cheap; a single character can match most of the
    /// database, so very short queries are answered from whole-token matches
    /// only and the UI asks the user to keep typing.
    public static let minimumPrefixLength = 2

    // MARK: - Building

    public init(vehicles: [Vehicle]) {
        var postings: [String: [Int32]] = [:]
        postings.reserveCapacity(vehicles.count * 2)

        for (offset, vehicle) in vehicles.enumerated() {
            let index = Int32(offset)
            for term in Self.terms(for: vehicle) {
                postings[term, default: []].append(index)
            }
        }

        self.postings = postings
        self.sortedTerms = postings.keys.sorted()
        self.recordCount = vehicles.count
    }

    /// Everything a user might reasonably type to find this vehicle.
    static func terms(for vehicle: Vehicle) -> Set<String> {
        var terms: Set<String> = []

        func add(_ text: String?) {
            guard let text, !text.isEmpty else { return }
            for token in normalize(text).split(separator: " ") where token.count >= 1 {
                terms.insert(String(token))
            }
        }

        add(vehicle.make)
        add(vehicle.model)
        add(vehicle.configuration)
        add(String(vehicle.year))
        add(vehicle.vehicleClass)
        add(vehicle.powertrain.displayName)
        add(vehicle.fuelDescription)

        // "model3" as well as "model" + "3", so a spaceless query still hits.
        let joined = normalize("\(vehicle.make)\(vehicle.model)")
            .replacingOccurrences(of: " ", with: "")
        if !joined.isEmpty { terms.insert(joined) }

        return terms
    }

    /// Lowercase, strip diacritics, and reduce punctuation to spaces.
    ///
    /// Folding diacritics matters for real government data: a user typing
    /// "Citroen" must still find "Citroën", and NRCan ships accented model names.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        var result = ""
        result.reserveCapacity(folded.count)
        var lastWasSpace = true
        for character in folded {
            if character.isLetter || character.isNumber {
                result.append(character)
                lastWasSpace = false
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Querying

    /// Record offsets matching every token in the query.
    ///
    /// Tokens are ANDed, so "hybrid suv" narrows rather than widens, and each
    /// token matches by prefix so "cam" finds "Camry" mid-type.
    public func matches(for query: String) -> [Int32] {
        let tokens = Self.normalize(query).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }

        var running: Set<Int32>?
        for token in tokens {
            let offsets = offsets(matchingPrefix: token)
            if offsets.isEmpty { return [] }
            running = running.map { $0.intersection(offsets) } ?? offsets
            if running?.isEmpty == true { return [] }
        }
        return Array(running ?? [])
    }

    private func offsets(matchingPrefix prefix: String) -> Set<Int32> {
        // An exact term hit is the common case and needs no scan.
        var result = Set(postings[prefix] ?? [])

        guard prefix.count >= Self.minimumPrefixLength else { return result }

        // Terms sharing a prefix are contiguous once sorted, so a binary search
        // for the lower bound and a walk forward covers them without touching
        // the rest of the vocabulary.
        var low = 0
        var high = sortedTerms.count
        while low < high {
            let middle = (low + high) / 2
            if sortedTerms[middle] < prefix { low = middle + 1 } else { high = middle }
        }
        var cursor = low
        while cursor < sortedTerms.count, sortedTerms[cursor].hasPrefix(prefix) {
            if sortedTerms[cursor] != prefix, let offsets = postings[sortedTerms[cursor]] {
                result.formUnion(offsets)
            }
            cursor += 1
        }
        return result
    }

    /// Rank a match. Higher is better.
    ///
    /// Ordering rules, in descending weight: an exact make or model word beats a
    /// mid-word prefix; newer model years come first; then alphabetical, which
    /// the caller applies as a tiebreak.
    public static func score(_ vehicle: Vehicle, query: String) -> Int {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return 0 }
        let tokens = normalized.split(separator: " ").map(String.init)

        let make = normalize(vehicle.make)
        let model = normalize(vehicle.model)
        let configuration = normalize(vehicle.configuration ?? "")

        var score = 0
        for token in tokens {
            if model == token || make == token { score += 100 }
            else if model.hasPrefix(token) || make.hasPrefix(token) { score += 60 }
            else if configuration.hasPrefix(token) { score += 30 }
            else if model.contains(token) || make.contains(token) { score += 15 }
            else { score += 5 }
        }
        // Recency, bounded so it never outranks a genuine name match.
        score += min(max(vehicle.year - 1990, 0), 40)
        return score
    }
}
