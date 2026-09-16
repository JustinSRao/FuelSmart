import SwiftUI
import Charts
import FuelSmartCore

/// The data a cumulative-cost chart needs, derived once from a result.
///
/// Deliberately separate from the view: the chart's *calculations* — sampling,
/// domains, scrub resolution, the accessibility sentence — live here and are
/// plain values that can be tested without rendering anything. The view below
/// only draws what this produces.
struct CumulativeCostChartModel {

    struct Point: Identifiable, Hashable {
        let month: Int
        let cost: Double
        let seriesName: String
        let isAccented: Bool
        var id: String { "\(seriesName)-\(month)" }
        var years: Double { Double(month) / 12 }
    }

    let pointsA: [Point]
    let pointsB: [Point]
    let nameA: String
    let nameB: String
    let horizonMonths: Int
    let maxMonth: Int
    let maxCost: Double
    let breakEvenMonth: Int?
    let breakEvenCost: Double?

    private let resultA: SideResult
    private let resultB: SideResult
    private let annualKilometres: Double

    init(result: ComparisonResult, sampleStride: Int = 1) {
        let months = min(result.sideA.cumulativePoints.count, result.sideB.cumulativePoints.count) - 1
        self.maxMonth = max(months, 1)
        self.horizonMonths = min(result.horizonMonths, maxMonth)
        self.nameA = result.sideA.vehicle.shortDisplayName
        self.nameB = result.sideB.vehicle.shortDisplayName
        self.resultA = result.sideA
        self.resultB = result.sideB
        self.annualKilometres = result.scenario.driving.annualKilometres

        // Sampling keeps the chart light without changing its shape: the curves
        // are piecewise linear in month, so intermediate points add nothing
        // visible. The horizon and any crossing are always included so neither
        // marker can land between samples.
        var indices = Set(stride(from: 0, through: maxMonth, by: max(sampleStride, 1)))
        indices.insert(maxMonth)
        indices.insert(horizonMonths)
        if let crossing = result.breakEven.month { indices.insert(crossing) }
        let sampled = indices.sorted()

        self.pointsA = sampled.map {
            Point(month: $0, cost: result.sideA.cost(atMonth: $0), seriesName: nameA, isAccented: false)
        }
        self.pointsB = sampled.map {
            Point(month: $0, cost: result.sideB.cost(atMonth: $0), seriesName: nameB, isAccented: true)
        }
        self.maxCost = max(
            result.sideA.cost(atMonth: maxMonth),
            result.sideB.cost(atMonth: maxMonth)
        ) * 1.06

        self.breakEvenMonth = result.breakEven.month
        self.breakEvenCost = result.breakEven.month.map {
            (result.sideA.cost(atMonth: $0) + result.sideB.cost(atMonth: $0)) / 2
        }
    }

    var allPoints: [Point] { pointsA + pointsB }

    func costA(atMonth month: Int) -> Double { resultA.cost(atMonth: month) }
    func costB(atMonth month: Int) -> Double { resultB.cost(atMonth: month) }
    func kilometres(atMonth month: Int) -> Double { annualKilometres * Double(month) / 12 }

    /// Clamp a proposed scrub month into the plotted range.
    func clampedMonth(_ month: Int) -> Int { min(max(month, 0), maxMonth) }

    /// The single sentence VoiceOver reads for the whole chart.
    ///
    /// The chart is one accessibility element rather than hundreds of data
    /// points, because a per-point rotor over 240 values is unusable.
    func accessibilitySummary(formatter: ValueFormatter, breakEven: BreakEvenResult) -> String {
        let horizonYears = horizonMonths / 12
        var sentence = "Cumulative cost, two series. "
        sentence += "\(nameA) \(formatter.currency(costA(atMonth: horizonMonths))) at \(horizonYears) years. "
        sentence += "\(nameB) \(formatter.currency(costB(atMonth: horizonMonths))). "
        if let month = breakEven.month, let description = breakEven.durationDescription {
            sentence += "Crossover at \(description), \(formatter.approximateDistance(kilometres(atMonth: month)))."
        } else {
            sentence += breakEven.explanation
        }
        return sentence
    }
}

/// The interactive cumulative-cost chart.
///
/// Vehicle A is grey and vehicle B is accent, everywhere, always. Series are
/// distinguished by stroke weight and label as well as colour, never by colour
/// alone.
struct CumulativeCostChart: View {

    let model: CumulativeCostChartModel
    let breakEven: BreakEvenResult
    let formatter: ValueFormatter
    /// Nil means "no scrub"; the readout then shows the horizon.
    @Binding var scrubMonth: Int?

