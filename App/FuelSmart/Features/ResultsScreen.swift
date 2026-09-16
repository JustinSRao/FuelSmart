import SwiftUI
import SwiftData
import FuelSmartCore

/// The signature screen.
///
/// Vehicle A is grey and vehicle B is accent, everywhere. Nothing is coloured to
/// praise a powertrain, and the headline states a cost difference under stated
/// assumptions rather than recommending a purchase.
struct ResultsScreen: View {

    let scenario: ComparisonScenario
    let dataSources: [DataSourceMetadata]
    /// Present when the result came from a live draft, which lets the horizon and
    /// ownership toggles write back to it.
    var draft: ComparisonDraft?

    @Environment(AppModel.self) private var model
    @Environment(\.fsTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.fsIsWideLayout) private var isWideLayout

    @State private var horizon: OwnershipHorizon
    @State private var includeOwnershipCosts: Bool
    @State private var scrubMonth: Int?
    @State private var showingSave = false
    @State private var showingShare = false
    @State private var saveName = ""
    @State private var savedMessage: String?

    private let engine = ScenarioCalculator()

    init(scenario: ComparisonScenario, dataSources: [DataSourceMetadata], draft: ComparisonDraft? = nil) {
        self.scenario = scenario
        self.dataSources = dataSources
        self.draft = draft
        _horizon = State(initialValue: scenario.horizon)
        _includeOwnershipCosts = State(initialValue: scenario.includesOwnershipCosts)
    }

    /// The scenario actually evaluated, reflecting the on-screen controls.
    ///
    /// Recomputed from the immutable input each time rather than mutated in
    /// place, so toggling ownership costs off and on cannot lose the user's
    /// figures.
    private var activeScenario: ComparisonScenario {
        var updated = scenario
        updated.horizon = horizon
        if !includeOwnershipCosts {
            updated.sideA.recurringCosts = .empty
            updated.sideB.recurringCosts = .empty
        }
        return updated
    }

    private var result: ComparisonResult {
        engine.evaluate(activeScenario, dataSources: dataSources)
    }

    private var formatter: ValueFormatter { ValueFormatter(region: scenario.region) }
    private var narrator: ResultNarrator { ResultNarrator(region: scenario.region) }

    /// True when the user actually entered any recurring cost, which decides
    /// whether the ownership toggle is meaningful at all.
    private var hasOwnershipData: Bool {
        scenario.sideA.recurringCosts.isEnabled || scenario.sideB.recurringCosts.isEnabled
    }

