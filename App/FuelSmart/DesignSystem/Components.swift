import SwiftUI
import FuelSmartCore

// MARK: - Card

/// The resting surface everything sits on. 14 pt padding, `lg` radius, `sm`
/// elevation — a hairline on dark, a soft ink shadow on light.
struct FSCard<Content: View>: View {
    var padding: CGFloat = Nocturne.Space.cardPadding
    var elevation: FSElevation = .small
    var isAccented: Bool = false
    @ViewBuilder var content: Content

    @Environment(\.fsTheme) private var theme

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Nocturne.Radius.large, style: .continuous)
                    .fill(isAccented ? theme.accentSurface : theme.surface)
            )
            .fsElevation(elevation, theme: theme)
    }
}

/// A row nested inside a card — the inset ground, `md` radius.
struct FSInsetRow<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content
    @Environment(\.fsTheme) private var theme

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                    .fill(theme.inset)
            )
    }
}

// MARK: - Buttons

/// Primary is an **accent outline, never a fill** — one of the design's
/// load-bearing rules.
struct FSPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = Nocturne.primaryButtonHeight
    @Environment(\.fsTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FSFont.bodyMedium)
            .foregroundStyle(theme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                    .fill(theme.accent.opacity(configuration.isPressed ? 0.22 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                    .strokeBorder(theme.accent, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

struct FSSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = Nocturne.controlHeight
    @Environment(\.fsTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FSFont.bodyMedium)
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                    .fill(theme.text.opacity(configuration.isPressed ? 0.14 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                    .strokeBorder(theme.divider, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

struct FSGhostButtonStyle: ButtonStyle {
    var height: CGFloat = Nocturne.minimumTapTarget
    @Environment(\.fsTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FSFont.bodyMedium)
            .foregroundStyle(theme.accentMuted)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                    .fill(theme.accent.opacity(configuration.isPressed ? 0.18 : 0))
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Tag

struct FSTag: View {
    enum Style { case accent, neutral, outline }

    let text: String
    var style: Style = .neutral
    @Environment(\.fsTheme) private var theme

    var body: some View {
        Text(text)
            .font(FSFont.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(background)
            .overlay(border)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: Nocturne.Radius.small * 1.5, style: .continuous))
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .accent: theme.accentSurface
        case .neutral: theme.isDark ? Nocturne.Neutral.n800 : Nocturne.Neutral.n200
        case .outline: Color.clear
        }
    }

    @ViewBuilder private var border: some View {
        if style == .outline {
            RoundedRectangle(cornerRadius: Nocturne.Radius.small * 1.5, style: .continuous)
                .strokeBorder(theme.accent, lineWidth: 1)
        }
    }

    private var foreground: Color {
        switch style {
        case .accent: theme.accentText
        case .neutral: theme.text
        case .outline: theme.accentMuted
        }
    }
}

/// The tag style for a powertrain. Electric and plug-in take the accent because
/// they are the two that involve a charging decision — not because they are
/// preferred.
extension FSTag {
    static func powertrain(_ powertrain: Powertrain) -> FSTag {
        FSTag(
            text: powertrain.displayName,
            style: powertrain.usesElectricity ? .accent : .neutral
        )
    }
}

// MARK: - Segmented control

/// The horizon / period selector. Rebuilt rather than using `Picker(.segmented)`
/// so it carries the Nocturne ground and radius.
struct FSSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var accessibilityPrefix: String = ""

    @Environment(\.fsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            // Iterating by index rather than by a key path into a tuple:
            // Swift has no key paths to tuple elements.
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button {
                    withAnimation(FSMotion.valueChange(reduceMotion: reduceMotion)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(isSelected ? FSFont.bodyMedium : FSFont.body)
                        .foregroundStyle(isSelected ? theme.text : theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? (theme.isDark ? Nocturne.Neutral.n700 : theme.surface) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(accessibilityPrefix)\(option.label)")
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.inset))
    }
}

// MARK: - Split slider

/// One handle, two values — the split can never leave 100%.
///
/// Implemented as a single fraction with a drag gesture rather than two linked
/// sliders, so the invariant holds by construction rather than by correction.
struct FSSplitSlider: View {
    @Binding var split: Split
    let primaryLabel: String
    let secondaryLabel: String
    var height: CGFloat = 34

    @Environment(\.fsTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(theme.inset)
                    .overlay(
                        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )

                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(theme.isDark ? Nocturne.Accent.a800 : Nocturne.Accent.a200)
                    .frame(width: max(width * split.primary, 0))

                // The handle.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.accentText)
                    .frame(width: 4, height: height - 8)
                    .shadow(color: theme.glow, radius: 6)
                    .offset(x: max(min(width * split.primary, width - 2), 2) - 2)

                HStack {
                    Text(primaryLabel).font(FSFont.footnote).fontWeight(.medium)
                    Spacer()
                    Text(secondaryLabel).font(FSFont.footnote).foregroundStyle(theme.secondaryText)
                }
                .padding(.horizontal, 14)
                .foregroundStyle(theme.text)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        split = Split(primary: value.location.x / width)
                    }
            )
        }
        .frame(height: height)
        // A drag target is not discoverable to VoiceOver, so the split is also
        // exposed as an adjustable value with explicit increments.
        .accessibilityElement()
        .accessibilityLabel("\(primaryLabel) and \(secondaryLabel) split")
        .accessibilityValue("\(Int(split.primaryPercent.rounded())) percent \(primaryLabel), \(Int(split.secondaryPercent.rounded())) percent \(secondaryLabel)")
        .accessibilityAdjustableAction { direction in
            let step = 5.0
            switch direction {
            case .increment: split = Split(primaryPercent: split.primaryPercent + step)
            case .decrement: split = Split(primaryPercent: split.primaryPercent - step)
            @unknown default: break
            }
        }
    }
}

// MARK: - Vehicle badge

/// The vehicle chip used wherever a selected vehicle is shown. `isAccented`
/// marks side B, consistently, everywhere.
struct FSVehicleBadge: View {
    let vehicle: Vehicle
    var isAccented: Bool
    var formatter: ValueFormatter

    @Environment(\.fsTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                .fill(isAccented ? theme.accentSurface : (theme.isDark ? Nocturne.Neutral.n800 : Nocturne.Neutral.n200))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "car.side")
                        .foregroundStyle(isAccented ? theme.accentText : theme.secondaryText)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.fullDisplayName)
                    .font(FSFont.bodyMedium)
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                Text(detailLine)
                    .font(FSFont.footnote)
                    .foregroundStyle(isAccented ? theme.accentMuted : theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                .fill(isAccented ? theme.accentSurface : theme.inset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                .strokeBorder(isAccented ? theme.accentBorder : .clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        [vehicle.powertrain.displayName, formatter.consumption(for: vehicle)]
            .filter { $0 != "—" }
            .joined(separator: " · ")
    }
}

// MARK: - Series swatch

/// The 22×3 stroke that identifies a series. Series are distinguished by stroke
/// weight and label as well as colour, never by colour alone.
struct FSSeriesSwatch: View {
    var isAccented: Bool
    @Environment(\.fsTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(isAccented ? theme.seriesB : theme.seriesA)
            .frame(width: 22, height: 3)
            .shadow(color: isAccented ? theme.glow : .clear, radius: 5)
            .accessibilityHidden(true)
    }
}

// MARK: - Comparison row

/// Two values with proportional bars. Bars are always proportional to the larger
/// value, so the reader can size the gap without reading the numbers.
struct FSComparisonRow: View {
    let label: String
    let nameA: String
    let nameB: String
    let valueA: Double
    let valueB: Double
    let format: (Double) -> String

    @Environment(\.fsTheme) private var theme

    private var maximum: Double { max(valueA, valueB, .leastNonzeroMagnitude) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FSSectionLabel(label)

            row(name: nameA, value: valueA, isAccented: false)
            bar(fraction: valueA / maximum, isAccented: false)
            row(name: nameB, value: valueB, isAccented: true)
            bar(fraction: valueB / maximum, isAccented: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label). \(nameA) \(format(valueA)). \(nameB) \(format(valueB)).")
    }

    private func row(name: String, value: Double, isAccented: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(FSFont.footnote)
                .foregroundStyle(theme.secondaryText)
            Spacer()
            Text(format(value))
                .font(FSFont.figureMedium)
                .foregroundStyle(isAccented ? theme.accentText : theme.text)
        }
    }

    private func bar(fraction: Double, isAccented: Bool) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isAccented ? theme.seriesB : theme.seriesA)
                .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), 2))
                .shadow(color: isAccented ? theme.glow : .clear, radius: 7)
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

