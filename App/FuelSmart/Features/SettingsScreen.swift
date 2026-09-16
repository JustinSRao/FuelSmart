import SwiftUI
import SwiftData
import FuelSmartCore

/// Defaults, appearance, data provenance and privacy.
struct SettingsScreen: View {

    @Environment(AppModel.self) private var model
    @Environment(\.fsTheme) private var theme
    @Environment(\.modelContext) private var context

    @State private var showingRegionChange = false
    @State private var pendingRegion: Region?

    private var settings: UserSettings { model.settings }
    private var formatter: ValueFormatter { model.formatter }

    var body: some View {
        Form {
            regionSection
            defaultsSection
            appearanceSection
            dataSection
            #if DEBUG
            debugSection
            #endif
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("Settings")
        .alert("Switch region?", isPresented: $showingRegionChange) {
            Button("Cancel", role: .cancel) { pendingRegion = nil }
            Button("Switch") { commitRegionChange() }
        } message: {
            Text("Units and currency change to that region's, and your price and distance defaults are replaced with values for it. Saved comparisons keep the region they were made in.")
        }
        .task { await model.loadManifest() }
    }

    // MARK: - Region

    private var regionSection: some View {
        Section("Region & units") {
            Picker("Region", selection: Binding(
                get: { settings.region },
                set: { newValue in
                    guard newValue != settings.region else { return }
                    pendingRegion = newValue
                    showingRegionChange = true
                }
            )) {
                Text("Canada").tag(Region.canada)
                Text("United States").tag(Region.unitedStates)
            }

            LabeledContent("Units") {
                Text(settings.region == .canada ? "km · L/100 km" : "miles · MPG")
                    .foregroundStyle(theme.secondaryText)
            }
            LabeledContent("Currency") {
                Text("\(settings.region.currencyCode) $")
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private func commitRegionChange() {
        guard let pendingRegion else { return }
        model.settingsStore.switchRegion(to: pendingRegion)
        self.pendingRegion = nil
    }

    // MARK: - Defaults

    private var defaultsSection: some View {
        Section {
            settingRow(
                "Gas price",
                value: formatter.fuelPrice(settings.gasolinePricePerLitre),
                binding: Binding(
                    get: { UnitConversionService.fuelPriceFromPerLitre(settings.gasolinePricePerLitre, region: settings.region) },
                    set: { model.settingsStore.update { s in
                        s.gasolinePricePerLitre = UnitConversionService.fuelPriceToPerLitre($0, region: s.region)
                    } }
                ),
                unit: settings.region == .canada ? "/ L" : "/ gal"
            )

            settingRow(
                "Diesel price",
                value: formatter.fuelPrice(settings.dieselPricePerLitre),
                binding: Binding(
                    get: { UnitConversionService.fuelPriceFromPerLitre(settings.dieselPricePerLitre, region: settings.region) },
                    set: { model.settingsStore.update { s in
                        s.dieselPricePerLitre = UnitConversionService.fuelPriceToPerLitre($0, region: s.region)
                    } }
                ),
                unit: settings.region == .canada ? "/ L" : "/ gal"
            )

            settingRow(
                "Electricity — home",
                value: formatter.electricityPrice(settings.homeElectricityPricePerKWh),
                binding: Binding(
                    get: { settings.homeElectricityPricePerKWh },
                    set: { value in model.settingsStore.update { $0.homeElectricityPricePerKWh = value } }
                ),
                unit: "/ kWh"
            )

            settingRow(
                "Electricity — public",
                value: formatter.electricityPrice(settings.publicElectricityPricePerKWh),
                binding: Binding(
                    get: { settings.publicElectricityPricePerKWh },
                    set: { value in model.settingsStore.update { $0.publicElectricityPricePerKWh = value } }
                ),
                unit: "/ kWh"
            )

            settingRow(
                "Annual distance",
                value: formatter.distance(settings.annualKilometres),
                binding: Binding(
                    get: { UnitConversionService.kilometresToRegionDistance(settings.annualKilometres, region: settings.region) },
                    set: { value in model.settingsStore.update { s in
                        s.annualKilometres = UnitConversionService.distanceToKilometres(value, region: s.region)
                    } }
                ),
                unit: formatter.distanceUnit,
                fractionDigits: 0...0
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("City / highway")
                    Spacer()
                    Text(formatter.split(settings.cityHighwaySplit, primaryLabel: "city", secondaryLabel: "highway"))
                        .foregroundStyle(theme.secondaryText)
                }
                FSSplitSlider(
                    split: Binding(
                        get: { settings.cityHighwaySplit },
                        set: { value in model.settingsStore.update { $0.cityHighwaySplit = value } }
                    ),
                    primaryLabel: "City",
                    secondaryLabel: "Highway",
                    height: 30
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Home / public charging")
                    Spacer()
                    Text(formatter.split(settings.publicChargingShare, primaryLabel: "public", secondaryLabel: "home"))
                        .foregroundStyle(theme.secondaryText)
                }
                FSSplitSlider(
                    split: Binding(
                        get: { Split(primary: settings.publicChargingShare.secondary) },
                        set: { value in
                            model.settingsStore.update { $0.publicChargingShare = Split(primary: value.secondary) }
                        }
                    ),
                    primaryLabel: "Home",
                    secondaryLabel: "Public",
                    height: 30
                )
            }
        } header: {
            Text("My defaults")
        } footer: {
            Text("These pre-fill every new comparison. You can change any of them per comparison without affecting these.")
        }
    }

    private func settingRow(
        _ title: String,
        value: String,
        binding: Binding<Double>,
        unit: String,
        fractionDigits: ClosedRange<Int> = 0...3
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: binding, format: .number.precision(.fractionLength(fractionDigits)))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .monospacedDigit()
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(unit)
                .font(FSFont.footnote)
                .foregroundStyle(theme.tertiaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: Binding(
                get: { settings.theme },
                set: { value in model.settingsStore.update { $0.theme = value } }
            )) {
                ForEach(UserSettings.ThemePreference.allCases) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Increase contrast", isOn: Binding(
                get: { settings.increaseContrast },
                set: { value in model.settingsStore.update { $0.increaseContrast = value } }
            ))
        }
    }

