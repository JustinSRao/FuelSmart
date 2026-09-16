import SwiftUI
import FuelSmartCore

/// The hub of the compare flow.
///
/// The design presents inputs as four short screens; this is the spine that
/// holds them. Every card opens with the one field that matters and hides the
/// rest behind an advanced section, and defaults come from Settings, so a
/// returning user can tap straight through to the answer.
struct CompareScreen: View {

    var initialMode: ComparisonMode = .buyVsBuy
    var editing: SavedComparison?

    @Environment(AppModel.self) private var model
    @Environment(\.fsTheme) private var theme

    @State private var draft: ComparisonDraft?
    @State private var dataSources: [DataSourceMetadata] = []
    @State private var pickerTarget: ComparisonSideIdentifier?
    @State private var showingResults = false

    var body: some View {
        Group {
            if let draft {
                content(draft)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.background)
        .navigationTitle(editing == nil ? "New comparison" : "Edit comparison")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if draft == nil {
                draft = editing.map { ComparisonDraft(saved: $0, settings: model.settings) }
                    ?? ComparisonDraft(settings: model.settings, mode: initialMode)
            }
            dataSources = (try? await model.currentRepository.dataSources()) ?? []
        }
    }

    @ViewBuilder
    private func content(_ draft: ComparisonDraft) -> some View {
        @Bindable var draft = draft

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                modeSection(draft)
                vehicleSection(draft)
                if draft.isReadyToCompare {
                    drivingSummary(draft)
                    energySummary(draft)
                    issues(draft)
                }
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 100)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            resultsButton(draft)
        }
        .sheet(item: $pickerTarget) { side in
            NavigationStack {
                VehiclePickerScreen(region: draft.region) { vehicle in
                    draft.setVehicle(vehicle, for: side)
                    prefillIfPossible(draft, side: side, vehicle: vehicle)
                    pickerTarget = nil
                }
            }
            .fsTheme(theme)
        }
        .navigationDestination(isPresented: $showingResults) {
            if let scenario = draft.makeScenario() {
                ResultsScreen(scenario: scenario, dataSources: dataSources, draft: draft)
            }
        }
    }

    // MARK: - Mode

    private func modeSection(_ draft: ComparisonDraft) -> some View {
        @Bindable var draft = draft

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(ComparisonMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(FSMotion.valueChange) { draft.mode = mode }
                } label: {
                    modeCard(mode: mode, isSelected: draft.mode == mode, draft: draft)
                }
                .buttonStyle(.plain)
            }

            if draft.mode == .keepVsReplace {
                FSInsightCard(
                    kind: .caveat,
                    label: "Sunk cost",
                    message: "The money you already spent on your current car is never charged against it again. The replacement is charged its price minus your trade-in and any incentive.",
                    systemImage: "info.circle"
                )
            }
        }
    }

    private func modeCard(mode: ComparisonMode, isSelected: Bool, draft: ComparisonDraft) -> some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(mode.displayName)
                            .font(FSFont.headline)
                            .foregroundStyle(theme.text)
                        Text(description(for: mode))
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.secondaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? theme.accentText : theme.strongBorder)
                        .font(.title3)
                }

                FSInsetRow(padding: 10) {
                    HStack {
                        sideStub(label: mode == .keepVsReplace ? "KEEP" : "A",
                                 value: draft.vehicleA?.shortDisplayName ?? "Not chosen")
                        Spacer()
                        Text("VS").font(FSFont.label).foregroundStyle(theme.tertiaryText)
                        Spacer()
                        sideStub(label: mode == .keepVsReplace ? "REPLACE" : "B",
                                 value: draft.vehicleB?.shortDisplayName ?? "Not chosen",
                                 alignment: .trailing)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Nocturne.Radius.large, style: .continuous)
                .strokeBorder(isSelected ? theme.accent : .clear, lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func sideStub(label: String, value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label).font(FSFont.label).foregroundStyle(theme.tertiaryText)
            Text(value).font(FSFont.footnote).foregroundStyle(theme.secondaryText).lineLimit(1)
        }
    }

    private func description(for mode: ComparisonMode) -> String {
        switch mode {
        case .buyVsBuy:
            "Choosing between two vehicles you don't own yet. Both purchase prices count."
        case .keepVsReplace:
            "You already own one of them. What you paid for it is sunk — only what happens next counts."
        }
    }

    // MARK: - Vehicles

    private func vehicleSection(_ draft: ComparisonDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FSSectionLabel("Vehicles")
            ForEach([ComparisonSideIdentifier.a, .b], id: \.self) { side in
                vehicleCard(draft, side: side)
            }
        }
    }

    private func vehicleCard(_ draft: ComparisonDraft, side: ComparisonSideIdentifier) -> some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    FSSeriesSwatch(isAccented: side == .b)
                    Text(draft.label(for: side))
                        .font(FSFont.label)
                        .tracking(1.2)
                        .foregroundStyle(theme.tertiaryText)
                    Spacer()
                }

                if let vehicle = draft.vehicle(for: side) {
                    FSVehicleBadge(vehicle: vehicle, isAccented: side == .b, formatter: model.formatter)

                    HStack(spacing: 8) {
                        Button("Change") { pickerTarget = side }
                            .buttonStyle(FSSecondaryButtonStyle(height: 38))
                        NavigationLink {
                            CostInputScreen(draft: draft, side: side)
                        } label: {
                            Text(costSummary(draft, side: side))
                        }
                        .buttonStyle(FSSecondaryButtonStyle(height: 38))
                    }
                } else {
                    Button {
                        pickerTarget = side
                    } label: {
                        Label("Choose a vehicle", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(FSSecondaryButtonStyle())
                }
            }
        }
    }

    private func costSummary(_ draft: ComparisonDraft, side: ComparisonSideIdentifier) -> String {
        // In keep-vs-replace the kept vehicle has no acquisition cost at all, so
        // offering a price field for it would contradict the model.
        if draft.mode == .keepVsReplace && side == .a { return "Ownership costs" }
        let price = draft.acquisition(for: side).purchasePrice
        return price > 0 ? model.formatter.currency(price) : "Add price"
    }

    // MARK: - Shared inputs

    private func drivingSummary(_ draft: ComparisonDraft) -> some View {
        NavigationLink {
            DrivingProfileScreen(draft: draft)
        } label: {
            FSCard {
                summaryRow(
                    label: "Driving",
                    value: model.formatter.distance(draft.driving.annualKilometres) + " / year",
                    detail: model.formatter.split(
                        draft.driving.cityHighwaySplit,
                        primaryLabel: "city", secondaryLabel: "highway"
                    )
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func energySummary(_ draft: ComparisonDraft) -> some View {
        NavigationLink {
            EnergyPricesScreen(draft: draft)
        } label: {
            FSCard {
                summaryRow(
                    label: "Energy costs",
                    value: energyValue(draft),
                    detail: energyDetail(draft)
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func energyValue(_ draft: ComparisonDraft) -> String {
        var parts: [String] = []
        if usesFuel(draft) {
            parts.append(model.formatter.fuelPrice(draft.energyPrices.gasolinePricePerLitre))
        }
        if usesElectricity(draft) {
            parts.append(model.formatter.electricityPrice(draft.energyPrices.blendedElectricityPricePerKWh))
        }
        return parts.joined(separator: " · ")
    }

    private func energyDetail(_ draft: ComparisonDraft) -> String {
        usesElectricity(draft) ? "Blended home and public charging" : "Fuel price"
    }

    private func usesFuel(_ draft: ComparisonDraft) -> Bool {
        [draft.vehicleA, draft.vehicleB].compactMap { $0 }.contains { $0.powertrain.usesLiquidFuel }
    }

    private func usesElectricity(_ draft: ComparisonDraft) -> Bool {
        [draft.vehicleA, draft.vehicleB].compactMap { $0 }.contains { $0.powertrain.usesElectricity }
    }

    private func summaryRow(label: String, value: String, detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                FSSectionLabel(label)
                Text(value).font(FSFont.bodyMedium).foregroundStyle(theme.text)
                Text(detail).font(FSFont.footnote).foregroundStyle(theme.tertiaryText)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(theme.tertiaryText).font(.footnote)
        }
    }

    // MARK: - Validation and action

    @ViewBuilder
    private func issues(_ draft: ComparisonDraft) -> some View {
        let blocking = draft.blockingIssues
        let advisory = draft.validationIssues.filter { !$0.isBlocking }

        ForEach(blocking, id: \.id) { issue in
            FSNoticeCard(
                severity: .warning,
                systemImage: "exclamationmark.triangle",
                title: "Check this before comparing",
                message: issue.message
            )
        }
        ForEach(advisory, id: \.id) { issue in
            FSNoticeCard(
                severity: .info,
                systemImage: "info.circle",
                title: "Worth knowing",
                message: issue.message
            )
        }
    }

    private func resultsButton(_ draft: ComparisonDraft) -> some View {
        VStack(spacing: 0) {
            Button("See results") { showingResults = true }
                .buttonStyle(FSPrimaryButtonStyle())
                .disabled(!draft.isReadyToCompare || !draft.blockingIssues.isEmpty)
                .padding(.horizontal, Nocturne.Space.gutter)
                .padding(.vertical, 12)
                .frame(maxWidth: 720)
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    /// Pre-fill the things the dataset already knows, so the user types less.
    ///
    /// Never a price — FuelSmart does not know what a vehicle costs and will not
    /// guess. Only the PHEV electric-share estimate, which is derived from the
    /// official electric range and the user's own daily distance.
    private func prefillIfPossible(_ draft: ComparisonDraft, side: ComparisonSideIdentifier, vehicle: Vehicle) {
        guard vehicle.powertrain == .phev,
              let range = vehicle.efficiency.electricRangeKm,
              draft.driving.annualKilometres > 0 else { return }
        let daily = draft.driving.annualKilometres / 365.25
        if let estimate = EnergyCostCalculator.estimatePHEVElectricShare(
            dailyKilometres: daily, electricRangeKm: range, chargesPerWeek: 7
        ) {
            draft.setPhevShare(estimate, for: side)
        }
    }
}