// MARK: - Insight card

/// An accent-tinted card is a **finding**; a neutral card is a **caveat**.
/// Never more than one accent card per screen.
struct FSInsightCard: View {
    enum Kind { case finding, caveat }

    let kind: Kind
    let label: String
    let message: String
    var systemImage: String?

    @Environment(\.fsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption)
                }
                Text(label.uppercased())
                    .font(FSFont.label)
                    .tracking(1.2)
            }
            .foregroundStyle(kind == .finding ? theme.accentMuted : theme.tertiaryText)
            .accessibilityLabel(label)

            Text(message)
                .font(FSFont.body)
                .foregroundStyle(kind == .finding ? theme.accentText : theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Nocturne.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Nocturne.Radius.large, style: .continuous)
                .fill(kind == .finding ? theme.accentSurface : theme.inset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Nocturne.Radius.large, style: .continuous)
                .strokeBorder(kind == .finding ? theme.accentBorder : .clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Data tile

/// The small labelled figure used in efficiency grids.
struct FSDataTile: View {
    let label: String
    let value: String
    var unit: String?
    var isAccented: Bool = false

    @Environment(\.fsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(FSFont.label)
                .tracking(0.8)
                .foregroundStyle(isAccented ? theme.accentMuted : theme.tertiaryText)
            Text(value)
                .font(FSFont.figureSmall)
                .foregroundStyle(isAccented ? theme.accentText : theme.text)
            if let unit {
                Text(unit)
                    .font(FSFont.label)
                    .foregroundStyle(isAccented ? theme.accentMuted : theme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Nocturne.Radius.small, style: .continuous)
                .fill(isAccented ? theme.accentSurface : theme.inset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Nocturne.Radius.small, style: .continuous)
                .strokeBorder(isAccented ? theme.accentBorder : .clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit ?? "")")
    }
}

// MARK: - States

struct FSEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.fsTheme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(theme.tertiaryText)
            Text(title)
                .font(FSFont.headline)
                .foregroundStyle(theme.text)
            Text(message)
                .font(FSFont.footnote)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(FSSecondaryButtonStyle(height: 38))
                    .fixedSize()
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Nocturne.Radius.large, style: .continuous)
                .fill(theme.surface)
        )
    }
}

