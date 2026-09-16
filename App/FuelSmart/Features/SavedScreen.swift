import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import FuelSmartCore

/// The local library of saved comparisons.
///
/// Everything here stays on the device. Rows render from denormalised columns,
/// so listing never decodes a stored scenario.
struct SavedScreen: View {

    @Environment(AppModel.self) private var model
    @Environment(\.fsTheme) private var theme
    @Environment(\.modelContext) private var context

    @Query(sort: \SavedComparisonEntity.dateModified, order: .reverse)
    private var comparisons: [SavedComparisonEntity]

    @State private var searchText = ""
    @State private var sortOrder: SavedComparison.SortOrder = .dateModified
    @State private var renaming: SavedComparisonEntity?
    @State private var renameText = ""
    @State private var pendingDelete: SavedComparisonEntity?
    @State private var route: CompareRoute?

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDocument: ComparisonExportDocument?
    @State private var importMessage: String?

    private var filtered: [SavedComparisonEntity] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty
            ? comparisons
            : comparisons.filter {
                [$0.name, $0.subtitle, $0.mode.displayName]
                    .joined(separator: " ")
                    .range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }

        return switch sortOrder {
        case .dateModified: matching.sorted { $0.dateModified > $1.dateModified }
        case .dateCreated: matching.sorted { $0.dateCreated > $1.dateCreated }
        case .name: matching.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        Group {
            if comparisons.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(theme.background)
        .navigationTitle("Saved")
        .searchable(text: $searchText, prompt: "Search comparisons")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SavedComparison.SortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                    Divider()
                    Button("Export all…", systemImage: "square.and.arrow.up") { exportAll() }
                        .disabled(comparisons.isEmpty)
                    Button("Import…", systemImage: "square.and.arrow.down") { isImporting = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Sort and file options")
            }
        }
        .navigationDestination(item: $route) { route in
            CompareScreen(initialMode: route.mode, editing: route.saved)
        }
        .alert("Rename comparison", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") { commitRename() }
        }
        .alert("Delete this comparison?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) { confirmDelete() }
        } message: {
            Text("This removes it from this device. It cannot be undone.")
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportDocument?.suggestedName ?? "FuelSmart-export"
        ) { result in
            if case .failure(let error) = result {
                importMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .overlay(alignment: .bottom) { toast }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 11) {
                if filtered.isEmpty {
                    FSEmptyState(
                        systemImage: "magnifyingglass",
                        title: "No comparisons match “\(searchText)”",
                        message: "Try a different name, or clear the search.",
                        actionTitle: "Clear search",
                        action: { searchText = "" }
                    )
                    .padding(.top, 20)
                } else {
                    ForEach(filtered) { entity in
                        Button { open(entity) } label: {
                            SavedComparisonCard(entity: entity, showsModeTag: true)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { rowMenu(entity) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { pendingDelete = entity } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func rowMenu(_ entity: SavedComparisonEntity) -> some View {
        Button("Open", systemImage: "arrow.up.right.square") { open(entity) }
        Button("Rename", systemImage: "pencil") {
            renameText = entity.name
            renaming = entity
        }
        Button("Duplicate", systemImage: "doc.on.doc") { duplicate(entity) }
        Button("Export…", systemImage: "square.and.arrow.up") { export([entity]) }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = entity }
    }

    private var emptyState: some View {
        VStack {
            FSEmptyState(
                systemImage: "bookmark",
                title: "Nothing saved yet",
                message: "Comparisons you save stay on this device. Start one and it will appear here.",
                actionTitle: "Compare vehicles",
                action: { route = CompareRoute(mode: .buyVsBuy, saved: nil) }
            )
            Button("Import a FuelSmart file") { isImporting = true }
                .buttonStyle(FSGhostButtonStyle())
                .padding(.top, 8)
        }
        .padding(.horizontal, Nocturne.Space.gutter)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func open(_ entity: SavedComparisonEntity) {
        do {
            let saved = try entity.toSavedComparison()
            route = CompareRoute(mode: saved.scenario.mode, saved: saved)
        } catch {
            importMessage = "That comparison couldn't be opened — it may have been written by a newer version."
        }
    }

    private func duplicate(_ entity: SavedComparisonEntity) {
        guard let saved = try? entity.toSavedComparison() else { return }
        if let copy = try? SavedComparisonEntity(saved: saved.duplicated()) {
            context.insert(copy)
            try? context.save()
        }
    }

    private func commitRename() {
        guard let renaming else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            renaming.name = trimmed
            renaming.dateModified = Date()
            try? context.save()
        }
        self.renaming = nil
    }

    private func confirmDelete() {
        guard let pendingDelete else { return }
        context.delete(pendingDelete)
        try? context.save()
        self.pendingDelete = nil
    }

    // MARK: - Export and import

    private func exportAll() { export(comparisons) }

    private func export(_ entities: [SavedComparisonEntity]) {
        let saved = entities.compactMap { try? $0.toSavedComparison() }
        guard !saved.isEmpty else {
            importMessage = "Nothing could be exported."
            return
        }
        do {
            let data = try ComparisonExporter.encode(saved, appVersion: Bundle.main.appVersion)
            exportDocument = ComparisonExportDocument(
                data: data,
                suggestedName: ComparisonExporter.suggestedFilename(for: saved)
            )
            isExporting = true
        } catch {
            importMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importMessage = "Import failed: \(error.localizedDescription)"

        case .success(let urls):
            guard let url = urls.first else { return }
            // A file chosen through the picker lives outside the sandbox, so
            // access must be requested explicitly and released afterwards.
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                let imported = try ComparisonImporter.decode(data)
                var added = 0
                for item in imported {
                    // A fresh id on import, so importing a file twice does not
                    // silently overwrite the copy already on the device.
                    let copy = SavedComparison(
                        id: UUID(), name: item.name, scenario: item.scenario,
                        dateCreated: item.dateCreated, dateModified: Date()
                    )
                    if let entity = try? SavedComparisonEntity(saved: copy) {
                        context.insert(entity)
                        added += 1
                    }
                }
                try context.save()
                importMessage = "Imported \(added) comparison\(added == 1 ? "" : "s")."
            } catch let error as ImportError {
                importMessage = error.message
            } catch {
                importMessage = "That file couldn't be read."
            }
        }
        dismissToast()
    }

    @ViewBuilder
    private var toast: some View {
        if let importMessage {
            Text(importMessage)
                .font(FSFont.footnote)
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.surface))
                .fsElevation(.medium, theme: theme)
                .padding(.horizontal, Nocturne.Space.gutter)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func dismissToast() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(FSMotion.valueChange) { importMessage = nil }
        }
    }
}

/// A `FileDocument` wrapper so export can use the system save panel.
struct ComparisonExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data
    let suggestedName: String

    init(data: Data, suggestedName: String) {
        self.data = data
        self.suggestedName = suggestedName
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        suggestedName = "FuelSmart-export"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension Bundle {
    var appVersion: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
