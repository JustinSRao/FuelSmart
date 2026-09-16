import SwiftUI

/// The Nocturne type scale.
///
/// Each role maps to a **semantic** text style rather than a fixed point size,
/// so every label scales from xSmall to AX5 without a hand-built breakpoint —
/// which is what the design reference specifies. The sizes quoted in the design
/// (display 34/40, title 22/28, headline 17/22, body 15/22, footnote 13/18,
/// label 11 caps) are the values these styles resolve to at the default Dynamic
/// Type size.
///
/// Money and distances use `.monospacedDigit()` so columns do not jitter while a
/// slider moves.
enum FSFont {

    /// 34/40, −2% tracking. The single headline figure on a results screen.
    static var display: Font { .system(.largeTitle, design: .default, weight: .medium) }

    /// 22/28. Section headings and sheet titles.
    static var title: Font { .system(.title2, design: .default, weight: .medium) }

    /// 17/22. Vehicle names, navigation titles, row leads.
    static var headline: Font { .system(.headline, design: .default, weight: .medium) }

    /// 15/22. Body copy.
    static var body: Font { .system(.subheadline) }

    /// 15/22, emphasised.
    static var bodyMedium: Font { .system(.subheadline, weight: .medium) }

    /// 13/18. Secondary and explanatory copy.
    static var footnote: Font { .system(.footnote) }

    /// 11, uppercase, +14% tracking. Section labels.
    static var label: Font { .system(.caption2, weight: .medium) }

    /// A large tabular figure, for the number a screen exists to show.
    static var figure: Font { .system(.title, design: .default, weight: .medium).monospacedDigit() }

    /// A tabular figure at body size, for table cells.
    static var figureSmall: Font { .system(.subheadline, weight: .medium).monospacedDigit() }

    /// A tabular figure at headline size.
    static var figureMedium: Font { .system(.title3, weight: .medium).monospacedDigit() }
}

// MARK: - Label style

/// The uppercase tracked label used above every section.
struct FSSectionLabel: View {
    let text: String
    @Environment(\.fsTheme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(FSFont.label)
            .tracking(1.4)
            .foregroundStyle(theme.tertiaryText)
            // The visual uppercasing is decorative; VoiceOver reads the natural
            // capitalisation so it is not spelled out letter by letter.
            .accessibilityLabel(text)
    }
}

extension View {
    /// Tabular figures, for any number that changes in place.
    func fsTabularNumbers() -> some View {
        monospacedDigit()
    }
}

// MARK: - Motion

/// Transitions are 180 ms ease-out on value change and 240 ms on sheet
/// presentation. Reduce Motion swaps chart redraws for a cross-fade and disables
/// the glow pulse on the break-even marker.
enum FSMotion {
    static let valueChange = Animation.easeOut(duration: 0.18)
    static let sheet = Animation.easeOut(duration: 0.24)

    /// The animation to use for a value change, honouring Reduce Motion.
    static func valueChange(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .linear(duration: 0.12) : valueChange
    }
}
