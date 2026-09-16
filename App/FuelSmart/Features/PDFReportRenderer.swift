import SwiftUI
import FuelSmartCore
import CoreGraphics
import UniformTypeIdentifiers

/// Renders the detailed report as a PDF, entirely on device.
///
/// Uses Core Graphics' PDF context plus SwiftUI's `ImageRenderer` — no server,
/// no third-party PDF library. The page is US Letter at 72 dpi (612 × 792 pt)
/// and is always drawn in the **print palette**: a light ground, no glow, and
/// the accent dropped a step so it holds contrast on paper.
enum PDFReportRenderer {

    static let pageSize = CGSize(width: 612, height: 792)

    enum RenderError: LocalizedError {
        case contextUnavailable
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .contextUnavailable: "A PDF context could not be created."
            case .renderFailed: "The report could not be drawn."
            }
        }
    }

    /// Render and write to a temporary file, returning its URL for sharing.
    @MainActor
    static func render(result: FuelSmartCore.ComparisonResult, includePrices: Bool) throws -> URL {
        let filename = suggestedFilename(for: result)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let page = PDFReportPage(result: result, includePrices: includePrices)
            .frame(width: pageSize.width, height: pageSize.height)
            .fsTheme(.light)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: page)
        // Render at 1× into a vector PDF context: text and shapes stay vector
        // rather than becoming a bitmap, so the report prints cleanly.
        renderer.scale = 1

        var didRender = false
        var thrownError: Error?

        renderer.render { size, renderInContext in
            var mediaBox = CGRect(origin: .zero, size: pageSize)
            guard let consumer = CGDataConsumer(url: url as CFURL),
                  let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                thrownError = RenderError.contextUnavailable
                return
            }
            context.beginPDFPage(nil)
            // Centre the rendered content if SwiftUI measured it slightly
            // differently from the requested page size.
            context.translateBy(
                x: (pageSize.width - size.width) / 2,
                y: (pageSize.height - size.height) / 2
            )
            renderInContext(context)
            context.endPDFPage()
            context.closePDF()
            didRender = true
        }

        if let thrownError { throw thrownError }
        guard didRender else { throw RenderError.renderFailed }
        return url
    }

    static func suggestedFilename(for result: FuelSmartCore.ComparisonResult) -> String {
        let names = "\(result.sideA.vehicle.shortDisplayName)-vs-\(result.sideB.vehicle.shortDisplayName)"
        let safe = names
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "FuelSmart-\(safe)-\(formatter.string(from: Date())).pdf"
    }
}

/// The printed page.
///
/// Laid out for paper rather than for a screen: no interactivity, no elevation,
/// a hairline rule instead of a shadow, and every assumption stated in full at
/// the foot so the sheet stands on its own.
struct PDFReportPage: View {

    let result: FuelSmartCore.ComparisonResult
    var includePrices: Bool

    @Environment(\.fsTheme) private var theme

