import SwiftUI

/// The Nocturne palette, as defined by the FuelSmart design reference.
///
/// Two rules carry the whole colour system and must survive any future polish:
///
/// 1. **Vehicle A is always neutral; vehicle B is always accent.** Never two
///    saturated hues competing for the reader.
/// 2. **Nothing turns green or red.** No colour implies moral approval of a
///    powertrain. The cheaper figure earns accent emphasis; the other stays
///    neutral. Verdict colour is earned, not decorative.
///
/// Light mode is not an inversion: elevation flips from "hairline plus ambient
/// darkness" to a soft ink shadow, and the accent glow is dropped entirely.
/// Glow exists only on dark.
enum Nocturne {

    // MARK: - Ramps
    //
    // Generated in OKLCH on one shared lightness scale, so the same step of any
    // role matches the others in visual value.

    enum Neutral {
        static let n100 = Color(hex: 0xf3f5fe)
        static let n200 = Color(hex: 0xe4e7f5)
        static let n300 = Color(hex: 0xcfd3e5)
        static let n400 = Color(hex: 0xb2b6ca)
        static let n500 = Color(hex: 0x9397ab)
        static let n600 = Color(hex: 0x75798c)
        static let n700 = Color(hex: 0x595d6c)
        static let n800 = Color(hex: 0x3f424d)
        static let n900 = Color(hex: 0x292b31)
    }

    enum Accent {
        static let a100 = Color(hex: 0xf5f4ff)
        static let a200 = Color(hex: 0xe7e5fe)
        static let a300 = Color(hex: 0xd2cefd)
        static let a400 = Color(hex: 0xb5abfc)
        static let a500 = Color(hex: 0x968ae0)
        static let a600 = Color(hex: 0x796cbf)
        static let a700 = Color(hex: 0x5d5294)
        static let a800 = Color(hex: 0x423a6a)
        static let a900 = Color(hex: 0x2b2741)
        /// The product blurple itself.
        static let base = Color(hex: 0x9184d9)
    }

    // MARK: - Radius

    enum Radius {
        /// Chips and data tiles.
        static let small: CGFloat = 4
        /// Fields and inner rows.
        static let medium: CGFloat = 8
        /// Cards.
        static let large: CGFloat = 14
        /// Sheets.
        static let sheet: CGFloat = 22
    }

    // MARK: - Space
    //
    // Density 0.7×. Screen gutter 16, card padding 14, row rhythm 12.

    enum Space {
        static let x1: CGFloat = 2.8
        static let x2: CGFloat = 5.6
        static let x3: CGFloat = 8.4
        static let x4: CGFloat = 11.2
        static let x6: CGFloat = 16.8
        static let x8: CGFloat = 22.4

        static let gutter: CGFloat = 16
        static let cardPadding: CGFloat = 14
        static let rowRhythm: CGFloat = 12
    }

    /// Minimum tap target, per the design's control notes.
    static let minimumTapTarget: CGFloat = 44
    /// Primary control height.
    static let controlHeight: CGFloat = 46
    /// Prominent call-to-action height.
    static let primaryButtonHeight: CGFloat = 50
}

// MARK: - Resolved theme

/// The palette resolved for the current colour scheme and contrast setting.
///
/// Passed through the environment rather than read from `@Environment(\.colorScheme)`
/// at every call site, so that the PDF and share-card renderers can force the
/// light palette regardless of the device's appearance.
struct FSTheme: Equatable {
    var isDark: Bool
    var increaseContrast: Bool

    // MARK: Ground

    var background: Color { isDark ? Color(hex: 0x161826) : Nocturne.Neutral.n100 }
    var surface: Color { isDark ? Color(hex: 0x232532) : .white }
    /// The inset ground used for rows inside a card.
    var inset: Color { isDark ? Nocturne.Neutral.n900 : Nocturne.Neutral.n100 }

    // MARK: Text

    var text: Color {
        if isDark { return increaseContrast ? Nocturne.Neutral.n100 : Color(hex: 0xe9e9ed) }
        return Nocturne.Neutral.n900
    }
    var secondaryText: Color {
        if isDark { return increaseContrast ? Nocturne.Neutral.n300 : Nocturne.Neutral.n400 }
        return increaseContrast ? Nocturne.Neutral.n900 : Nocturne.Neutral.n600
    }
    var tertiaryText: Color { isDark ? Nocturne.Neutral.n500 : Nocturne.Neutral.n600 }

    // MARK: Accent
    //
    // On light the accent drops a step for strokes and two for text, holding
    // 4.5:1 against white.

