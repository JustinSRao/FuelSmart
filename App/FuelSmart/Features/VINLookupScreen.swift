import SwiftUI
import SwiftData
import FuelSmartCore

/// Optional VIN decoding via the free NHTSA vPIC service.
///
/// Every failure path here ends with a route back to manual selection. **A VIN
/// lookup failure must never prevent choosing a vehicle by hand**, so the
/// "Choose manually" action is present in every error state, and the screen can
/// be dismissed at any point without consequence.
struct VINLookupScreen: View {

    let region: Region
    var onSelect: (Vehicle) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.fsTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var vin = ""
    @State private var state: LookupState = .idle

    private enum LookupState {
        case idle
        case decoding
        case decoded(DecodedVIN, candidates: [Vehicle])
        case failed(VINError, decoded: DecodedVIN?)
    }

    private var trimmedVIN: String {
        vin.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canLookUp: Bool { VINService.isPlausible(trimmedVIN) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                explanation
                entryCard
                stateContent
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("VIN lookup")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task { await primeCache() }
    }

    // MARK: - Sections

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Identify a vehicle from its VIN")
                .font(FSFont.title)
                .foregroundStyle(theme.text)
            Text("The 17-character number on the dashboard, door frame or registration. FuelSmart sends only the VIN, to the U.S. government's free vehicle-identification service, and matches the result to an efficiency record.")
                .font(FSFont.footnote)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private var entryCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                FSSectionLabel("VIN")
                TextField("1HGCM82633A004352", text: $vin)
                    .font(FSFont.figureMedium)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                            .fill(theme.inset)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                            .strokeBorder(canLookUp ? theme.accent : theme.border, lineWidth: canLookUp ? 2 : 1)
                    )
                    .accessibilityLabel("Vehicle identification number")

                HStack {
                    Text("\(trimmedVIN.count) of 17")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.tertiaryText)
                    Spacer()
                    // The check digit is advisory, not a gate: some legitimately
                    // issued VINs — particularly older and non-North-American
                    // ones — fail it, and vPIC decodes them anyway.
                    if canLookUp && !VINService.passesCheckDigit(trimmedVIN) {
                        Label("Check digit doesn't match", systemImage: "exclamationmark.circle")
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.secondaryText)
                    }
                }

                Button("Decode VIN") { Task { await lookUp() } }
                    .buttonStyle(FSPrimaryButtonStyle(height: Nocturne.controlHeight))
                    .disabled(!canLookUp || isDecoding)
            }
        }
    }

    private var isDecoding: Bool {
        if case .decoding = state { return true }
        return false
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .idle:
            EmptyView()

        case .decoding:
            FSCard {
                VStack(alignment: .leading, spacing: 9) {
                    FSSkeleton(height: 16, widthFraction: 0.6)
                    FSSkeleton(height: 40)
                }
            }

        case .decoded(let decoded, let candidates):
            decodedCard(decoded)
            if candidates.isEmpty {
                noMatchCard(decoded)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    FSSectionLabel("Matching records")
                    Text("A VIN doesn't identify a trim precisely enough to choose between ratings. Pick the configuration that matches your vehicle.")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(candidates) { vehicle in
                        Button { onSelect(vehicle) } label: {
                            FSCard { VehicleRow(vehicle: vehicle, formatter: ValueFormatter(region: region)) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        case .failed(let error, let decoded):
            FSNoticeCard(
                severity: error == .offline ? .info : .warning,
                systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
                title: title(for: error),
                message: error.message,
                actions: [
                    ("Choose manually", { dismiss() }),
                    ("Try again", { Task { await lookUp() } }),
                ]
            )
            if let decoded { decodedCard(decoded) }
        }
    }

    private func title(for error: VINError) -> String {
        switch error {
        case .offline: "Offline — VIN lookup unavailable"
        case .invalidFormat: "That VIN doesn't look right"
        case .noMatch: "No matching efficiency record"
        case .serviceUnavailable, .decodingFailed: "VIN lookup didn't work"
        }
    }

    private func decodedCard(_ decoded: DecodedVIN) -> some View {
        FSCard {
            VStack(alignment: .leading, spacing: 10) {
                FSSectionLabel("Decoded")
                Text(decoded.displayName.isEmpty ? "Unknown vehicle" : decoded.displayName)
                    .font(FSFont.headline)
                    .foregroundStyle(theme.text)
                let rows = decodedRows(decoded)
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    HStack {
                        Text(row.label).font(FSFont.footnote).foregroundStyle(theme.secondaryText)
                        Spacer()
                        Text(row.value).font(FSFont.footnote).foregroundStyle(theme.text)
                    }
                }
            }
        }
    }

    /// Only the fields vPIC actually returned.
    private func decodedRows(_ decoded: DecodedVIN) -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let trim = decoded.trim { rows.append(("Trim", trim)) }
        if let body = decoded.bodyClass { rows.append(("Body", body)) }
        if let fuel = decoded.fuelTypePrimary { rows.append(("Fuel", fuel)) }
        if let level = decoded.electrificationLevel { rows.append(("Electrification", level)) }
        if let displacement = decoded.engineDisplacementL {
            rows.append(("Engine", "\(displacement.formatted(.number.precision(.fractionLength(1)))) L"))
        }
        if let drive = decoded.driveType { rows.append(("Drive", drive)) }
        return rows
    }

    private func noMatchCard(_ decoded: DecodedVIN) -> some View {
        FSNoticeCard(
            severity: .info,
            systemImage: "magnifyingglass",
            title: "Decoded, but not in the efficiency dataset",
            message: "The VIN identified a \(decoded.displayName), but no matching rating was found in this region's dataset. Choose the closest configuration by hand.",
            actions: [("Choose manually", { dismiss() })]
        )
    }

    // MARK: - Lookup

    private func lookUp() async {
        state = .decoding
        do {
            let decoded = try await model.vinService.decode(trimmedVIN)
            cache(decoded)
            do {
                let candidates = try await VINMatcher.candidates(
                    for: decoded, in: model.repository(for: region)
                )
                state = .decoded(decoded, candidates: candidates)
            } catch {
                // Decoding worked; matching did not. That is still a useful
                // result, so the decoded details are shown with a manual route.
                state = .decoded(decoded, candidates: [])
            }
        } catch let error as VINError {
            state = .failed(error, decoded: nil)
        } catch {
            state = .failed(.serviceUnavailable(status: -1), decoded: nil)
        }
    }

    /// Persist the decoded result so a repeat lookup works with no connection.
    private func cache(_ decoded: DecodedVIN) {
        let key = decoded.vin
        let descriptor = FetchDescriptor<CachedVINEntity>(predicate: #Predicate { $0.vin == key })
        if (try? context.fetch(descriptor).first) == nil,
           let entity = try? CachedVINEntity(decoded: decoded) {
            context.insert(entity)
            try? context.save()
        }
    }

    /// Seed the in-memory cache from disk so previously decoded VINs resolve
    /// instantly and offline.
    private func primeCache() async {
        let descriptor = FetchDescriptor<CachedVINEntity>()
        let stored = (try? context.fetch(descriptor)) ?? []
        let decoded = stored.compactMap { try? $0.toDecodedVIN() }
        guard !decoded.isEmpty else { return }
        await model.vinService.primeCache(with: decoded)
    }
}
