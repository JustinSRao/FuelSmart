import SwiftUI
import FuelSmartCore

/// How far and how the user drives.
///
/// Distance can be entered per day, week, month or year and is normalized to a
/// year before it reaches the engine, so the same figure means the same thing
/// however it was typed.
struct DrivingProfileScreen: View {

    @Bindable var draft: ComparisonDraft

    @Environment(AppModel.self) private var model
    @Environment(\.fsTheme) private var theme

    private var formatter: ValueFormatter { ValueFormatter(region: draft.region) }
    private var distanceUnit: String { formatter.distanceUnit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                distanceCard
                mixCard
                conditionsCard
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 32)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("Driving profile")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var distanceCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 13) {
                FSSectionLabel("How far you drive")

                FSNumberField(
                    label: "Distance",
                    value: Binding(
                        get: { draft.distanceEntry },
                        set: { draft.distanceEntry = $0; draft.applyDistanceEntry() }
                    ),
                    unit: distanceUnit,
                    isProminent: true,
                    fractionDigits: 0...0,
                    plausibleRange: 1...200_000
                )

                FSSegmented(
                    options: DistancePeriod.allCases.map { ($0, $0.rawValue) },
                    selection: Binding(
                        get: { draft.distancePeriod },
                        set: { draft.distancePeriod = $0; draft.applyDistanceEntry() }
                    ),
                    accessibilityPrefix: "Per "
                )

                if draft.driving.annualKilometres > 0 {
                    Text(normalizedSummary)
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.tertiaryText)
                } else {
                    Label("Enter a distance above zero to compare.", systemImage: "exclamationmark.circle")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.warning)
                }
            }
        }
    }

    private var normalizedSummary: String {
        let perDay = draft.driving.annualKilometres / 365.25
        let perMonth = draft.driving.annualKilometres / 12
        return "≈ \(formatter.distance(perDay))/day · \(formatter.distance(perMonth))/month. Everything is normalised to a year."
    }

    private var mixCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    FSSectionLabel("Driving mix")
                    Spacer()
                    Text(formatter.split(draft.driving.cityHighwaySplit, primaryLabel: "city", secondaryLabel: "highway"))
                        .font(FSFont.figureSmall)
                        .foregroundStyle(theme.text)
                }

                FSSplitSlider(
                    split: Binding(
                        get: { draft.driving.cityHighwaySplit },
                        set: { draft.driving.cityHighwaySplit = $0 }
                    ),
                    primaryLabel: "City",
                    secondaryLabel: "Highway"
                )

                Text("City and highway always total 100 %, and each vehicle is rated on the mix you set — hybrids gain in the city, electric vehicles lose a little on the highway.")
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if usesCombinedFallback {
                    Label(
                        "One of these vehicles has no separate city and highway rating, so its combined figure is used instead.",
                        systemImage: "info.circle"
                    )
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Surfaced so the fallback is visible rather than silent.
    private var usesCombinedFallback: Bool {
        [draft.vehicleA, draft.vehicleB].compactMap { $0 }.contains { vehicle in
            if vehicle.powertrain.usesLiquidFuel && !vehicle.efficiency.hasSplitFuelRatings { return true }
            if vehicle.powertrain.usesElectricity && !vehicle.efficiency.hasSplitElectricRatings { return true }
            return false
        }
    }

    private var conditionsCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                FSSectionLabel("Conditions")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(DrivingProfile.Conditions.allCases, id: \.self) { condition in
                            Button {
                                draft.applyConditions(condition)
                            } label: {
                                FSTag(
                                    text: condition.displayName,
                                    style: draft.conditions == condition ? .accent : .outline
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(draft.conditions == condition ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if draft.conditions == .custom {
                    FSNumberField(
                        label: "Efficiency adjustment",
                        caption: "Percentage above the official rating.",
                        value: Binding(
                            get: { draft.driving.realWorldAdjustment * 100 },
                            set: { draft.driving.realWorldAdjustment = $0 / 100 }
                        ),
                        unit: "% more energy",
                        fractionDigits: 0...0,
                        plausibleRange: -20...60
                    )
                } else {
                    FSInsetRow(padding: 11) {
                        HStack {
                            Text("Efficiency adjustment")
                                .font(FSFont.body)
                                .foregroundStyle(theme.text)
                            Spacer()
                            Text(adjustmentDescription)
                                .font(FSFont.figureSmall)
                                .foregroundStyle(theme.text)
                        }
                    }
                }

                Text("Government ratings are standardized laboratory tests. This is a scenario assumption you are choosing, applied equally to both vehicles — the official rating itself is never changed.")
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var adjustmentDescription: String {
        let percent = draft.driving.realWorldAdjustment * 100
        if percent == 0 { return "Official rating" }
        let sign = percent > 0 ? "+" : ""
        return "\(sign)\(Int(percent.rounded())) % consumption"
    }
}

// MARK: - Energy prices

/// What the user pays for fuel and electricity.
///
/// Simple mode is a single electricity price; advanced mode splits home and
/// public charging and shows the blended rate the engine will actually use.
struct EnergyPricesScreen: View {

    @Bindable var draft: ComparisonDraft

    @Environment(AppModel.self) private var model
    @Environment(\.fsTheme) private var theme

    @State private var advancedCharging = true

    private var formatter: ValueFormatter { ValueFormatter(region: draft.region) }
    private var region: Region { draft.region }

    private var needsFuel: Bool {
        [draft.vehicleA, draft.vehicleB].compactMap { $0 }.contains { $0.powertrain.usesLiquidFuel }
    }
    private var needsDiesel: Bool {
        [draft.vehicleA, draft.vehicleB].compactMap { $0 }.contains { $0.powertrain == .diesel }
    }
    private var needsElectricity: Bool {
        [draft.vehicleA, draft.vehicleB].compactMap { $0 }.contains { $0.powertrain.usesElectricity }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if needsFuel { fuelCard }
                if needsElectricity { electricityCard }
                if !needsFuel && !needsElectricity {
                    FSNoticeCard(
                        severity: .info,
                        systemImage: "info.circle",
                        title: "Choose vehicles first",
                        message: "Energy prices appear once FuelSmart knows which kinds of energy your vehicles use."
                    )
                }
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 32)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("Energy costs")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var fuelCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                FSSectionLabel(needsDiesel ? "Fuel" : "Gasoline")

                // Prices are typed in the region's own unit and converted to the
                // canonical per-litre figure at this boundary.
                FSNumberField(
                    label: "Gasoline",
                    value: Binding(
                        get: {
                            UnitConversionService.fuelPriceFromPerLitre(
                                draft.energyPrices.gasolinePricePerLitre, region: region
                            )
                        },
                        set: {
                            draft.energyPrices.gasolinePricePerLitre =
                                UnitConversionService.fuelPriceToPerLitre($0, region: region)
                        }
                    ),
                    unit: region == .canada ? "/ L" : "/ gal",
                    isProminent: true,
                    fractionDigits: 0...3,
                    plausibleRange: 0...(region == .canada ? 5 : 15)
                )

                if needsDiesel {
                    FSNumberField(
                        label: "Diesel",
                        value: Binding(
                            get: {
                                UnitConversionService.fuelPriceFromPerLitre(
                                    draft.energyPrices.dieselPricePerLitre, region: region
                                )
                            },
                            set: {
                                draft.energyPrices.dieselPricePerLitre =
                                    UnitConversionService.fuelPriceToPerLitre($0, region: region)
                            }
                        ),
                        unit: region == .canada ? "/ L" : "/ gal",
                        fractionDigits: 0...3,
                        plausibleRange: 0...(region == .canada ? 5 : 15)
                    )
                }
            }
        }
    }

    private var electricityCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    FSSectionLabel("Electricity")
                    Spacer()
                    Button(advancedCharging ? "Simple" : "Advanced") {
                        withAnimation(FSMotion.valueChange) { advancedCharging.toggle() }
                    }
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.accentMuted)
                }

                if advancedCharging {
                    FSNumberField(
                        label: "Home charging",
                        value: chargingPriceBinding(id: "home"),
                        unit: "/ kWh",
                        fractionDigits: 0...3,
                        plausibleRange: 0...2
                    )
                    FSNumberField(
                        label: "Public charging",
                        value: chargingPriceBinding(id: "public"),
                        unit: "/ kWh",
                        fractionDigits: 0...3,
                        plausibleRange: 0...2
                    )

                    FSSplitSlider(
                        split: Binding(
                            get: { Split(primary: homeShare) },
                            set: { setHomeShare($0.primary) }
                        ),
                        primaryLabel: "Home",
                        secondaryLabel: "Public",
                        height: 30
                    )

                    FSInsetRow(padding: 12) {
                        HStack {
                            Text("Blended charging cost")
                                .font(FSFont.body)
                                .foregroundStyle(theme.accentMuted)
                            Spacer()
                            Text(formatter.electricityPrice(draft.energyPrices.blendedElectricityPricePerKWh))
                                .font(FSFont.figureMedium)
                                .foregroundStyle(theme.accentText)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    Text("Each charging source is weighted by its share of your charging. Percentages always total 100 %.")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    FSNumberField(
                        label: "Electricity",
                        value: Binding(
                            get: { draft.energyPrices.blendedElectricityPricePerKWh },
                            set: { newValue in
                                draft.energyPrices.chargingSources = [
                                    .init(id: "single", name: "Electricity", pricePerKWh: newValue, share: 1)
                                ]
                            }
                        ),
                        unit: "/ kWh",
                        isProminent: true,
                        fractionDigits: 0...3,
                        plausibleRange: 0...2
                    )
                }
            }
        }
    }

    // MARK: - Charging bindings

    private var homeShare: Double {
        let sources = draft.energyPrices.chargingSources
        let total = sources.reduce(0) { $0 + max($1.share, 0) }
        guard total > 0 else { return 0.8 }
        return (sources.first { $0.id == "home" }?.share ?? 0) / total
    }

    private func setHomeShare(_ value: Double) {
        ensureAdvancedSources()
        draft.energyPrices.chargingSources = draft.energyPrices.chargingSources.map { source in
            var updated = source
            updated.share = source.id == "home" ? value : 1 - value
            return updated
        }
    }

    private func chargingPriceBinding(id: String) -> Binding<Double> {
        Binding(
            get: { draft.energyPrices.chargingSources.first { $0.id == id }?.pricePerKWh ?? 0 },
            set: { newValue in
                ensureAdvancedSources()
                draft.energyPrices.chargingSources = draft.energyPrices.chargingSources.map { source in
                    var updated = source
                    if source.id == id { updated.pricePerKWh = newValue }
                    return updated
                }
            }
        )
    }

    /// Switching from simple to advanced needs two named sources to exist.
    /// The current blended rate seeds both, so toggling modes never changes the
    /// result until the user actually edits something.
    private func ensureAdvancedSources() {
        let existing = draft.energyPrices.chargingSources
        guard !existing.contains(where: { $0.id == "home" }) else { return }
        let seed = draft.energyPrices.blendedElectricityPricePerKWh
        draft.energyPrices.chargingSources = [
            .init(id: "home", name: "Home charging", pricePerKWh: seed, share: 0.8),
            .init(id: "public", name: "Public charging", pricePerKWh: seed, share: 0.2),
        ]
    }
}