    var accent: Color { isDark ? Nocturne.Accent.base : Nocturne.Accent.a600 }
    var accentText: Color { isDark ? Nocturne.Accent.a200 : Nocturne.Accent.a700 }
    var accentMuted: Color { isDark ? Nocturne.Accent.a300 : Nocturne.Accent.a600 }
    var accentSurface: Color { isDark ? Nocturne.Accent.a900 : Nocturne.Accent.a200 }
    var accentBorder: Color { isDark ? Nocturne.Accent.a800 : Nocturne.Accent.a300 }

    // MARK: Series
    //
    // The two comparison series. A is the ground's own grey, B is the accent.

    var seriesA: Color { isDark ? Nocturne.Neutral.n500 : Nocturne.Neutral.n600 }
    var seriesAEmphasis: Color { isDark ? Nocturne.Neutral.n300 : Nocturne.Neutral.n700 }
    var seriesB: Color { accent }
    var seriesBEmphasis: Color { accentText }

    // MARK: Lines

    var divider: Color { (isDark ? Color(hex: 0xe9e9ed) : Nocturne.Neutral.n900).opacity(increaseContrast ? 0.34 : 0.16) }
    var border: Color { isDark ? Nocturne.Neutral.n800 : Nocturne.Neutral.n200 }
    var strongBorder: Color { isDark ? Nocturne.Neutral.n600 : Nocturne.Neutral.n400 }
    var gridLine: Color { isDark ? Nocturne.Neutral.n900 : Nocturne.Neutral.n200 }

    /// Warning tint. Deliberately a desaturated clay rather than a true red —
    /// red would read as a verdict on a vehicle rather than on an input.
    var warning: Color { isDark ? Color(hex: 0xe0a0a0) : Color(hex: 0x8a5a5a) }

    /// Glow exists only on dark, and only on the break-even marker and a live
    /// chart marker.
    var glow: Color { isDark ? Nocturne.Accent.base.opacity(0.45) : .clear }

    static let dark = FSTheme(isDark: true, increaseContrast: false)
    static let light = FSTheme(isDark: false, increaseContrast: false)
}

private struct FSThemeKey: EnvironmentKey {
    static let defaultValue = FSTheme.dark
}

/// Whether the current container is wide enough for the two-column layout.
///
/// `horizontalSizeClass` exists only on iOS, so reading it directly would break
/// the macOS build. The root view resolves the question once — from the size
/// class on iOS, and always true on macOS, where a window is never compact — and
/// publishes the answer here.
private struct FSWideLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var fsTheme: FSTheme {
        get { self[FSThemeKey.self] }
        set { self[FSThemeKey.self] = newValue }
    }

    var fsIsWideLayout: Bool {
        get { self[FSWideLayoutKey.self] }
        set { self[FSWideLayoutKey.self] = newValue }
    }
}

extension View {
    /// Resolve and inject the theme for a subtree.
    func fsTheme(_ theme: FSTheme) -> some View {
        environment(\.fsTheme, theme)
    }
}

// MARK: - Elevation

/// Three elevations only: `sm` resting card, `md` floating control or tab bar,
/// `lg` sheet and dialog.
enum FSElevation {
    case small, medium, large
}

extension View {
    @ViewBuilder
    func fsElevation(_ level: FSElevation, theme: FSTheme) -> some View {
        switch (level, theme.isDark) {
        case (.small, true):
            overlay(RoundedRectangle(cornerRadius: Nocturne.Radius.large, style: .continuous)
                .strokeBorder(Nocturne.Neutral.n800, lineWidth: 1))
        case (.small, false):
            overlay(RoundedRectangle(cornerRadius: Nocturne.Radius.large, style: .continuous)
                .strokeBorder(Nocturne.Neutral.n200, lineWidth: 1))
                .shadow(color: Nocturne.Neutral.n900.opacity(0.06), radius: 1.5, y: 1)
        case (.medium, true):
            overlay(RoundedRectangle(cornerRadius: Nocturne.Radius.large, style: .continuous)
                .strokeBorder(Nocturne.Neutral.n700, lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 9, y: 6)
        case (.medium, false):
            overlay(RoundedRectangle(cornerRadius: Nocturne.Radius.large, style: .continuous)
                .strokeBorder(Nocturne.Neutral.n200, lineWidth: 1))
                .shadow(color: Nocturne.Neutral.n900.opacity(0.08), radius: 9, y: 6)
        case (.large, true):
            shadow(color: .black.opacity(0.65), radius: 20, y: 16)
        case (.large, false):
            shadow(color: Nocturne.Neutral.n900.opacity(0.14), radius: 20, y: 16)
        }
    }
}

// MARK: - Hex

extension Color {
    /// Nocturne tokens are documented as hex, so they are written as hex.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}