/// An advisory or error card. Uses an icon and text, never colour alone.
struct FSNoticeCard: View {
    enum Severity { case info, warning }

    let severity: Severity
    let systemImage: String
    let title: String
    let message: String
    var actions: [(title: String, action: () -> Void)] = []

    @Environment(\.fsTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(severity == .warning ? theme.warning : theme.secondaryText)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(FSFont.bodyMedium)
                    .foregroundStyle(theme.text)
                Text(message)
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(actions.indices, id: \.self) { index in
                            let entry = actions[index]
                            Button(entry.title, action: entry.action)
                                .buttonStyle(FSSecondaryButtonStyle(height: 36))
                                .fixedSize()
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(Nocturne.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Nocturne.Radius.large, style: .continuous)
                .fill(theme.surface)
        )
        .fsElevation(.small, theme: theme)
        .accessibilityElement(children: .combine)
    }
}

/// Shimmering placeholder used while the records file decodes.
struct FSSkeleton: View {
    var height: CGFloat = 14
    var widthFraction: CGFloat = 1

    @Environment(\.fsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.inset)
                .frame(width: proxy.size.width * widthFraction)
                .overlay {
                    if !reduceMotion {
                        LinearGradient(
                            colors: [.clear, theme.strongBorder.opacity(0.35), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .offset(x: shimmer ? proxy.size.width : -proxy.size.width)
                        .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: shimmer)
                        .clipped()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .frame(height: height)
        .onAppear { shimmer = true }
        .accessibilityHidden(true)
    }
}
