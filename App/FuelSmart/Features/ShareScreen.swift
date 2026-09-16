import SwiftUI
import Charts
import FuelSmartCore
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Share a polished card, or a fuller PDF report.
///
/// Both are rendered locally with native frameworks. Nothing is uploaded, and
/// the user chooses the destination through the system share sheet.
struct ShareScreen: View {

    let result: ComparisonResult

    @Environment(\.fsTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var includeAssumptions = true
    @State private var includePrices = false
    @State private var shareItems: [Any] = []
    @State private var isPreparing = false
    @State private var errorMessage: String?

    private var formatter: ValueFormatter { ValueFormatter(region: result.scenario.region) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ShareCardView(
                    result: result,
                    includeAssumptions: includeAssumptions,
                    includePrices: includePrices
                )
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)

                FSCard {
                    VStack(alignment: .leading, spacing: 12) {
                        FSToggleRow(
                            title: "Include my assumptions",
                            caption: "Distance, energy prices and what the total covers.",
                            isOn: $includeAssumptions
                        )
                        Divider().overlay(theme.divider)
                        FSToggleRow(
                            title: "Include prices I entered",
                            caption: "Off by default — what you paid is usually private.",
                            isOn: $includePrices
                        )
                    }
                }

                if let errorMessage {
                    FSNoticeCard(
                        severity: .warning,
                        systemImage: "exclamationmark.triangle",
                        title: "Couldn't prepare that",
                        message: errorMessage
                    )
                }

                HStack(spacing: 10) {
                    Button { Task { await shareImage() } } label: {
                        Label("Image", systemImage: "photo")
                    }
                    .buttonStyle(FSSecondaryButtonStyle())

                    Button { Task { await sharePDF() } } label: {
                        Label("Full PDF", systemImage: "doc.richtext")
                    }
                    .buttonStyle(FSSecondaryButtonStyle())
                }
                .disabled(isPreparing)

                Text("Rendered on this device. Nothing is uploaded — you choose where it goes.")
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 28)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("Share")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: Binding(
            get: { !shareItems.isEmpty },
            set: { if !$0 { shareItems = [] } }
        )) {
            ActivityView(items: shareItems)
        }
    }

    // MARK: - Rendering

    /// Render the card at 3× so it stays sharp when shared.
    ///
    /// The card is rendered in the **light** palette regardless of the device's
    /// appearance: a shared image lands on someone else's screen, and glow and
    /// dark grounds do not survive that trip well.
    @MainActor
    private func shareImage() async {
        isPreparing = true
        defer { isPreparing = false }

        let card = ShareCardView(
            result: result,
            includeAssumptions: includeAssumptions,
            includePrices: includePrices
        )
        .frame(width: 420)
        .fsTheme(.light)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: card)
        renderer.scale = max(displayScale, 3)

        #if canImport(UIKit)
        guard let image = renderer.uiImage else {
            errorMessage = "The share image couldn't be rendered."
            return
        }
        shareItems = [image]
        #elseif canImport(AppKit)
        guard let image = renderer.nsImage else {
            errorMessage = "The share image couldn't be rendered."
            return
        }
        shareItems = [image]
        #endif
    }

    @MainActor
    private func sharePDF() async {
        isPreparing = true
        defer { isPreparing = false }

        do {
            let url = try PDFReportRenderer.render(result: result, includePrices: includePrices)
            shareItems = [url]
        } catch {
            errorMessage = "The PDF couldn't be created: \(error.localizedDescription)"
        }
    }
}

// MARK: - The share card

/// The branded card. Deliberately compact: the two vehicles, the shape of the
/// two curves, and the figures that matter, with the assumptions that produced
/// them.
struct ShareCardView: View {

    let result: ComparisonResult
    var includeAssumptions: Bool = true
    var includePrices: Bool = false

    @Environment(\.fsTheme) private var theme

    private var formatter: ValueFormatter { ValueFormatter(region: result.scenario.region) }
    private var narrator: ResultNarrator { ResultNarrator(region: result.scenario.region) }
    private var horizonYears: Int { Int(result.scenario.horizon.years) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            vehicles
            miniChart
            figures
            if includeAssumptions { assumptions }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.surface)
        )
        .fsElevation(.large, theme: theme)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                BrandMark(size: 22)
                Text("FUELSMART")
                    .font(FSFont.label)
                    .tracking(2)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Text("\(result.scenario.region == .canada ? "Canada" : "United States") · \(formatter.currencyCode)")
                .font(FSFont.label)
                .foregroundStyle(theme.tertiaryText)
        }
    }

    private var vehicles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.sideA.vehicle.fullDisplayName)
                .font(FSFont.headline)
                .foregroundStyle(theme.text)
            Text("versus")
                .font(FSFont.footnote)
                .foregroundStyle(theme.tertiaryText)
            Text(result.sideB.vehicle.fullDisplayName)
                .font(FSFont.headline)
                .foregroundStyle(theme.text)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var miniChart: some View {
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
                    .symbolSize(70)
                    .foregroundStyle(theme.isDark ? Nocturne.Accent.a300 : Nocturne.Accent.a700)
            }
        }
        .chartYScale(domain: 0...max(model.maxCost, 1))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 96)
        .accessibilityHidden(true)
    }

    private var figures: some View {
        VStack(spacing: 11) {
            Divider().overlay(theme.divider)
            row("Annual driving", formatter.distance(result.assumptions.annualKilometres))
            if includePrices {
                row("\(result.sideA.vehicle.shortDisplayName) price",
                    formatter.currency(result.scenario.sideA.acquisition.purchasePrice))
                row("\(result.sideB.vehicle.shortDisplayName) price",
                    formatter.currency(result.scenario.sideB.acquisition.purchasePrice))
            }
            row("Energy difference", "\(formatter.currency(result.energyCostDifferencePerYear)) / yr")
            row("Break-even", narrator.breakEvenChip(result.breakEven, horizonYears: horizonYears))

            HStack(alignment: .firstTextBaseline) {
                Text("\(horizonYears)-year difference")
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.accentMuted)
                Spacer()
                Text(formatter.currency(result.costDifferenceAtHorizon))
                    .font(FSFont.figureMedium)
                    .foregroundStyle(theme.accentText)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(FSFont.footnote)
                .foregroundStyle(theme.secondaryText)
            Spacer()
            Text(value)
                .font(FSFont.figureSmall)
                .foregroundStyle(theme.text)
        }
    }

    private var assumptions: some View {
        Text("Assumptions: \(narrator.assumptionsLine(for: result)). Efficiency data: \(result.dataSources.first?.publisher ?? "official government sources").")
            .font(FSFont.label)
            .foregroundStyle(theme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Share sheet

/// The native share sheet, on both platforms.
struct ActivityView: View {
    let items: [Any]

    var body: some View {
        #if canImport(UIKit)
        ActivityViewControllerRepresentable(items: items)
        #else
        MacShareView(items: items)
        #endif
    }
}

#if canImport(UIKit)
private struct ActivityViewControllerRepresentable: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#else
private struct MacShareView: NSViewRepresentable {
    let items: [Any]

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard !items.isEmpty else { return }
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
#endif
