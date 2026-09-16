import SwiftUI
import SwiftData
import FuelSmartCore

/// Official data for one configuration, with its source.
///
/// **Only fields the publisher actually supplied are shown.** A missing value is
/// omitted rather than rendered as a zero or a guess, which is the whole reason
/// every efficiency field in the domain model is optional.
struct VehicleDetailScreen: View {

    let vehicle: Vehicle
    let region: Region
    var onUse: ((Vehicle) -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.fsTheme) private var theme
    @Environment(\.modelContext) private var context

    @State private var sources: [DataSourceMetadata] = []
    @State private var isFavourite = false

    private var formatter: ValueFormatter { ValueFormatter(region: region) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                heading
                tags
                efficiencyCard
                if hasSpecifications { specificationsCard }
                if hasRatings { ratingsCard }
                sourceCard
                caveat
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 90)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("Vehicle")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggleFavourite()
                } label: {
                    Image(systemName: isFavourite ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(isFavourite ? "Remove from favourites" : "Add to favourites")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let onUse {
                Button("Use this vehicle") { onUse(vehicle) }
                    .buttonStyle(FSPrimaryButtonStyle())
                    .padding(.horizontal, Nocturne.Space.gutter)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .task {
            sources = (try? await model.repository(for: region).dataSources()) ?? []
            loadFavouriteState()
        }
    }

    // MARK: - Sections

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vehicle.displayName)
                .font(FSFont.title)
                .foregroundStyle(theme.text)
            if let subtitle {
                Text(subtitle)
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(.top, 4)
    }

    private var subtitle: String? {
        let parts = [vehicle.configuration, vehicle.drive, vehicle.fuelDescription].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var tags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FSTag.powertrain(vehicle.powertrain)
                if let vehicleClass = vehicle.vehicleClass {
                    FSTag(text: vehicleClass, style: .neutral)
                }
                if vehicle.isUserDefined {
                    FSTag(text: "Entered by you", style: .outline)
                }
            }
        }
    }

    private var efficiencyCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 14) {
                FSSectionLabel("Official efficiency data")

                if vehicle.powertrain.usesElectricity, vehicle.efficiency.combinedKwhPer100Km != nil {
                    tileRow(
                        city: vehicle.efficiency.cityKwhPer100Km,
                        highway: vehicle.efficiency.highwayKwhPer100Km,
                        combined: vehicle.efficiency.combinedKwhPer100Km,
                        format: { formatter.electricConsumption($0) },
                        unit: region == .canada ? "kWh/100 km" : "kWh/100 mi"
                    )
                }

                if vehicle.powertrain.usesLiquidFuel, vehicle.efficiency.combinedLPer100Km != nil {
                    tileRow(
                        city: vehicle.efficiency.cityLPer100Km,
                        highway: vehicle.efficiency.highwayLPer100Km,
                        combined: vehicle.efficiency.combinedLPer100Km,
                        format: { formatter.fuelConsumption($0) },
                        unit: region == .canada ? "L/100 km" : "MPG"
                    )
                }

                if !hasAnyEfficiency {
                    Text("This configuration has no published consumption rating.")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.secondaryText)
                }

                detailRows
            }
        }
    }

    private func tileRow(
        city: Double?, highway: Double?, combined: Double?,
        format: (Double?) -> String, unit: String
    ) -> some View {
        HStack(spacing: 9) {
            if let city { FSDataTile(label: "City", value: stripUnit(format(city)), unit: unit) }
            if let highway { FSDataTile(label: "Hwy", value: stripUnit(format(highway)), unit: unit) }
            if let combined {
                FSDataTile(label: "Comb", value: stripUnit(format(combined)), unit: unit, isAccented: true)
            }
        }
    }

    /// The tiles carry their own unit caption, so the formatted string's trailing
    /// unit is removed rather than shown twice.
    private func stripUnit(_ text: String) -> String {
        text.split(separator: " ").first.map(String.init) ?? text
    }

    @ViewBuilder
    private var detailRows: some View {
        let rows = specificationRows
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    HStack {
                        Text(row.label).font(FSFont.footnote).foregroundStyle(theme.secondaryText)
                        Spacer()
                        Text(row.value).font(FSFont.figureSmall).foregroundStyle(theme.text)
                    }
                    .padding(.vertical, 10)
                    if index < rows.count - 1 {
                        Divider().overlay(theme.divider)
                    }
                }
            }
        }
    }

    /// Only rows whose value actually exists.
    private var specificationRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let range = vehicle.efficiency.electricRangeKm {
            rows.append(("Electric range", formatter.distance(range)))
        }
        if let total = vehicle.efficiency.totalRangeKm,
           total != vehicle.efficiency.electricRangeKm {
            rows.append(("Total range", formatter.distance(total)))
        }
        if let recharge = vehicle.efficiency.rechargeHours {
            rows.append(("Recharge time", "\(recharge.formatted(.number.precision(.fractionLength(0...1)))) h"))
        }
        if let co2 = vehicle.efficiency.co2GramsPerKm {
            let value = region == .canada
                ? "\(Int(co2.rounded())) g/km"
                : "\(Int((co2 * UnitConversionService.kilometresPerMile).rounded())) g/mi"
            rows.append(("Tailpipe CO₂", value))
        }
        return rows
    }

    private var hasSpecifications: Bool {
        vehicle.engineSizeL != nil || vehicle.cylinders != nil
            || vehicle.transmission != nil || vehicle.drive != nil
    }

    private var specificationsCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                FSSectionLabel("Mechanical")
                VStack(spacing: 0) {
                    let rows = mechanicalRows
                    ForEach(rows.indices, id: \.self) { index in
                        let row = rows[index]
                        HStack {
                            Text(row.label).font(FSFont.footnote).foregroundStyle(theme.secondaryText)
                            Spacer()
                            Text(row.value).font(FSFont.footnote).foregroundStyle(theme.text)
                        }
                        .padding(.vertical, 9)
                        if index < rows.count - 1 { Divider().overlay(theme.divider) }
                    }
                }
            }
        }
    }

    private var mechanicalRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let engine = vehicle.engineSizeL {
            rows.append(("Engine", "\(engine.formatted(.number.precision(.fractionLength(1)))) L"))
        }
        if let cylinders = vehicle.cylinders {
            rows.append(("Cylinders", String(cylinders)))
        }
        if let transmission = vehicle.transmission {
            rows.append(("Transmission", transmission))
        }
        if let drive = vehicle.drive {
            rows.append(("Drive", drive))
        }
        return rows
    }

    private var hasRatings: Bool {
        vehicle.efficiency.co2Rating != nil
            || vehicle.efficiency.smogRating != nil
            || vehicle.efficiency.fuelEconomyScore != nil
    }

    private var ratingsCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                FSSectionLabel("Government ratings")
                HStack(spacing: 9) {
                    if let co2 = vehicle.efficiency.co2Rating {
                        FSDataTile(label: "CO₂", value: "\(co2)", unit: "of 10")
                    }
                    if let smog = vehicle.efficiency.smogRating {
                        FSDataTile(label: "Smog", value: "\(smog)", unit: "of 10")
                    }
                    if let score = vehicle.efficiency.fuelEconomyScore {
                        FSDataTile(label: "Economy", value: "\(score)", unit: "of 10")
                    }
                }
            }
        }
    }

    private var sourceCard: some View {
        FSCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "cylinder.split.1x2")
                    .foregroundStyle(theme.secondaryText)
                VStack(alignment: .leading, spacing: 3) {
                    Text(sourceDescription)
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let source = matchingSource, let url = source.landingPage.flatMap(URL.init) {
                        Link("View source", destination: url)
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.accentMuted)
                    }
                }
            }
        }
    }

    private var matchingSource: DataSourceMetadata? {
        sources.first { $0.id == vehicle.sourceId } ?? sources.first
    }

    private var sourceDescription: String {
        guard let source = matchingSource else {
            return "Official government efficiency data."
        }
        var text = "\(source.publisher) — \(source.dataset)"
        if let version = source.datasetVersion { text += ", dataset \(version)" }
        return text
    }

    private var caveat: some View {
        Text("Ratings are laboratory figures. Your real consumption depends on climate, terrain and driving style — adjust it in the driving profile.")
            .font(FSFont.footnote)
            .foregroundStyle(theme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var hasAnyEfficiency: Bool {
        vehicle.efficiency.combinedLPer100Km != nil || vehicle.efficiency.combinedKwhPer100Km != nil
    }

    // MARK: - Favourites

    private func loadFavouriteState() {
        let id = vehicle.id
        let descriptor = FetchDescriptor<VehicleBookmarkEntity>(predicate: #Predicate { $0.vehicleId == id })
        isFavourite = (try? context.fetch(descriptor).first?.isFavourite) as? Bool ?? false
    }

    private func toggleFavourite() {
        let id = vehicle.id
        let descriptor = FetchDescriptor<VehicleBookmarkEntity>(predicate: #Predicate { $0.vehicleId == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.isFavourite.toggle()
            isFavourite = existing.isFavourite
        } else {
            context.insert(VehicleBookmarkEntity(vehicle: vehicle, isFavourite: true))
            isFavourite = true
        }
        try? context.save()
    }
}
