import SwiftUI
import FuelSmartCore

/// A currency field.
///
/// Binds to an optional so "empty" and "zero" stay distinguishable — an
/// untouched insurance field means *unknown*, while a typed 0 means *nothing*,
/// and the result label depends on which the user meant.
struct FSMoneyField: View {
    let label: String
    var caption: String?
    @Binding var value: Double?
    var currencyCode: String
    var isProminent: Bool = false
    var isOptional: Bool = true

    @Environment(\.fsTheme) private var theme
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(label)
                    .font(FSFont.footnote)
                    .foregroundStyle(isProminent ? theme.accentMuted : theme.secondaryText)
                if isOptional {
                    Text("· optional")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.tertiaryText)
                }
            }

            HStack(spacing: 8) {
                Text("$")
                    .font(isProminent ? FSFont.figureMedium : FSFont.body)
                    .foregroundStyle(theme.secondaryText)

                TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.plain)
                    .font(isProminent ? FSFont.figure : FSFont.figureSmall)
                    .foregroundStyle(theme.text)
                    .focused($isFocused)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif

                Text(currencyCode)
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: isProminent ? 52 : Nocturne.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                    .fill(theme.inset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                    .strokeBorder(
                        isFocused || isProminent ? theme.accent : theme.border,
                        lineWidth: isFocused || isProminent ? 2 : 1
                    )
            )

            if let caption {
                Text(caption)
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

/// A plain number field with a trailing unit.
struct FSNumberField: View {
    let label: String
    var caption: String?
    @Binding var value: Double
    var unit: String
    var isProminent: Bool = false
    var fractionDigits: ClosedRange<Int> = 0...2
    /// Values outside this are almost certainly typos; the field says so rather
    /// than silently accepting them.
    var plausibleRange: ClosedRange<Double>?

    @Environment(\.fsTheme) private var theme
    @FocusState private var isFocused: Bool

    private var isImplausible: Bool {
        guard let plausibleRange else { return false }
        return !plausibleRange.contains(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(FSFont.footnote)
                .foregroundStyle(isImplausible ? theme.warning : (isProminent ? theme.accentMuted : theme.secondaryText))

            HStack(spacing: 8) {
                TextField("0", value: $value, format: .number.precision(.fractionLength(fractionDigits)))
                    .textFieldStyle(.plain)
                    .font(isProminent ? FSFont.figure : FSFont.figureSmall)
                    .foregroundStyle(theme.text)
                    .focused($isFocused)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif

                Text(unit)
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: isProminent ? 52 : Nocturne.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                    .fill(theme.inset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                    .strokeBorder(borderColour, lineWidth: isFocused || isProminent || isImplausible ? 2 : 1)
            )

            if isImplausible, let plausibleRange {
                Label(
                    "Expected between \(Int(plausibleRange.lowerBound).formatted()) and \(Int(plausibleRange.upperBound).formatted()) \(unit).",
                    systemImage: "exclamationmark.circle"
                )
                .font(FSFont.footnote)
                .foregroundStyle(theme.warning)
            } else if let caption {
                Text(caption)
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(value.formatted()) \(unit)")
    }

    private var borderColour: Color {
        if isImplausible { return theme.warning }
        if isFocused || isProminent { return theme.accent }
        return theme.border
    }
}

/// A labelled row that discloses an optional value, matching the design's
/// "Add" / value pattern inside a card.
struct FSDisclosureRow<Content: View>: View {
    let label: String
    let value: String?
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    @Environment(\.fsTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(FSMotion.valueChange) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(label)
                        .font(FSFont.body)
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text(value ?? "Add")
                        .font(FSFont.figureSmall)
                        .foregroundStyle(value == nil ? theme.tertiaryText : theme.text)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(theme.tertiaryText)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Collapses" : "Expands")

            if isExpanded {
                content
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                .fill(theme.inset)
        )
    }
}

/// A toggle row in the Nocturne style.
struct FSToggleRow: View {
    let title: String
    var caption: String?
    @Binding var isOn: Bool

    @Environment(\.fsTheme) private var theme

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(FSFont.body).foregroundStyle(theme.text)
                if let caption {
                    Text(caption).font(FSFont.footnote).foregroundStyle(theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(theme.accent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
