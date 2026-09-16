import SwiftUI
import Charts
import FuelSmartCore

/// Energy, upfront and the full category breakdown.
struct CostDetailScreen: View {

    let result: FuelSmartCore.ComparisonResult

    @Environment(\.fsTheme) private var theme

    private var formatter: ValueFormatter { ValueFormatter(region: result.scenario.region) }
    private var narrator: ResultNarrator { ResultNarrator(region: result.scenario.region) }
    private var horizonYears: Int { Int(result.scenario.horizon.years) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                heading
                energyCard
                upfrontCard
                breakdownCard
                milestonesCard
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("Cost detail")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            FSSectionLabel("Over \(horizonYears) years · \(formatter.distance(result.assumptions.annualKilometres))/year")
            Text(narrator.headline(for: result))
                .font(FSFont.title)
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: - Energy

    private var energyCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 13) {
                FSComparisonRow(
                    label: "Energy per 100 \(formatter.distanceUnit)",
                    nameA: result.sideA.vehicle.shortDisplayName,
                    nameB: result.sideB.vehicle.shortDisplayName,
                    valueA: result.sideA.energy.totalCostPer100Km,
                    valueB: result.sideB.energy.totalCostPer100Km,
                    format: { formatter.rate($0) }
                )

                threeColumnGrid(
                    rows: [
                        ("Month", result.sideA.energy.monthlyTotal, result.sideB.energy.monthlyTotal),
                        ("Year", result.sideA.energy.annualTotal, result.sideB.energy.annualTotal),
                        ("\(horizonYears) yr",
                         result.sideA.energy.annualTotal * Double(horizonYears),
                         result.sideB.energy.annualTotal * Double(horizonYears)),
                    ]
                )

                let saving = abs(result.sideA.energy.annualTotal - result.sideB.energy.annualTotal)
                let cheaper = result.sideA.energy.annualTotal < result.sideB.energy.annualTotal
                    ? result.sideA.vehicle.shortDisplayName
                    : result.sideB.vehicle.shortDisplayName
                if saving > 0.005 {
                    Text("Energy difference: the \(cheaper) costs \(formatter.currency(saving)) less per year to run.")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if result.sideA.energy.usedCombinedFallback || result.sideB.energy.usedCombinedFallback {
                    Label(
                        "One of these vehicles has no separate city and highway rating, so its combined figure was used.",
                        systemImage: "info.circle"
                    )
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func threeColumnGrid(rows: [(String, Double, Double)]) -> some View {
        HStack(spacing: 1) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.0.uppercased())
                        .font(FSFont.label)
                        .tracking(1)
                        .foregroundStyle(theme.tertiaryText)
                    Text(formatter.currency(row.1))
                        .font(FSFont.figureSmall)
                        .foregroundStyle(theme.text)
                    Text(formatter.currency(row.2))
                        .font(FSFont.figureSmall)
                        .foregroundStyle(theme.accentText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(theme.surface)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.0): \(result.sideA.vehicle.shortDisplayName) \(formatter.currency(row.1)), \(result.sideB.vehicle.shortDisplayName) \(formatter.currency(row.2))")
            }
        }
        .background(theme.divider)
        .clipShape(RoundedRectangle(cornerRadius: Nocturne.Radius.small, style: .continuous))
    }

    // MARK: - Upfront

