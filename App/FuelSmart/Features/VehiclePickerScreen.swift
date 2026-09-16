import SwiftUI
import SwiftData
import FuelSmartCore

/// Country → Year → Make → Model → Configuration, plus full search.
///
/// Browsing is served entirely from the small catalog file, so drilling down
/// never touches the multi-megabyte records file. Search is served from a prefix
/// index built once, so typing does not rescan the database per keystroke.
struct VehiclePickerScreen: View {

    let region: Region
    var onSelect: (Vehicle) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.fsTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \VehicleBookmarkEntity.lastUsed, order: .reverse)
    private var bookmarks: [VehicleBookmarkEntity]

    @State private var catalog: VehicleCatalog?
    @State private var loadError: String?

    @State private var searchText = ""
    @State private var results: [Vehicle] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    @State private var powertrainFilter: Set<Powertrain> = []
    @State private var showingVIN = false

    private var repository: any VehicleRepository { model.repository(for: region) }

    var body: some View {
        Group {
            if let loadError {
                loadFailure(loadError)
            } else if let catalog {
                list(catalog)
            } else {
                loading
            }
        }
        .background(theme.background)
        .navigationTitle("Choose a vehicle")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .searchable(text: $searchText, prompt: searchPrompt)
        .onChange(of: searchText) { _, query in scheduleSearch(query) }
        .sheet(isPresented: $showingVIN) {
            NavigationStack {
                VINLookupScreen(region: region) { vehicle in
                    showingVIN = false
                    choose(vehicle)
                }
            }
            .fsTheme(theme)
        }
        .task { await load() }
    }

    private var searchPrompt: String {
        guard let catalog else { return "Search vehicles" }
        let total = catalog.years.reduce(0) { $0 + $1.count }
        return "Search \(total.formatted()) vehicles"
    }

    // MARK: - States

    private var loading: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                FSSkeleton(height: 44)
            }
        }
        .padding(Nocturne.Space.gutter)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityLabel("Loading vehicle database")
    }

    private func loadFailure(_ message: String) -> some View {
        VStack {
            FSNoticeCard(
                severity: .warning,
                systemImage: "exclamationmark.triangle",
                title: "Vehicle database unavailable",
                message: message,
                actions: [("Try again", { Task { await load(force: true) } })]
            )
        }
        .padding(Nocturne.Space.gutter)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - List

    @ViewBuilder
    private func list(_ catalog: VehicleCatalog) -> some View {
        List {
            if searchText.isEmpty {
                if !powertrainFilter.isEmpty || !bookmarks.isEmpty {
                    Section { filterRow } header: { Text("Filter") }
                }
                if !recentVehicles.isEmpty {
                    Section("Recent") {
                        ForEach(recentVehicles, id: \.vehicleId) { bookmark in
                            Button(bookmark.displayName) { Task { await openBookmark(bookmark) } }
                                .foregroundStyle(theme.text)
                        }
                    }
                }
                if !favouriteVehicles.isEmpty {
                    Section("Favourites") {
                        ForEach(favouriteVehicles, id: \.vehicleId) { bookmark in
                            Button(bookmark.displayName) { Task { await openBookmark(bookmark) } }
                                .foregroundStyle(theme.text)
                        }
                    }
                }
                Section("Browse by year") {
                    ForEach(catalog.years) { year in
                        NavigationLink {
                            makeList(year: year)
                        } label: {
                            LabeledContent(String(year.year)) {
                                Text(year.count.formatted()).foregroundStyle(theme.tertiaryText)
                            }
                        }
                    }
                }
            } else {
                searchResults
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .safeAreaInset(edge: .bottom) {
            Button {
                showingVIN = true
            } label: {
                Label("Scan or enter VIN", systemImage: "barcode.viewfinder")
            }
            .buttonStyle(FSGhostButtonStyle())
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Powertrain.allCases.filter { $0 != .other }, id: \.self) { powertrain in
                    let isOn = powertrainFilter.contains(powertrain)
                    Button {
                        if isOn { powertrainFilter.remove(powertrain) } else { powertrainFilter.insert(powertrain) }
                        scheduleSearch(searchText)
                    } label: {
                        FSTag(text: powertrain.displayName, style: isOn ? .accent : .outline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }

    @ViewBuilder
    private var searchResults: some View {
        if isSearching {
            Section { ForEach(0..<4, id: \.self) { _ in FSSkeleton(height: 40) } }
        } else if results.isEmpty {
            Section {
                FSEmptyState(
                    systemImage: "magnifyingglass",
                    title: "No vehicles match “\(searchText)”",
                    message: "Check the spelling, or browse by year and make.",
                    actionTitle: "Clear search",
                    action: { searchText = "" }
                )
                .listRowBackground(Color.clear)
            }
        } else {
            Section("\(results.count) result\(results.count == 1 ? "" : "s")") {
                ForEach(results) { vehicle in
                    NavigationLink {
                        VehicleDetailScreen(vehicle: vehicle, region: region, onUse: choose)
                    } label: {
                        VehicleRow(vehicle: vehicle, formatter: model.formatter)
                    }
                }
            }
        }
    }

    private func makeList(year: VehicleCatalog.YearNode) -> some View {
        List(year.makes) { make in
            NavigationLink {
                modelList(year: year.year, make: make)
            } label: {
                LabeledContent(make.make) {
                    Text(make.count.formatted()).foregroundStyle(theme.tertiaryText)
                }
            }
        }
        .navigationTitle(String(year.year))
        .scrollContentBackground(.hidden)
        .background(theme.background)
    }

    private func modelList(year: Int, make: VehicleCatalog.MakeNode) -> some View {
        List(make.models) { node in
            NavigationLink {
                ConfigurationList(
                    region: region, year: year, make: make.make, model: node.model, onSelect: choose
                )
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.model).foregroundStyle(theme.text)
                    if !node.resolvedPowertrains.isEmpty {
                        Text(node.resolvedPowertrains.map(\.displayName).joined(separator: " · "))
                            .font(FSFont.footnote)
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
            }
        }
        .navigationTitle(make.make)
        .scrollContentBackground(.hidden)
        .background(theme.background)
    }

    // MARK: - Bookmarks

    private var recentVehicles: [VehicleBookmarkEntity] {
        bookmarks.filter { $0.region == region && !$0.isFavourite }.prefix(4).map { $0 }
    }

    private var favouriteVehicles: [VehicleBookmarkEntity] {
        bookmarks.filter { $0.region == region && $0.isFavourite }
    }

    private func openBookmark(_ bookmark: VehicleBookmarkEntity) async {
        if let vehicle = try? await repository.vehicle(id: bookmark.vehicleId) {
            choose(vehicle)
        }
    }

    // MARK: - Actions

    private func choose(_ vehicle: Vehicle) {
        recordUse(of: vehicle)
        onSelect(vehicle)
    }

    /// Remember what the user picked, so the next comparison starts faster.
    private func recordUse(of vehicle: Vehicle) {
        let id = vehicle.id
        let descriptor = FetchDescriptor<VehicleBookmarkEntity>(
            predicate: #Predicate { $0.vehicleId == id }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.lastUsed = Date()
        } else {
            context.insert(VehicleBookmarkEntity(vehicle: vehicle, isFavourite: false))
        }
        try? context.save()
    }

    private func load(force: Bool = false) async {
        if catalog != nil && !force { return }
        do {
            catalog = try await repository.catalog()
            loadError = nil
        } catch {
            loadError = (error as? VehicleRepositoryError)?.message ?? error.localizedDescription
        }
    }

    /// Debounced search.
    ///
    /// Each keystroke cancels the previous task, so a fast typist triggers one
    /// query rather than one per character, and the index is never asked for a
    /// result the user has already moved past.
    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let filter = VehicleFilter(powertrains: powertrainFilter)
            let found = (try? await repository.search(trimmed, filter: filter, limit: 60)) ?? []
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }
}

/// The final picker step: every configuration of one model.
private struct ConfigurationList: View {
    let region: Region
    let year: Int
    let make: String
    let model: String
    var onSelect: (Vehicle) -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.fsTheme) private var theme
    @State private var vehicles: [Vehicle] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ForEach(0..<3, id: \.self) { _ in FSSkeleton(height: 40) }
            } else if vehicles.isEmpty {
                FSEmptyState(
                    systemImage: "car.side",
                    title: "No configurations listed",
                    message: "The dataset doesn't list a rated configuration for this model."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(vehicles) { vehicle in
                    NavigationLink {
                        VehicleDetailScreen(vehicle: vehicle, region: region, onUse: onSelect)
                    } label: {
                        VehicleRow(vehicle: vehicle, formatter: appModel.formatter)
                    }
                }
            }
        }
        .navigationTitle(model)
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .task {
            vehicles = (try? await appModel.repository(for: region)
                .configurations(year: year, make: make, model: model)) ?? []
            isLoading = false
        }
    }
}

/// One vehicle in a list.
struct VehicleRow: View {
    let vehicle: Vehicle
    let formatter: ValueFormatter

    @Environment(\.fsTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Nocturne.Radius.medium, style: .continuous)
                .fill(vehicle.powertrain.usesElectricity ? theme.accentSurface : theme.inset)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: vehicle.powertrain.usesElectricity ? "bolt.car" : "car.side")
                        .font(.footnote)
                        .foregroundStyle(vehicle.powertrain.usesElectricity ? theme.accentText : theme.secondaryText)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.fullDisplayName)
                    .font(FSFont.bodyMedium)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(detail)
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vehicle.fullDisplayName). \(detail)")
    }

    private var detail: String {
        var parts = [vehicle.powertrain.displayName, formatter.consumption(for: vehicle)]
        if let range = vehicle.efficiency.electricRangeKm, vehicle.powertrain.usesElectricity {
            parts.append(formatter.distance(range) + " range")
        }
        return parts.filter { $0 != "—" }.joined(separator: " · ")
    }
}