    @Environment(\.fsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var readoutMonth: Int { scrubMonth ?? model.horizonMonths }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chart
            readout
        }
    }

    private var chart: some View {
        Chart {
            // Area under the accent curve, a faint tint that helps separate the
            // two lines without introducing a second hue.
            ForEach(model.pointsB) { point in
                AreaMark(
                    x: .value("Month", point.years),
                    y: .value("Cost", point.cost)
                )
                .foregroundStyle(theme.accent.opacity(0.13))
            }

            ForEach(model.pointsA) { point in
                LineMark(
                    x: .value("Month", point.years),
                    y: .value("Cost", point.cost),
                    series: .value("Vehicle", model.nameA)
                )
                .foregroundStyle(theme.seriesA)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }

            ForEach(model.pointsB) { point in
                LineMark(
                    x: .value("Month", point.years),
                    y: .value("Cost", point.cost),
                    series: .value("Vehicle", model.nameB)
                )
                .foregroundStyle(theme.seriesB)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }

            // The chosen ownership horizon.
            RuleMark(x: .value("Horizon", Double(model.horizonMonths) / 12))
                .foregroundStyle(theme.strongBorder)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))

            // Break-even, the one moment the product exists to find.
            if let month = model.breakEvenMonth, let cost = model.breakEvenCost {
                PointMark(
                    x: .value("Break-even", Double(month) / 12),
                    y: .value("Cost", cost)
                )
                .symbolSize(reduceMotion ? 90 : 130)
                .foregroundStyle(theme.isDark ? Nocturne.Accent.a300 : Nocturne.Accent.a700)
            }

            // Scrub position.
            if let scrubMonth {
                RuleMark(x: .value("Scrub", Double(scrubMonth) / 12))
                    .foregroundStyle(theme.text.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                PointMark(
                    x: .value("Scrub", Double(scrubMonth) / 12),
                    y: .value("Cost", model.costA(atMonth: scrubMonth))
                )
                .symbolSize(60)
                .foregroundStyle(theme.seriesAEmphasis)

                PointMark(
                    x: .value("Scrub", Double(scrubMonth) / 12),
                    y: .value("Cost", model.costB(atMonth: scrubMonth))
                )
                .symbolSize(60)
                .foregroundStyle(theme.seriesB)
            }
        }
        .chartYScale(domain: 0...max(model.maxCost, 1))
        .chartXScale(domain: 0...(Double(model.maxMonth) / 12))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(theme.gridLine)
                AxisValueLabel {
                    if let years = value.as(Double.self) {
                        Text("\(Int(years)) yr")
                            .font(FSFont.label)
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(theme.gridLine)
                AxisValueLabel {
                    if let cost = value.as(Double.self) {
                        Text(compactCurrency(cost))
                            .font(FSFont.label)
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
            }
        }
        .frame(height: 200)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geometry[plotFrame].origin
                                let x = value.location.x - origin.x
                                guard let years: Double = proxy.value(atX: x) else { return }
                                scrubMonth = model.clampedMonth(Int((years * 12).rounded()))
                            }
                            // Release snaps back to the horizon, so the screen
                            // always returns to the figure the user chose.
                            .onEnded { _ in scrubMonth = nil }
                    )
            }
        }
        // One accessibility element, with an adjustable action standing in for
        // the drag gesture, which VoiceOver cannot perform.
        .accessibilityElement()
        .accessibilityLabel("Cumulative cost chart")
        .accessibilityValue(model.accessibilitySummary(formatter: formatter, breakEven: breakEven))
        .accessibilityAdjustableAction { direction in
            let current = readoutMonth
            switch direction {
            case .increment: scrubMonth = model.clampedMonth(current + 6)
            case .decrement: scrubMonth = model.clampedMonth(current - 6)
            @unknown default: break
            }
        }
    }

    /// "$52k" — axis labels need to stay narrow at every Dynamic Type size.
    private func compactCurrency(_ value: Double) -> String {
        if value >= 1_000 {
            return "$\((value / 1_000).formatted(.number.precision(.fractionLength(0))))k"
        }
        return formatter.currency(value)
    }

    // MARK: - Readout

    private var readout: some View {
        let month = readoutMonth
        let costA = model.costA(atMonth: month)
        let costB = model.costB(atMonth: month)
        let difference = abs(costA - costB)
        let aheadName = costB < costA ? model.nameB : model.nameA

        return FSInsetRow(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("AT \(scrubLabel(month))")
                        .font(FSFont.label)
                        .tracking(1)
                        .foregroundStyle(theme.tertiaryText)
                    Spacer()
                    Text(difference < 0.005 ? "Level" : "\(aheadName) ahead by \(formatter.currency(difference))")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.accentMuted)
                        .multilineTextAlignment(.trailing)
                }

                seriesRow(name: model.nameA, value: costA, isAccented: false)
                seriesRow(name: model.nameB, value: costB, isAccented: true)

                Text(scrubMonth == nil
                     ? "Drag across the chart to read any date."
                     : "Release to snap back to your horizon.")
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .accessibilityHidden(true)
    }

    private func seriesRow(name: String, value: Double, isAccented: Bool) -> some View {
        HStack {
            FSSeriesSwatch(isAccented: isAccented)
            Text(name)
                .font(FSFont.footnote)
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Spacer()
            Text(formatter.currency(value))
                .font(FSFont.figureSmall)
                .foregroundStyle(isAccented ? theme.accentText : theme.text)
        }
    }

    private func scrubLabel(_ month: Int) -> String {
        let years = Double(month) / 12
        let yearText = years == years.rounded()
            ? "\(Int(years)) yr"
            : "\(years.formatted(.number.precision(.fractionLength(1)))) yr"
        return "\(yearText) · \(formatter.approximateDistance(model.kilometres(atMonth: month)))"
    }
}
