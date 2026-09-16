import SwiftUI
import FuelSmartCore

/// Three cards, no account, no permissions.
///
/// Skippable from the first screen — the whole point is to reach a comparison
/// quickly, so onboarding never blocks and never asks for everything up front.
struct OnboardingScreen: View {

    @Environment(AppModel.self) private var model
    @Environment(\.fsTheme) private var theme

    @State private var page = 0

    private let pages: [Page] = [
        Page(
            title: "Compare the cars you're actually considering",
            message: "Gasoline, diesel, hybrid, plug-in or electric — any two, side by side. Official efficiency data, your real prices.",
            points: [
                "Pick any two vehicles from official government data",
                "Use your real driving and energy costs",
                "See when each choice becomes cheaper — if it does",
            ]
        ),
        Page(
            title: "Your prices, not a guess",
            message: "FuelSmart never invents what a car costs. You enter what you'll actually pay — a negotiated price, a used listing, a private sale.",
            points: [
                "Efficiency comes from NRCan and the U.S. EPA",
                "Price is always yours to enter",
                "Rebates, trade-in and charger costs are optional",
            ]
        ),
        Page(
            title: "Nothing leaves your device",
            message: "No account, no tracking, no server. The vehicle database is stored on your device, so comparing works offline.",
            points: [
                "No sign-in, ever",
                "Comparisons are saved locally",
                "Only you decide when to share or export",
            ]
        ),
    ]

    private struct Page {
        let title: String
        let message: String
        let points: [String]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .font(FSFont.body)
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.top, 8)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

            footer
        }
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.text)
    }

    private func pageView(_ item: Page) -> some View {
        VStack(alignment: .leading, spacing: 34) {
            Spacer(minLength: 0)

            BrandMark(size: 72)

            VStack(alignment: .leading, spacing: 14) {
                Text(item.title)
                    .font(FSFont.display)
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.message)
                    .font(FSFont.body)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 18) {
                ForEach(item.points.indices, id: \.self) { index in
                    let point = item.points[index]
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.accentText)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(theme.accentSurface))
                        Text(point)
                            .font(FSFont.body)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private var footer: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == page ? theme.accentText : theme.strongBorder)
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)

            Button(page == pages.count - 1 ? "Start comparing" : "Continue") {
                if page == pages.count - 1 {
                    finish()
                } else {
                    withAnimation(FSMotion.valueChange) { page += 1 }
                }
            }
            .buttonStyle(FSPrimaryButtonStyle())

            Text("No account. Nothing leaves your device.")
                .font(FSFont.footnote)
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func finish() {
        model.settingsStore.update { $0.hasCompletedOnboarding = true }
    }
}

/// The FuelSmart mark: two cost trajectories meeting at a break-even point.
///
/// The mark *is* the chart — the one moment the whole product exists to find.
/// The accent stroke is the vehicle that starts behind and catches up; the
/// neutral stroke is the one that starts ahead; the dot is break-even and is the
/// only glow in the product outside a live chart marker.
struct BrandMark: View {
    var size: CGFloat = 56
    @Environment(\.fsTheme) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: theme.isDark
                            ? [Color(hex: 0x242636), Color(hex: 0x14161f)]
                            : [Nocturne.Neutral.n200, Nocturne.Neutral.n100],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            // Neutral stroke — starts ahead, rises slowly.
            Capsule()
                .fill(theme.seriesA)
                .frame(width: size * 0.78, height: max(size * 0.04, 1.5))
                .rotationEffect(.degrees(-24))
                .offset(y: size * 0.11)

            // Accent stroke — starts behind, climbs to meet it.
            Capsule()
                .fill(theme.accent)
                .frame(width: size * 0.78, height: max(size * 0.04, 1.5))
                .rotationEffect(.degrees(22))
                .offset(y: -size * 0.06)

            // Break-even.
            if size >= 40 {
                Circle()
                    .fill(theme.isDark ? Nocturne.Accent.a200 : Nocturne.Accent.a700)
                    .frame(width: size * 0.14, height: size * 0.14)
                    .shadow(color: theme.glow, radius: size * 0.2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .accessibilityHidden(true)
    }
}
