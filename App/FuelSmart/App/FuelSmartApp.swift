import SwiftUI
import SwiftData
import FuelSmartCore

@main
struct FuelSmartApp: App {

    @State private var model = AppModel()
    private let container = PersistenceController.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(model.preferredColorScheme)
                .task { await model.loadManifest() }
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1080, height: 700)
        .commands { FuelSmartCommands() }
        #endif

        #if os(macOS)
        Settings {
            SettingsScreen()
                .environment(model)
                .modelContainer(container)
                .frame(width: 520, height: 560)
        }
        #endif
    }
}

/// The four areas of the app, as defined by the design reference.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home, compare, saved, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .compare: "Compare"
        case .saved: "Saved"
        case .settings: "Settings"
        }
    }

    /// SF Symbols chosen to match the reference's Phosphor icons in meaning.
    var systemImage: String {
        switch self {
        case .home: "house"
        case .compare: "scalemass"
        case .saved: "bookmark"
        case .settings: "slider.horizontal.3"
        }
    }
}

/// Chooses the navigation shape for the current size class.
///
/// iPhone gets a tab bar over navigation stacks; iPad and macOS get a sidebar
/// split view. One set of screens serves both — the difference is the container,
/// not three separate applications.
struct RootView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // Optional because `List(_:selection:rowContent:)` with a non-optional
    // binding is macOS-only; a sidebar selection is conventionally optional
    // anyway, since nothing need be selected.
    @State private var selection: AppSection? = .home

    /// TabView wants a non-optional selection, so the optional is bridged here
    /// rather than keeping two pieces of state that could disagree.
    private var tabSelection: Binding<AppSection> {
        Binding(get: { selection ?? .home }, set: { selection = $0 })
    }

    private var theme: FSTheme { model.theme(for: colorScheme) }

    /// macOS windows are never compact, so the wide layout always applies there.
    private var isWideLayout: Bool {
        #if os(iOS)
        horizontalSizeClass != .compact
        #else
        true
        #endif
    }

    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                tabs
            } else {
                splitView
            }
            #else
            splitView
            #endif
        }
        .fsTheme(theme)
        .environment(\.fsIsWideLayout, isWideLayout)
        .tint(theme.accent)
        .background(theme.background)
        .fullScreenCoverIfNeeded(isPresented: !model.settings.hasCompletedOnboarding) {
            OnboardingScreen()
                .fsTheme(theme)
        }
    }

    // MARK: - iPhone

    private var tabs: some View {
        TabView(selection: tabSelection) {
            ForEach(AppSection.allCases) { section in
                NavigationStack {
                    screen(for: section)
                }
                .tabItem {
                    Label(section.title, systemImage: section.systemImage)
                }
                .tag(section)
            }
        }
    }

    // MARK: - iPad and macOS

    private var splitView: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.systemImage)
                }
                .listRowBackground(
                    section == selection
                        ? RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.accentSurface)
                        : RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.clear)
                )
            }
            .navigationTitle("FuelSmart")
            #if os(macOS)
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 228, max: 280)
            #endif
        } detail: {
            NavigationStack {
                screen(for: selection ?? .home)
            }
        }
    }

    @ViewBuilder
    private func screen(for section: AppSection) -> some View {
        switch section {
        case .home: HomeScreen(onStartComparison: { selection = .compare })
        case .compare: CompareScreen()
        case .saved: SavedScreen()
        case .settings: SettingsScreen()
        }
    }
}

// MARK: - Platform helpers

private extension View {
    /// `fullScreenCover` does not exist on macOS, where a sheet is the right
    /// presentation for onboarding anyway.
    @ViewBuilder
    func fullScreenCoverIfNeeded<Content: View>(
        isPresented: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        sheet(isPresented: .constant(isPresented), content: content)
        #else
        fullScreenCover(isPresented: .constant(isPresented), content: content)
        #endif
    }
}

#if os(macOS)
/// Keyboard-accessible menu commands, so the Mac build is navigable without a
/// pointer.
struct FuelSmartCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Comparison") {
                NotificationCenter.default.post(name: .fsNewComparison, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

extension Notification.Name {
    static let fsNewComparison = Notification.Name("fsNewComparison")
}
#endif