    // MARK: - Data and privacy

    private var dataSection: some View {
        Section {
            NavigationLink { DataSourcesScreen() } label: {
                LabeledContent("Vehicle data sources") {
                    Text("NRCan · EPA").foregroundStyle(theme.secondaryText)
                }
            }
            LabeledContent("Dataset version") {
                Text(model.manifest?.datasetVersion ?? "—")
                    .foregroundStyle(theme.secondaryText)
            }
            NavigationLink { PrivacyScreen() } label: {
                LabeledContent("Privacy") {
                    Text("On this device").foregroundStyle(theme.secondaryText)
                }
            }
            NavigationLink { AboutScreen() } label: { Text("About FuelSmart") }
        } header: {
            Text("Data & privacy")
        } footer: {
            Text("Efficiency data © Natural Resources Canada and the U.S. Department of Energy, used under their open data licences. FuelSmart has no account, no analytics and no server.")
        }
    }

    // MARK: - Debug

    #if DEBUG
    /// Development-only tools. Compiled out of release builds entirely, so they
    /// can never appear in shipped UI.
    private var debugSection: some View {
        Section("Developer") {
            Button("Load sample comparison") { insertSample() }
            Button("Reset onboarding") {
                model.settingsStore.update { $0.hasCompletedOnboarding = false }
            }
            Button("Reset defaults") { model.settingsStore.resetToDefaults() }
            Button("Delete all saved comparisons", role: .destructive) { deleteAllSaved() }
            if let manifest = model.manifest {
                ForEach(manifest.countries) { country in
                    LabeledContent(country.country) {
                        Text("\(country.recordCount) records")
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            if let error = model.datasetLoadError {
                Text(error).font(FSFont.footnote).foregroundStyle(theme.warning)
            }
        }
    }

    private func insertSample() {
        let scenario = DebugFixtures.sampleScenario(region: settings.region)
        let saved = SavedComparison(name: "Sample comparison", scenario: scenario)
        if let entity = try? SavedComparisonEntity(saved: saved) {
            context.insert(entity)
            try? context.save()
        }
    }

    private func deleteAllSaved() {
        try? context.delete(model: SavedComparisonEntity.self)
        try? context.save()
    }
    #endif
}

// MARK: - Data sources

/// Required attribution, plus what the app actually ships.
///
/// These notices are a licence condition of the underlying data and must not be
/// removed during UI polish.
struct DataSourcesScreen: View {

    @Environment(AppModel.self) private var model
    @Environment(\.fsTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let manifest = model.manifest {
                    ForEach(manifest.countries) { country in
                        countryCard(country, manifest: manifest)
                    }
                    FSCard {
                        VStack(alignment: .leading, spacing: 8) {
                            FSSectionLabel("VIN decoding")
                            Text("U.S. National Highway Traffic Safety Administration — vPIC API. A work of the U.S. Government. Used only when you look up a VIN, and never required.")
                                .font(FSFont.footnote)
                                .foregroundStyle(theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(manifest.disclaimer)
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let error = model.datasetLoadError {
                    FSNoticeCard(
                        severity: .warning,
                        systemImage: "exclamationmark.triangle",
                        title: "Dataset information unavailable",
                        message: error
                    )
                } else {
                    ProgressView()
                }
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("Data sources")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func countryCard(_ country: DatasetManifest.CountrySummary, manifest: DatasetManifest) -> some View {
        FSCard {
            VStack(alignment: .leading, spacing: 11) {
                FSSectionLabel(country.country == "CA" ? "Canada" : "United States")

                Text("\(country.recordCount.formatted()) vehicle configurations")
                    .font(FSFont.bodyMedium)
                    .foregroundStyle(theme.text)

                if let range = country.yearRange, range.count == 2 {
                    Text("Model years \(range[0])–\(range[1])")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.secondaryText)
                }

                ForEach(country.sources) { source in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.dataset)
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.text)
                        Text(source.publisher)
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.secondaryText)
                        HStack(spacing: 10) {
                            if let url = URL(string: source.licenceUrl) {
                                Link(source.licence, destination: url)
                                    .font(FSFont.footnote)
                                    .foregroundStyle(theme.accentMuted)
                            }
                            if let url = URL(string: source.landingPage) {
                                Link("Dataset", destination: url)
                                    .font(FSFont.footnote)
                                    .foregroundStyle(theme.accentMuted)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let attribution = manifest.attribution[country.country] {
                    Divider().overlay(theme.divider)
                    Text(attribution)
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Privacy

struct PrivacyScreen: View {
    @Environment(\.fsTheme) private var theme

    private let guarantees = [
        ("person.crop.circle.badge.xmark", "No account", "FuelSmart has no sign-in and no user profile."),
        ("icloud.slash", "No server", "There is no FuelSmart backend. Nothing is uploaded."),
        ("chart.bar.xaxis", "No analytics", "No tracking SDKs, no behavioural advertising, no telemetry."),
        ("iphone", "Stored on device", "Comparisons, settings and cached VIN results stay on this device."),
    ]

    private let networkUses = [
        ("VIN lookup", "Sends only the VIN you type, to the U.S. government's free vehicle-identification service. Optional — you can always choose a vehicle by hand."),
        ("Dataset update", "Downloads a published government dataset. Optional — the app ships with a complete database."),
        ("Sharing and export", "Only when you deliberately share an image, a PDF or a file, to a destination you choose."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your comparisons are yours")
                    .font(FSFont.title)
                    .foregroundStyle(theme.text)
                    .padding(.top, 4)

                FSCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(guarantees.indices, id: \.self) { index in
                            let (icon, title, detail) = guarantees[index]
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: icon)
                                    .foregroundStyle(theme.accentMuted)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title).font(FSFont.body).foregroundStyle(theme.text)
                                    Text(detail)
                                        .font(FSFont.footnote)
                                        .foregroundStyle(theme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                FSCard {
                    VStack(alignment: .leading, spacing: 11) {
                        FSSectionLabel("When FuelSmart uses the network")
                        ForEach(networkUses.indices, id: \.self) { index in
                            let (title, detail) = networkUses[index]
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).font(FSFont.body).foregroundStyle(theme.text)
                                Text(detail)
                                    .font(FSFont.footnote)
                                    .foregroundStyle(theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }
                        Divider().overlay(theme.divider)
                        Text("No vehicle-comparison information leaves your device in any of these cases, except the file or image you choose to share.")
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("Privacy")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - About

struct AboutScreen: View {
    @Environment(\.fsTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    BrandMark(size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FuelSmart").font(FSFont.title).foregroundStyle(theme.text)
                        Text("Version \(Bundle.main.appVersion ?? "1.0")")
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
                .padding(.top, 4)

                FSCard {
                    VStack(alignment: .leading, spacing: 10) {
                        FSSectionLabel("What FuelSmart does")
                        Text("FuelSmart compares what two vehicles will actually cost you — purchase price, fuel or electricity, financing, and the ownership costs you choose to include — and shows when, or whether, one becomes cheaper than the other.")
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("It stays neutral. It never assumes an electric vehicle is better, that gasoline is worse, or that a more efficient vehicle is automatically the better financial choice. It shows the mathematics and lets you decide.")
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                FSCard {
                    VStack(alignment: .leading, spacing: 10) {
                        FSSectionLabel("What it deliberately doesn't do")
                        ForEach(limitations.indices, id: \.self) { index in
                            let (title, detail) = limitations[index]
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).font(FSFont.body).foregroundStyle(theme.text)
                                Text(detail)
                                    .font(FSFont.footnote)
                                    .foregroundStyle(theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                FSCard {
                    VStack(alignment: .leading, spacing: 10) {
                        FSSectionLabel("Disclaimer")
                        Text("Calculations are estimates. Government efficiency ratings are standardized laboratory tests and may differ from real-world use. Prices and future energy costs change. Maintenance, insurance and depreciation assumptions vary widely. FuelSmart is an informational comparison tool and does not provide financial advice.")
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("About")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var limitations: [(String, String)] {
        [
            ("Supply vehicle prices", "There is no free authoritative source for what a car actually sells for, so FuelSmart asks you instead of guessing."),
            ("Forecast fuel or electricity prices", "No reliable free forecast exists, and a wrong one would be worse than none. Threshold tools show sensitivities, not predictions."),
            ("Model depreciation", "Resale value is your assumption, shown as yours."),
            ("Recommend a purchase", "It reports costs under stated assumptions. The decision is yours."),
        ]
    }
}

#if DEBUG
/// Fixtures for the DEBUG-only developer tools.
enum DebugFixtures {
    static func sampleScenario(region: Region) -> ComparisonScenario {
        let hybrid = Vehicle(
            id: "debug-hybrid", region: region, year: 2026, make: "Toyota", model: "Camry",
            configuration: "Hybrid LE", powertrain: .hybrid,
            efficiency: VehicleEfficiency(cityLPer100Km: 4.9, highwayLPer100Km: 5.1, combinedLPer100Km: 5.0),
            isUserDefined: true
        )
        let electric = Vehicle(
            id: "debug-bev", region: region, year: 2026, make: "Tesla", model: "Model 3",
            configuration: "RWD", powertrain: .bev,
            efficiency: VehicleEfficiency(
                cityKwhPer100Km: 13.9, highwayKwhPer100Km: 16.2, combinedKwhPer100Km: 14.9,
                electricRangeKm: 584
            ),
            isUserDefined: true
        )
        return ComparisonScenario(
            mode: .buyVsBuy,
            region: region,
            sideA: ComparisonSide(
                vehicle: hybrid,
                acquisition: AcquisitionCost(purchasePrice: 41_000, dealerFees: 2_500)
            ),
            sideB: ComparisonSide(
                vehicle: electric,
                acquisition: AcquisitionCost(
                    purchasePrice: 49_990, dealerFees: 2_600,
                    rebate: 5_000, homeChargerInstallation: 1_200
                )
            ),
            driving: DrivingProfile(annualKilometres: 18_000),
            energyPrices: .homeAndPublic(
                gasolinePricePerLitre: 1.72, dieselPricePerLitre: 1.85,
                homePricePerKWh: 0.14, publicPricePerKWh: 0.52,
                publicShare: Split(primaryPercent: 20)
            )
        )
    }
}
#endif
