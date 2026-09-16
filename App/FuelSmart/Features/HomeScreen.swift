import SwiftUI
import SwiftData
import FuelSmartCore

/// Home states what the product does in one sentence and offers exactly two ways
/// in. Everything else on the screen is history the user made.
struct HomeScreen: View {

    var onStartComparison: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.fsTheme) private var theme
    @Environment(\.modelContext) private var context

    @Query(sort: \SavedComparisonEntity.dateModified, order: .reverse)
    private var saved: [SavedComparisonEntity]

    @State private var route: CompareRoute?

    private var recent: [SavedComparisonEntity] { Array(saved.prefix(3)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                intro
                actions
                if !recent.isEmpty { recentSection }
                howItWorks
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("FuelSmart")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $route) { route in
            CompareScreen(initialMode: route.mode, editing: route.saved)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Spacer()
            Label(
                model.region == .canada ? "Canada" : "United States",
                systemImage: "mappin.and.ellipse"
            )
            .font(FSFont.footnote)
            .foregroundStyle(theme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(theme.inset))
            .accessibilityLabel("Region: \(model.region == .canada ? "Canada" : "United States")")
        }
        .padding(.top, 4)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What will your next car really cost?")
                .font(FSFont.display)
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("Compare purchase price, fuel, electricity and ownership costs using your real driving habits.")
                .font(FSFont.body)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 9) {
            Button("Compare vehicles") {
                route = CompareRoute(mode: .buyVsBuy, saved: nil)
            }
            .buttonStyle(FSPrimaryButtonStyle())

            Button("Keep vs replace") {
                route = CompareRoute(mode: .keepVsReplace, saved: nil)
            }
            .buttonStyle(FSGhostButtonStyle())
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                FSSectionLabel("Recent")
                Spacer()
            }
            ForEach(recent) { entity in
                Button {
                    open(entity)
                } label: {
                    SavedComparisonCard(entity: entity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var howItWorks: some View {
        FSInsightCard(
            kind: .finding,
            label: "How it works",
            message: "Pick two vehicles, enter what you'll pay and how you drive. FuelSmart charts both costs over time and finds the crossover — if there is one.",
            systemImage: "lightbulb"
        )
    }

    private func open(_ entity: SavedComparisonEntity) {
        guard let saved = try? entity.toSavedComparison() else { return }
        route = CompareRoute(mode: saved.scenario.mode, saved: saved)
    }
}

/// A route into the compare flow, either fresh or resuming a saved comparison.
struct CompareRoute: Hashable, Identifiable {
    let mode: ComparisonMode
    let saved: SavedComparison?
    var id: String { saved?.id.uuidString ?? mode.rawValue }
}

/// The card used on Home and in the Saved list.
///
/// Reads entirely from the denormalised columns, so rendering a list never
/// decodes a stored scenario.
struct SavedComparisonCard: View {
    let entity: SavedComparisonEntity
    var showsModeTag: Bool = false

    @Environment(\.fsTheme) private var theme

    var body: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entity.name)
                            .font(FSFont.bodyMedium)
                            .foregroundStyle(theme.text)
                            .multilineTextAlignment(.leading)
                        Text("\(entity.mode.displayName) · \(entity.dateModified.formatted(.dateTime.day().month(.abbreviated).year()))")
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.tertiaryText)
                    }
                    Spacer(minLength: 8)
                    if showsModeTag {
                        FSTag(
                            text: entity.mode.displayName,
                            style: entity.mode == .keepVsReplace ? .accent : .neutral
                        )
                    }
                }

                HStack(spacing: 8) {
                    Text(entity.vehicleASummary)
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.seriesAEmphasis)
                    Text("VS")
                        .font(FSFont.label)
                        .foregroundStyle(theme.tertiaryText)
                    Text(entity.vehicleBSummary)
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.accentText)
                    Spacer(minLength: 0)
                }

                // Two proportional strokes stand in for the pair of curves,
                // matching the series colours used everywhere else.
                HStack(spacing: 8) {
                    Capsule().fill(theme.seriesA).frame(height: 6)
                    Capsule().fill(theme.seriesB).frame(height: 6)
                }
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entity.name), \(entity.mode.displayName), \(entity.vehicleASummary) versus \(entity.vehicleBSummary)")
        .accessibilityAddTraits(.isButton)
    }
}