    var body: some View {
        let result = self.result

        ScrollView {
            Group {
                if isWideLayout {
                    wideLayout(result)
                } else {
                    compactLayout(result)
                }
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 32)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("Comparison")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { beginSave(result) } label: { Image(systemName: "bookmark") }
                    .accessibilityLabel("Save comparison")
                Button { showingShare = true } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share comparison")
            }
        }
        .sheet(isPresented: $showingSave) { saveSheet(result) }
        .sheet(isPresented: $showingShare) {
            NavigationStack {
                ShareScreen(result: result)
            }
            .fsTheme(theme)
        }
        .overlay(alignment: .bottom) { savedToast }
    }

    // MARK: - Layouts

    /// iPhone reads results top to bottom.
    private func compactLayout(_ result: ComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            vehicleHeader(result)
            horizonPicker
            chartCard(result)
            breakEvenCard(result)
            headlineCard(result)
            ownershipToggle
            navigationLinks(result)
            assumptionsFooter(result)
        }
    }

    /// On a larger canvas the two vehicles become true columns, the chart spans
    /// both, and assumptions move into a persistent inspector.
    private func wideLayout(_ result: ComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            vehicleHeader(result)
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 14) {
                    chartCard(result)
                    headlineCard(result)
                }
                VStack(spacing: 14) {
                    horizonPicker
                    breakEvenCard(result)
                    ownershipToggle
                    navigationLinks(result)
                }
                .frame(width: 320)
            }
            assumptionsFooter(result)
        }
    }

    // MARK: - Sections

    private func vehicleHeader(_ result: ComparisonResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            vehicleColumn(result.sideA, total: result.totalA, isAccented: false)
            Text("VS")
                .font(FSFont.label)
                .foregroundStyle(theme.tertiaryText)
                .padding(.top, 24)
            vehicleColumn(result.sideB, total: result.totalB, isAccented: true)
        }
    }

    private func vehicleColumn(_ side: SideResult, total: Double, isAccented: Bool) -> some View {
        FSCard(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                FSSeriesSwatch(isAccented: isAccented)
                Text(side.vehicle.displayName)
                    .font(FSFont.bodyMedium)
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                Text(subtitle(for: side.vehicle))
                    .font(FSFont.footnote)
                    .foregroundStyle(isAccented ? theme.accentMuted : theme.tertiaryText)
                    .lineLimit(2)
                Text(formatter.currency(total))
                    .font(FSFont.figureMedium)
                    .foregroundStyle(isAccented ? theme.accentText : theme.text)
                    .padding(.top, 4)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Nocturne.Radius.large, style: .continuous)
                .strokeBorder(isAccented ? theme.accentBorder : .clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side.vehicle.fullDisplayName), \(formatter.currency(total)) over \(Int(horizon.years)) years")
    }

    private func subtitle(for vehicle: Vehicle) -> String {
        [vehicle.configuration, formatter.consumption(for: vehicle)]
            .compactMap { $0 }
            .filter { $0 != "—" }
            .joined(separator: " · ")
    }

    private var horizonPicker: some View {
        FSSegmented(
            options: OwnershipHorizon.presets.map { ($0, "\(Int($0.years)) yr") },
            selection: Binding(
                get: { horizon },
                set: { newValue in
                    horizon = newValue
                    scrubMonth = nil
                    draft?.horizon = newValue
                }
            ),
            accessibilityPrefix: "Ownership horizon "
        )
    }

    private func chartCard(_ result: ComparisonResult) -> some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    FSSectionLabel("Cumulative cost")
                    Spacer()
                    Text(result.assumptions.costLabel)
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.tertiaryText)
                }
                CumulativeCostChart(
                    model: CumulativeCostChartModel(result: result),
                    breakEven: result.breakEven,
                    formatter: formatter,
                    scrubMonth: $scrubMonth
                )
            }
        }
    }

    private func breakEvenCard(_ result: ComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FSInsightCard(
                kind: result.breakEven.status == .breakEvenOccurs ? .finding : .caveat,
                label: "Break-even",
                message: result.breakEven.explanation,
                systemImage: breakEvenIcon(result.breakEven.status)
            )

            if result.breakEven.status == .breakEvenOccurs {
                HStack(spacing: 8) {
                    FSDataTile(
                        label: "Time",
                        value: result.breakEven.durationDescription ?? "—"
                    )
                    FSDataTile(
                        label: "Distance",
                        value: result.breakEven.kilometres.map(formatter.approximateDistance) ?? "—"
                    )
                    FSDataTile(
                        label: "Date",
                        value: result.breakEven.estimatedDate.map(formatter.monthAndYear) ?? "—"
                    )
                }
            }

            // The energy-only view, always available, so the core economics can
            // be read apart from softer assumptions.
            if result.assumptions.includesOwnershipCosts,
               result.energyOnlyBreakEven.status != result.breakEven.status {
                FSInsightCard(
                    kind: .caveat,
                    label: "Purchase + energy only",
                    message: result.energyOnlyBreakEven.explanation,
                    systemImage: "bolt"
                )
            }
        }
    }

    private func breakEvenIcon(_ status: BreakEvenStatus) -> String {
        switch status {
        case .breakEvenOccurs: "chart.line.uptrend.xyaxis"
        case .identical: "equal"
        case .insufficientData: "questionmark.circle"
        case .vehicleAAlwaysAhead, .vehicleBAlwaysAhead, .noCrossingWithinHorizon: "arrow.left.and.right"
        }
    }

    private func headlineCard(_ result: ComparisonResult) -> some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                FSSectionLabel("Over \(Int(horizon.years)) years · \(formatter.distance(result.assumptions.annualKilometres))/year")
                Text(narrator.headline(for: result))
                    .font(FSFont.title)
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                FSComparisonRow(
                    label: "Energy per 100 \(formatter.distanceUnit)",
                    nameA: result.sideA.vehicle.shortDisplayName,
                    nameB: result.sideB.vehicle.shortDisplayName,
                    valueA: result.sideA.energy.totalCostPer100Km,
                    valueB: result.sideB.energy.totalCostPer100Km,
                    format: { formatter.rate($0) }
                )
            }
        }
    }

    @ViewBuilder
    private var ownershipToggle: some View {
        if hasOwnershipData {
            FSCard(padding: 13) {
                FSToggleRow(
                    title: includeOwnershipCosts ? "Estimated ownership cost" : "Purchase + energy",
                    caption: "Include the insurance, maintenance and registration you entered.",
                    isOn: $includeOwnershipCosts
                )
            }
        } else {
            FSCard(padding: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Purchase + energy")
                            .font(FSFont.body)
                            .foregroundStyle(theme.text)
                        Text("Add insurance, maintenance or registration to widen this.")
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.tertiaryText)
                    }
                    Spacer()
                }
            }
        }
    }

    private func navigationLinks(_ result: ComparisonResult) -> some View {
        VStack(spacing: 10) {
            NavigationLink {
                CostDetailScreen(result: result)
            } label: {
                linkRow(title: "Cost detail", subtitle: "Energy, upfront and where the money goes", icon: "list.bullet.rectangle")
            }
            .buttonStyle(.plain)

            NavigationLink {
                ThresholdToolsScreen(scenario: activeScenario)
            } label: {
                linkRow(title: "What would change this", subtitle: "Break-even gas price, distance and purchase price", icon: "arrow.triangle.swap")
            }
            .buttonStyle(.plain)

            NavigationLink {
                ScenarioLabScreen(scenario: activeScenario, dataSources: dataSources)
            } label: {
                linkRow(title: "Scenario Lab", subtitle: "Drag any assumption and watch the curves move", icon: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
        }
    }

    private func linkRow(title: String, subtitle: String, icon: String) -> some View {
        FSCard(padding: 13) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(theme.accentMuted)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(FSFont.body).foregroundStyle(theme.text)
                    Text(subtitle).font(FSFont.footnote).foregroundStyle(theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(theme.tertiaryText)
            }
        }
    }

    private func assumptionsFooter(_ result: ComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FSSectionLabel("Assumptions")
            Text(narrator.assumptionsLine(for: result))
                .font(FSFont.footnote)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(ResultNarrator.shortDisclaimer)
                .font(FSFont.footnote)
                .foregroundStyle(theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let source = result.dataSources.first {
                Text("Efficiency data: \(source.publisher), \(source.dataset).")
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Saving

    private func beginSave(_ result: ComparisonResult) {
        saveName = draft?.name.isEmpty == false
            ? draft!.name
            : "\(result.sideA.vehicle.shortDisplayName) vs \(result.sideB.vehicle.shortDisplayName)"
        showingSave = true
    }

    private func saveSheet(_ result: ComparisonResult) -> some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Comparison name", text: $saveName)
                }
                Section {
                    Text("Saved comparisons stay on this device. FuelSmart has no account and no server.")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .navigationTitle("Save comparison")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingSave = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { performSave() }
                        .disabled(saveName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .fsTheme(theme)
        .presentationDetents([.medium])
    }

    private func performSave() {
        let saved = SavedComparison(
            id: draft?.editingSavedId ?? UUID(),
            name: saveName.trimmingCharacters(in: .whitespaces),
            scenario: activeScenario
        )

        // Update in place when editing, so re-saving does not create a duplicate.
        let id = saved.id
        let descriptor = FetchDescriptor<SavedComparisonEntity>(predicate: #Predicate { $0.id == id })
        do {
            if let existing = try context.fetch(descriptor).first {
                try existing.update(from: saved)
            } else {
                context.insert(try SavedComparisonEntity(saved: saved))
            }
            try context.save()
            draft?.editingSavedId = saved.id
            draft?.name = saved.name
            savedMessage = "Saved to this device"
        } catch {
            savedMessage = "Couldn't save: \(error.localizedDescription)"
        }
        showingSave = false
        dismissToastAfterDelay()
    }

    @ViewBuilder
    private var savedToast: some View {
        if let savedMessage {
            Text(savedMessage)
                .font(FSFont.footnote)
                .foregroundStyle(theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(theme.surface))
                .fsElevation(.medium, theme: theme)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private func dismissToastAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(FSMotion.valueChange) { savedMessage = nil }
        }
    }
}