    private var formatter: ValueFormatter { ValueFormatter(region: result.scenario.region) }
    private var narrator: ResultNarrator { ResultNarrator(region: result.scenario.region) }
    private var horizonYears: Int { Int(result.scenario.horizon.years) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            title
            chartSection
            lineItems
            Spacer(minLength: 0)
            assumptionsFooter
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 52)
        .frame(width: PDFReportRenderer.pageSize.width, height: PDFReportRenderer.pageSize.height)
        .background(Color.white)
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                BrandMark(size: 26)
                Text("FUELSMART")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Nocturne.Neutral.n700)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Vehicle cost comparison")
                Text("\(Date().formatted(.dateTime.day().month(.wide).year())) · \(result.scenario.region == .canada ? "Canada" : "United States") · \(formatter.currencyCode)")
            }
            .font(.system(size: 9))
            .foregroundStyle(Nocturne.Neutral.n600)
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Nocturne.Neutral.n300).frame(height: 1)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(result.sideA.vehicle.fullDisplayName) vs \(result.sideB.vehicle.fullDisplayName)")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Nocturne.Neutral.n900)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(result.breakEven.explanation) \(narrator.headline(for: result))")
                .font(.system(size: 11))
                .foregroundStyle(Nocturne.Neutral.n700)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chartSection: some View {
        let model = CumulativeCostChartModel(result: result, sampleStride: 2)
        return VStack(alignment: .leading, spacing: 9) {
            Text("CUMULATIVE COST")
                .font(.system(size: 8, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(Nocturne.Neutral.n600)

            // Drawn directly rather than via Swift Charts: a plain path renders
            // predictably into a PDF context at any page size.
            PDFCurveChart(model: model)
                .frame(height: 170)

            HStack(spacing: 18) {
                legendItem(colour: Nocturne.Neutral.n600, label: result.sideA.vehicle.shortDisplayName)
                legendItem(colour: Nocturne.Accent.a600, label: result.sideB.vehicle.shortDisplayName)
                Spacer()
                Text("0 – \(model.maxMonth / 12) years")
                    .font(.system(size: 8))
                    .foregroundStyle(Nocturne.Neutral.n600)
            }
        }
    }

    private func legendItem(colour: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(colour).frame(width: 14, height: 2)
            Text(label).font(.system(size: 8)).foregroundStyle(Nocturne.Neutral.n600)
        }
    }

    private var lineItems: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("LINE ITEM")
                Text(result.sideA.vehicle.shortDisplayName.uppercased()).gridColumnAlignment(.trailing)
                Text(result.sideB.vehicle.shortDisplayName.uppercased()).gridColumnAlignment(.trailing)
            }
            .font(.system(size: 8, weight: .medium))
            .tracking(1.2)
            .foregroundStyle(Nocturne.Neutral.n600)

            row("Net acquisition",
                formatter.currency(result.sideA.netAcquisitionCost),
                formatter.currency(result.sideB.netAcquisitionCost),
                topRule: true)

            if includePrices {
                row("Vehicle price",
                    formatter.currency(result.scenario.sideA.acquisition.purchasePrice),
                    formatter.currency(result.scenario.sideB.acquisition.purchasePrice))
            }

            row("Energy per 100 \(formatter.distanceUnit)",
                formatter.rate(result.sideA.energy.totalCostPer100Km),
                formatter.rate(result.sideB.energy.totalCostPer100Km))

            row("Energy per year",
                formatter.currency(result.sideA.energy.annualTotal),
                formatter.currency(result.sideB.energy.annualTotal))

            row("Energy over \(horizonYears) years",
                formatter.currency(result.sideA.energy.annualTotal * Double(horizonYears)),
                formatter.currency(result.sideB.energy.annualTotal * Double(horizonYears)))

            if result.sideA.financing.totalInterest > 0 || result.sideB.financing.totalInterest > 0 {
                row("Financing interest to \(horizonYears) yr",
                    formatter.currency(result.sideA.financing.cumulativeInterest(atMonth: result.horizonMonths)),
                    formatter.currency(result.sideB.financing.cumulativeInterest(atMonth: result.horizonMonths)))
            }

            if result.assumptions.includesOwnershipCosts {
                row("Ownership costs over \(horizonYears) yr",
                    formatter.currency(result.sideA.annualRecurringCost * Double(horizonYears)),
                    formatter.currency(result.sideB.annualRecurringCost * Double(horizonYears)))
            }

            if result.assumptions.includesResale {
                row("Resale at \(horizonYears) yr",
                    "−" + formatter.currency(result.sideA.resaleCredit),
                    "−" + formatter.currency(result.sideB.resaleCredit))
            }

            GridRow {
                Text("Total at \(horizonYears) years")
                Text(formatter.currency(result.totalA)).gridColumnAlignment(.trailing)
                Text(formatter.currency(result.totalB)).gridColumnAlignment(.trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Nocturne.Neutral.n900)
            .padding(.top, 8)
            .overlay(alignment: .top) {
                Rectangle().fill(Nocturne.Neutral.n900).frame(height: 1)
            }
        }
    }

    private func row(_ label: String, _ a: String, _ b: String, topRule: Bool = false) -> some View {
        GridRow {
            Text(label)
            Text(a).gridColumnAlignment(.trailing)
            Text(b).gridColumnAlignment(.trailing)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(Nocturne.Neutral.n900)
        .padding(.top, topRule ? 8 : 0)
        .overlay(alignment: .top) {
            if topRule { Rectangle().fill(Nocturne.Neutral.n300).frame(height: 1) }
        }
    }

    private var assumptionsFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ASSUMPTIONS")
                .font(.system(size: 8, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(Nocturne.Neutral.n600)

            Text(footerText)
                .font(.system(size: 9))
                .foregroundStyle(Nocturne.Neutral.n700)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Nocturne.Neutral.n300).frame(height: 1)
        }
    }

    private var footerText: String {
        var text = narrator.assumptionsLine(for: result) + ". "
        if let source = result.dataSources.first {
            text += "Efficiency ratings: \(source.publisher), \(source.dataset). "
        }
        text += "Prices are user-entered. FuelSmart does not forecast fuel prices or depreciation. "
        text += "Government ratings are standardized laboratory tests and may differ from real-world use. "
        text += "This is an informational comparison, not financial advice."
        return text
    }
}

/// A plain-path rendering of the two curves for print.
///
/// Swift Charts is built for interactive display; drawing the curves as explicit
/// paths keeps the PDF vector output simple and predictable.
private struct PDFCurveChart: View {
    let model: CumulativeCostChartModel

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let maxCost = max(model.maxCost, 1)
            let maxMonth = max(Double(model.maxMonth), 1)

            func point(_ p: CumulativeCostChartModel.Point) -> CGPoint {
                CGPoint(
                    x: Double(p.month) / maxMonth * width,
                    y: height - (p.cost / maxCost) * height
                )
            }

            ZStack {
                // Grid.
                ForEach(0..<4, id: \.self) { index in
                    let y = height * Double(index) / 3
                    Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: width, y: y)) }
                        .stroke(Nocturne.Neutral.n200, lineWidth: 0.75)
                }

                curve(model.pointsA.map(point)).stroke(Nocturne.Neutral.n600, lineWidth: 2)
                curve(model.pointsB.map(point)).stroke(Nocturne.Accent.a600, lineWidth: 2)

                if let month = model.breakEvenMonth, let cost = model.breakEvenCost {
                    let x = Double(month) / maxMonth * width
                    let y = height - (cost / maxCost) * height
                    Circle()
                        .fill(Nocturne.Accent.a700)
                        .frame(width: 7, height: 7)
                        .position(x: x, y: y)
                }
            }
        }
    }

    private func curve(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }
}