    private var upfrontCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 11) {
                FSSectionLabel("Upfront")

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                    GridRow {
                        Text("")
                        Text(result.sideA.vehicle.shortDisplayName)
                            .font(FSFont.label)
                            .foregroundStyle(theme.tertiaryText)
                            .gridColumnAlignment(.trailing)
                        Text(result.sideB.vehicle.shortDisplayName)
                            .font(FSFont.label)
                            .foregroundStyle(theme.accentMuted)
                            .gridColumnAlignment(.trailing)
                    }

                    ForEach(upfrontRows.indices, id: \.self) { index in
                        let row = upfrontRows[index]
                        GridRow {
                            Text(row.label)
                                .font(FSFont.footnote)
                                .foregroundStyle(theme.secondaryText)
                            valueCell(row.a)
                            valueCell(row.b)
                        }
                    }
                }

                Divider().overlay(theme.divider)

                Grid(alignment: .leading, horizontalSpacing: 12) {
                    GridRow {
                        Text("Net acquisition")
                            .font(FSFont.body)
                            .foregroundStyle(theme.text)
                        Text(formatter.currency(result.sideA.netAcquisitionCost))
                            .font(FSFont.figureMedium)
                            .foregroundStyle(theme.text)
                            .gridColumnAlignment(.trailing)
                        Text(formatter.currency(result.sideB.netAcquisitionCost))
                            .font(FSFont.figureMedium)
                            .foregroundStyle(theme.accentText)
                            .gridColumnAlignment(.trailing)
                    }
                }

                Text(gapExplanation)
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func valueCell(_ value: Double?) -> some View {
        if let value, value != 0 {
            Text(formatter.currency(value))
                .font(FSFont.figureSmall)
                .foregroundStyle(theme.text)
                .gridColumnAlignment(.trailing)
        } else {
            Text("—")
                .font(FSFont.footnote)
                .foregroundStyle(theme.tertiaryText)
                .gridColumnAlignment(.trailing)
        }
    }

    /// Only line items that exist on at least one side, so a simple comparison
    /// does not show five rows of dashes.
    private var upfrontRows: [(label: String, a: Double?, b: Double?)] {
        let a = result.scenario.sideA.acquisition
        let b = result.scenario.sideB.acquisition
        let keptA = result.scenario.sideA.isAlreadyOwned

        var rows: [(String, Double?, Double?)] = []
        func add(_ label: String, _ valueA: Double, _ valueB: Double, negate: Bool = false) {
            guard valueA != 0 || valueB != 0 else { return }
            let sign: Double = negate ? -1 : 1
            rows.append((label, keptA ? nil : valueA * sign, valueB * sign))
        }

        add("Vehicle price", a.purchasePrice, b.purchasePrice)
        add("Taxes & fees",
            a.salesTax + a.dealerFees + a.otherOneTimeFees,
            b.salesTax + b.dealerFees + b.otherOneTimeFees)
        add("Rebates & incentives",
            a.rebate + a.governmentIncentive + a.manufacturerIncentive,
            b.rebate + b.governmentIncentive + b.manufacturerIncentive,
            negate: true)
        add("Trade-in", a.tradeInValue, b.tradeInValue, negate: true)
        add("Charger & electrical",
            a.homeChargerInstallation + a.electricalPanelUpgrade,
            b.homeChargerInstallation + b.electricalPanelUpgrade)
        add("Other one-time", a.otherOneTimeCost, b.otherOneTimeCost)
        return rows
    }

    private var gapExplanation: String {
        let difference = result.breakEven.initialDifference
        if result.scenario.sideA.isAlreadyOwned {
            return "You already own the \(result.sideA.vehicle.shortDisplayName), so nothing is charged against keeping it. Replacing it costs \(formatter.currency(abs(difference))) up front."
        }
        if abs(difference) < 0.005 {
            return "Both vehicles cost the same up front."
        }
        let behind = difference > 0 ? result.sideB.vehicle.shortDisplayName : result.sideA.vehicle.shortDisplayName
        return "The \(behind) starts \(formatter.currency(abs(difference))) behind. That gap is what the running-cost difference has to repay."
    }

    // MARK: - Breakdown

    private var breakdownCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                FSSectionLabel("Where the money goes · \(horizonYears) yr")

                stackedBar(for: result.sideA, total: result.totalA, isAccented: false)
                stackedBar(for: result.sideB, total: result.totalB, isAccented: true)

                legend
            }
        }
    }

    private func stackedBar(for side: SideResult, total: Double, isAccented: Bool) -> some View {
        let categories = presentCategories(for: side)
        let sum = max(categories.reduce(0) { $0 + $1.value }, .leastNonzeroMagnitude)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(side.vehicle.shortDisplayName)
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Text(formatter.currency(total))
                    .font(FSFont.figureSmall)
                    .foregroundStyle(isAccented ? theme.accentText : theme.text)
            }

            GeometryReader { proxy in
                HStack(spacing: 1) {
                    ForEach(categories.indices, id: \.self) { index in
                        let entry = categories[index]
                        Rectangle()
                            .fill(shade(for: entry.category, isAccented: isAccented))
                            .frame(width: max(proxy.size.width * (entry.value / sum) - 1, 0))
                    }
                }
            }
            .frame(height: 22)
            .clipShape(RoundedRectangle(cornerRadius: Nocturne.Radius.small, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel("\(side.vehicle.shortDisplayName) cost breakdown")
            .accessibilityValue(
                categories
                    .map { "\($0.category.displayName) \(formatter.currency($0.value))" }
                    .joined(separator: ", ")
            )
        }
    }

    /// Only categories with a non-zero total, so disabled ones do not render as
    /// invisible slivers.
    private func presentCategories(for side: SideResult) -> [(category: CostCategory, value: Double)] {
        let totals = side.categoryTotals(atMonth: result.horizonMonths)
        return CostCategory.allCases.compactMap { category in
            guard !category.isCredit, let value = totals[category], value > 0.005 else { return nil }
            return (category, value)
        }
    }

    /// Shades within one family rather than a rainbow: the series keeps its own
    /// identity and no category reads as a judgement.
    private func shade(for category: CostCategory, isAccented: Bool) -> Color {
        let ramp: [Color] = isAccented
            ? [Nocturne.Accent.a600, Nocturne.Accent.a500, Nocturne.Accent.a400, Nocturne.Accent.a300, Nocturne.Accent.a200]
            : [Nocturne.Neutral.n600, Nocturne.Neutral.n500, Nocturne.Neutral.n400, Nocturne.Neutral.n300, Nocturne.Neutral.n200]
        let index = CostCategory.allCases.firstIndex(of: category) ?? 0
        return ramp[index % ramp.count]
    }

    private var legend: some View {
        let categories = Set(presentCategories(for: result.sideA).map(\.category))
            .union(presentCategories(for: result.sideB).map(\.category))

        return FlexibleHStack(spacing: 12) {
            ForEach(CostCategory.allCases.filter { categories.contains($0) }, id: \.self) { category in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(shade(for: category, isAccented: false))
                        .frame(width: 9, height: 9)
                    Text(category.displayName)
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.tertiaryText)
                }
            }
        }
    }

    // MARK: - Milestones

    private var milestonesCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 11) {
                FSSectionLabel("Totals at each horizon")
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                    GridRow {
                        Text("")
                        Text(result.sideA.vehicle.shortDisplayName)
                            .font(FSFont.label).foregroundStyle(theme.tertiaryText)
                            .gridColumnAlignment(.trailing)
                        Text(result.sideB.vehicle.shortDisplayName)
                            .font(FSFont.label).foregroundStyle(theme.accentMuted)
                            .gridColumnAlignment(.trailing)
                    }
                    ForEach([3, 5, 8, 10], id: \.self) { years in
                        GridRow {
                            Text("\(years) years")
                                .font(FSFont.footnote)
                                .foregroundStyle(years == horizonYears ? theme.text : theme.secondaryText)
                            Text(formatter.currency(result.total(for: result.sideA, atYears: years)))
                                .font(FSFont.figureSmall)
                                .foregroundStyle(theme.text)
                                .gridColumnAlignment(.trailing)
                            Text(formatter.currency(result.total(for: result.sideB, atYears: years)))
                                .font(FSFont.figureSmall)
                                .foregroundStyle(theme.accentText)
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
                if result.assumptions.includesResale {
                    Text("Resale is subtracted only at your \(horizonYears)-year horizon, never spread across the other rows.")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A wrapping horizontal stack, for legends that must reflow at large Dynamic
/// Type sizes rather than clipping.
struct FlexibleHStack<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content }
            VStack(alignment: .leading, spacing: spacing / 2) { content }
        }
    }
}
