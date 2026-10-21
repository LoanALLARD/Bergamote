import BergamoteKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } content: {
            Group {
                if model.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    DocumentListView()
                } else {
                    SearchResultsView()
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        } detail: {
            if let document = model.selectedDocument {
                DocumentDetailView(document: document)
            } else if let error = model.startupError {
                ContentUnavailableView("Démarrage impossible", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ContentUnavailableView(
                    "Aucun document sélectionné", systemImage: "doc.text.magnifyingglass",
                    description: Text("Déposez des fichiers ou un dossier ici, ou appuyez sur ⌘O."))
            }
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "Rechercher dans vos documents")
        .onChange(of: model.query) { model.scheduleSearch() }
        .dropDestination(for: URL.self) { urls, _ in
            model.importItems(urls)
            return true
        }
        .fileImporter(
            isPresented: $model.isImporterVisible,
            allowedContentTypes: DocumentLibrary.supportedTypes + [.folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.importItems(urls) }
        }
        .sheet(isPresented: $model.isPaletteVisible) {
            CommandPalette()
        }
        .toolbar {
            ToolbarItem(placement: .status) { IndexingStatusView() }
            ToolbarItem {
                Button("Importer", systemImage: "plus") { model.isImporterVisible = true }
            }
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.filter) {
            Section("Bibliothèque") {
                Label("Tous les documents", systemImage: "tray.full").tag(AppModel.Filter.all)
                Label("À vérifier", systemImage: "checkmark.seal").tag(AppModel.Filter.toReview)
                Label("En échec", systemImage: "exclamationmark.triangle").tag(AppModel.Filter.failed)
            }
            Section("Types") {
                ForEach(DocTypeDefinition.defaults) { definition in
                    Label(definition.label, systemImage: "doc.text").tag(AppModel.Filter.docType(definition.id))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.engine != nil && !model.isSemanticSearchAvailable {
                Label("Recherche par mots. Installez le modèle CamemBERT pour chercher aussi par le sens.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
    }
}

struct DocumentListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedDocumentID) {
            ForEach(model.visibleDocuments) { document in
                DocumentRow(document: document).tag(document.id ?? -1)
            }
        }
        .overlay {
            if model.visibleDocuments.isEmpty {
                ContentUnavailableView("Rien ici", systemImage: "tray", description: Text("Glissez des PDF, images ou documents Word dans la fenêtre."))
            }
        }
        .onChange(of: model.selectedDocumentID) { model.highlight = nil }
    }
}

struct DocumentRow: View {
    @Environment(AppModel.self) private var model
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.title).font(.headline).lineLimit(1)
            HStack(spacing: 6) {
                if let label = model.label(forDocType: document.docType) {
                    Text(document.docTypeSource == .suggested ? "\(label) ?" : label)
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.tint.opacity(document.docTypeSource == .suggested ? 0.1 : 0.2), in: Capsule())
                }
                StatusBadge(status: document.status)
                Spacer()
                Text(document.importedAt, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let status: Document.Status

    var body: some View {
        switch status {
        case .ready: EmptyView()
        case .failed: Label("Échec", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
        case .searchable, .enriching: Label("Analyse…", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
        case .queued, .extracting: Label("Lecture…", systemImage: "doc.viewfinder").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SearchResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // La sélection suit le passage ouvert, y compris depuis la palette ⌘K.
        let selection = Binding<SearchHit.ID?>(
            get: { model.highlight?.chunkID },
            set: { id in
                if let hit = model.results.first(where: { $0.id == id }) { model.open(hit) }
            })
        List(model.results, selection: selection) { hit in
            SearchHitRow(hit: hit)
        }
        .overlay {
            if model.results.isEmpty && !model.isSearching {
                ContentUnavailableView.search(text: model.query)
            }
        }
    }
}

struct SearchHitRow: View {
    @Environment(AppModel.self) private var model
    let hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(hit.title).font(.headline).lineLimit(1)
                Spacer()
                if let page = hit.page { Text("p. \(page)").font(.caption).foregroundStyle(.secondary) }
            }
            Text(hit.snippet).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            HStack(spacing: 8) {
                if let label = model.label(forDocType: hit.docType) { Text(label).font(.caption2) }
                if hit.matchedLexically { Label("mots", systemImage: "textformat").font(.caption2).foregroundStyle(.secondary) }
                if hit.matchedSemantically { Label("sens", systemImage: "sparkles").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 2)
    }
}

struct IndexingStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            if model.inProgressCount > 0 {
                ProgressView().controlSize(.small)
                Text("\(model.inProgressCount) en cours").font(.callout)
            }
            if let reason = model.pauseReason {
                Label("Analyse en pause : \(reason)", systemImage: "pause.circle").font(.callout)
            }
            if let message = model.lastImportMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
