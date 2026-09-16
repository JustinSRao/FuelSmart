import SwiftUI
import Charts
import FuelSmartCore

/// Drag any assumption and watch both curves move.
///
/// Scenario Lab never overwrites the saved comparison. It holds its own copy of
/// the adjustable values, and "Apply these values" is the only way changes reach
/// the underlying scenario.
struct ScenarioLabScreen: View {

    let scenario: ComparisonScenario
    let dataSources: [DataSourceMetadata]

    @Environment(\.fsTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // The adjustable values, in the region's own units where the user sees them
    // and canonical units where the engine does.
    @State private var gasPrice: Double
    @State private var electricityPrice: Double
    @State private var annualDistance: Double
    @State private var priceA: Double
    @State private var priceB: Double
    @State private var publicShare: Double
    @State private var cityShare: Double
    @State private var realWorldAdjustment: Double
    @State private var horizon: OwnershipHorizon
    @State private var insuranceDelta: Double = 0

    @State private var showingSaveAsNew = false
    @State private var newName = ""

    private let engine = ScenarioCalculator()

    init(scenario: ComparisonScenario, dataSources: [DataSourceMetadata]) {
        self.scenario = scenario
        self.dataSources = dataSources
        _gasPrice = State(initialValue: scenario.energyPrices.gasolinePricePerLitre)
        _electricityPrice = State(initialValue: scenario.energyPrices.blendedElectricityPricePerKWh)
        _annualDistance = State(initialValue: scenario.driving.annualKilometres)
        _priceA = State(initialValue: scenario.sideA.acquisition.purchasePrice)
        _priceB = State(initialValue: scenario.sideB.acquisition.purchasePrice)
        _publicShare = State(initialValue: 1 - Self.homeShare(of: scenario.energyPrices))
        _cityShare = State(initialValue: scenario.driving.cityHighwaySplit.primary)
        _realWorldAdjustment = State(initialValue: scenario.driving.realWorldAdjustment)
        _horizon = State(initialValue: scenario.horizon)
    }

    private static func homeShare(of prices: EnergyPriceProfile) -> Double {
        let total = prices.chargingSources.reduce(0) { $0 + max($1.share, 0) }
        guard total > 0 else { return 1 }
        return (prices.chargingSources.first { $0.id == "home" }?.share ?? total) / total
    }

    private var formatter: ValueFormatter { ValueFormatter(region: scenario.region) }
    private var narrator: ResultNarrator { ResultNarrator(region: scenario.region) }

    /// The scenario as currently dialled in. Rebuilt from the original each
    /// time, so nothing drifts and Reset is exact.
    private var adjustedScenario: ComparisonScenario {
        var updated = scenario
        updated.horizon = horizon
        updated.driving.annualKilometres = annualDistance
        updated.driving.cityHighwaySplit = Split(primary: cityShare)
        updated.driving.realWorldAdjustment = realWorldAdjustment
        updated.energyPrices.gasolinePricePerLitre = gasPrice

        // Rebuild charging so the blended rate lands on the chosen value while
        // preserving the home/public price ratio the user set.
        let sources = scenario.energyPrices.chargingSources
        if sources.count >= 2 {
            let currentBlend = scenario.energyPrices.blendedElectricityPricePerKWh
            let factor = currentBlend > 0 ? electricityPrice / currentBlend : 1
            updated.energyPrices.chargingSources = sources.map { source in
                var copy = source
                copy.pricePerKWh = currentBlend > 0 ? source.pricePerKWh * factor : electricityPrice
                copy.share = source.id == "home" ? 1 - publicShare : publicShare
                return copy
            }
        } else {
            updated.energyPrices.chargingSources = [
                .init(id: "single", name: "Electricity", pricePerKWh: electricityPrice, share: 1)
            ]
        }

        updated.sideA.acquisition.purchasePrice = priceA
        updated.sideB.acquisition.purchasePrice = priceB

        if insuranceDelta != 0 {
            updated.sideB.recurringCosts.annualInsurance =
                (scenario.sideB.recurringCosts.annualInsurance ?? 0) + insuranceDelta
        }
        return updated
    }

    private var result: FuelSmartCore.ComparisonResult {
        engine.evaluate(adjustedScenario, dataSources: dataSources)
    }

    private var usesFuel: Bool {
        scenario.sideA.vehicle.powertrain.usesLiquidFuel || scenario.sideB.vehicle.powertrain.usesLiquidFuel
    }
    private var usesElectricity: Bool {
        scenario.sideA.vehicle.powertrain.usesElectricity || scenario.sideB.vehicle.powertrain.usesElectricity
    }

    var body: some View {
        let result = self.result

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                previewCard(result)
                slidersCard
                note
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("Scenario Lab")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Reset") { reset() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Save as a new comparison") {
                newName = "\(result.sideA.vehicle.shortDisplayName) vs \(result.sideB.vehicle.shortDisplayName) — scenario"
                showingSaveAsNew = true
            }
            .buttonStyle(FSSecondaryButtonStyle())
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.vertical, 10)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingSaveAsNew) { saveSheet }
    }

    // MARK: - Preview

    private func previewCard(_ result: FuelSmartCore.ComparisonResult) -> some View {
        FSCard(elevation: .medium) {
            VStack(alignment: .leading, spacing: 12) {
                miniChart(result)

                HStack(spacing: 8) {
                    FSDataTile(
                        label: "Break-even",
                        value: breakEvenSummary(result.breakEven)
                    )
                    FSDataTile(
                        label: "\(Int(horizon.years))-yr gap",
                        value: formatter.currency(result.costDifferenceAtHorizon),
                        isAccented: true
                    )
                }

                Text(narrator.headline(for: result))
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func breakEvenSummary(_ breakEven: BreakEvenResult) -> String {
        switch breakEven.status {
        case .breakEvenOccurs: breakEven.durationDescription ?? "—"
        case .identical: "Level"
        case .insufficientData: "—"
        case .vehicleAAlwaysAhead, .vehicleBAlwaysAhead, .noCrossingWithinHorizon: "None"
        }
    }

    /// A compact, non-interactive version of the main chart — same series
    /// colours, same rules, no scrubbing.
    private func miniChart(_ result: FuelSmartCore.ComparisonResult) -> some View {
        let model = CumulativeCostChartModel(result: result, sampleStride: 3)
        return Chart {
            ForEach(model.pointsA) { point in
                LineMark(
                    x: .value("Years", point.years),
                    y: .value("Cost", point.cost),
                    series: .value("Vehicle", model.nameA)
                )
                .foregroundStyle(theme.seriesA)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }
            ForEach(model.pointsB) { point in
                LineMark(
                    x: .value("Years", point.years),
                    y: .value("Cost", point.cost),
                    series: .value("Vehicle", model.nameB)
                )
                .foregroundStyle(theme.seriesB)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }
            if let month = model.breakEvenMonth, let cost = model.breakEvenCost {
                PointMark(x: .value("Break-even", Double(month) / 12), y: .value("Cost", cost))
                    .symbolSize(80)
                    .foregroundStyle(theme.isDark ? Nocturne.Accent.a300 : Nocturne.Accent.a700)
            }
        }
        .chartYScale(domain: 0...max(model.maxCost, 1))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 110)
        .accessibilityElement()
        .accessibilityLabel("Scenario preview chart")
        .accessibilityValue(model.accessibilitySummary(formatter: formatter, breakEven: result.breakEven))
    }

    // MARK: - Sliders

    private var slidersCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 16) {
                FSSegmented(
                    options: OwnershipHorizon.presets.map { ($0, "\(Int($0.years)) yr") },
                    selection: $horizon,
                    accessibilityPrefix: "Ownership horizon "
                )

                if usesFuel {
                    labelledSlider(
                        title: "Fuel price",
                        value: $gasPrice,
                        range: fuelRange,
                        step: 0.01,
                        display: formatter.fuelPrice(gasPrice)
                    )
                }

                if usesElectricity {
                    labelledSlider(
                        title: "Electricity price",
                        value: $electricityPrice,
                        range: 0.02...1.00,
                        step: 0.005,
                        display: formatter.electricityPrice(electricityPrice)
                    )

                    if scenario.energyPrices.chargingSources.count >= 2 {
                        labelledSlider(
                            title: "Public charging share",
                            value: $publicShare,
                            range: 0...1,
                            step: 0.05,
                            display: formatter.percent(publicShare)
                        )
                    }
                }

                labelledSlider(
                    title: "Annual distance",
                    value: $annualDistance,
                    range: distanceRange,
                    step: distanceStep,
                    display: formatter.distance(annualDistance)
                )

                labelledSlider(
                    title: "City share",
                    value: $cityShare,
                    range: 0...1,
                    step: 0.05,
                    display: formatter.percent(cityShare)
                )

                if !scenario.sideA.isAlreadyOwned {
                    labelledSlider(
                        title: "\(scenario.sideA.vehicle.shortDisplayName) price",
                        value: $priceA,
                        range: priceRange(around: scenario.sideA.acquisition.purchasePrice),
                        step: 500,
                        display: formatter.currency(priceA)
                    )
                }

                labelledSlider(
                    title: "\(scenario.sideB.vehicle.shortDisplayName) price",
                    value: $priceB,
                    range: priceRange(around: scenario.sideB.acquisition.purchasePrice),
                    step: 500,
                    display: formatter.currency(priceB)
                )

                labelledSlider(
                    title: "Real-world efficiency",
                    value: $realWorldAdjustment,
                    range: -0.10...0.40,
                    step: 0.01,
                    display: realWorldAdjustment == 0
                        ? "Official rating"
                        : "\(realWorldAdjustment > 0 ? "+" : "")\(Int((realWorldAdjustment * 100).rounded())) % consumption"
                )
            }
        }
    }

    private func labelledSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Text(display)
                    .font(FSFont.figureSmall)
                    .foregroundStyle(theme.text)
            }
            Slider(value: value, in: range, step: step)
                .tint(theme.accent)
                .accessibilityLabel(title)
                .accessibilityValue(display)
        }
    }

    // MARK: - Ranges

    /// Slider bounds are derived from the user's own figures rather than fixed,
    /// so a $90,000 vehicle is still adjustable and a $12,000 one is not lost at
    /// the far left of the track.
    private func priceRange(around value: Double) -> ClosedRange<Double> {
        let lower = max(value * 0.5, 1_000)
        let upper = max(value * 1.6, lower + 10_000)
        return lower...upper
    }

    private var fuelRange: ClosedRange<Double> {
        // Expressed per litre internally; the display converts.
        scenario.region == .canada ? 0.5...4.0 : 0.13...1.6
    }

    private var distanceRange: ClosedRange<Double> {
        scenario.region == .canada ? 2_000...60_000 : 3_218...96_560
    }

    private var distanceStep: Double {
        scenario.region == .canada ? 500 : 804.672
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scenario Lab never overwrites your comparison. Save it as a new one to keep these values.")
                .font(FSFont.footnote)
                .foregroundStyle(theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(ResultNarrator.shortDisclaimer)
                .font(FSFont.footnote)
                .foregroundStyle(theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func reset() {
        withAnimation(FSMotion.valueChange) {
            gasPrice = scenario.energyPrices.gasolinePricePerLitre
            electricityPrice = scenario.energyPrices.blendedElectricityPricePerKWh
            annualDistance = scenario.driving.annualKilometres
            priceA = scenario.sideA.acquisition.purchasePrice
            priceB = scenario.sideB.acquisition.purchasePrice
            publicShare = 1 - Self.homeShare(of: scenario.energyPrices)
            cityShare = scenario.driving.cityHighwaySplit.primary
            realWorldAdjustment = scenario.driving.realWorldAdjustment
            horizon = scenario.horizon
            insuranceDelta = 0
        }
    }

    private var saveSheet: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Scenario name", text: $newName) }
                Section {
                    Text("This saves the values you dialled in as a separate comparison. The original is untouched.")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .navigationTitle("Save scenario")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingSaveAsNew = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAsNew() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .fsTheme(theme)
        .presentationDetents([.medium])
    }

    private func saveAsNew() {
        let saved = SavedComparison(
            name: newName.trimmingCharacters(in: .whitespaces),
            scenario: adjustedScenario
        )
        if let entity = try? SavedComparisonEntity(saved: saved) {
            context.insert(entity)
            try? context.save()
        }
        showingSaveAsNew = false
        dismiss()
    }
}
