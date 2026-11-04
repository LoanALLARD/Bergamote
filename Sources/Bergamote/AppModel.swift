import BergamoteKit
import Foundation
import GRDB
import Observation

@MainActor
@Observable
final class AppModel {
    enum Filter: Hashable {
        case all
        case toReview
        case failed
        case docType(String)
    }

    struct Highlight: Equatable {
        var documentID: Int64
        var chunkID: Int64
        var page: Int?
        var bbox: NormalizedRect?
        var text: String
        /// Termes de la requête (lemmes et mots tels que tapés, sans accents) à surligner dans la page.
        var terms: [String]
    }

    private(set) var engine: BergamoteEngine?
    private(set) var startupError: String?
    private(set) var documents: [Document] = []
    private(set) var results: [SearchHit] = []
    private(set) var isSearching = false
    private(set) var pauseReason: String?
    private(set) var lastImportMessage: String?

    var filter: Filter = .all
    var selectedDocumentID: Int64?
    var highlight: Highlight?
    var query = ""
    var isPaletteVisible = false
    var isImporterVisible = false

    /// Le camembert (menu circulaire) : créé avec le moteur, surveillance lancée par l'app.
    @ObservationIgnored private(set) var radialMenu: RadialMenuController?
    /// Dossiers où le camembert peut écrire ses résultats (à côté des originaux).
    let folderAccess = FolderAccessStore()
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// Fichiers reçus (« Ouvrir avec », dépôt sur l'icône du Dock) avant que le moteur soit prêt.
    @ObservationIgnored private var pendingImports: [URL] = []

    var visibleDocuments: [Document] {
        switch filter {
        case .all: documents
        case .toReview: documents.filter { $0.docTypeSource == .suggested || ($0.status == .ready && $0.docType == nil) }
        case .failed: documents.filter { $0.status == .failed }
        case .docType(let type): documents.filter { $0.docType == type }
        }
    }

    var selectedDocument: Document? {
        documents.first { $0.id == selectedDocumentID }
    }

    var inProgressCount: Int {
        documents.filter { [.queued, .extracting, .searchable, .enriching].contains($0.status) }.count
    }

    func start() async {
        guard engine == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let engine = try await BergamoteEngine.bootstrap(root: BergamoteEngine.defaultRoot())
            await engine.runner.start()
            attach(engine)
            radialMenu?.startMonitoring()
        } catch {
            startupError = error.localizedDescription
        }
    }

    /// Branche un moteur déjà démarré (utilisé aussi par les tests de rendu).
    func attach(_ engine: BergamoteEngine) {
        self.engine = engine
        radialMenu = RadialMenuController(engine: engine, folderAccess: folderAccess)
        observe(engine)
        if !pendingImports.isEmpty {
            let urls = pendingImports
            pendingImports = []
            importItems(urls)
        }
    }

    private func observe(_ engine: BergamoteEngine) {
        observation = Task { [weak self] in
            let documents = ValueObservation.tracking { db in
                try Document.order(Column("importedAt").desc).fetchAll(db)
            }
            do {
                for try await snapshot in documents.values(in: engine.database.reader) {
                    self?.documents = snapshot
                    self?.pauseReason = engine.runner.pauseReason
                }
            } catch {
                self?.startupError = error.localizedDescription
            }
        }
    }

    // MARK: Actions

    func importItems(_ urls: [URL]) {
        guard let engine else {
            pendingImports += urls
            return
        }
        Task {
            do {
                let report = try await engine.importItems(urls)
                var parts = ["\(report.added.count) ajouté(s)"]
                if report.duplicates > 0 { parts.append("\(report.duplicates) doublon(s)") }
                if !report.unsupported.isEmpty { parts.append("\(report.unsupported.count) non pris en charge") }
                if !report.failures.isEmpty { parts.append("\(report.failures.count) en erreur") }
                lastImportMessage = parts.joined(separator: " · ")
                if let first = report.added.first, selectedDocumentID == nil { selectedDocumentID = first }
            } catch {
                lastImportMessage = error.localizedDescription
            }
        }
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let query = query
        guard let engine, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))  // anti-rebond pendant la frappe
            guard !Task.isCancelled else { return }
            let hits = (try? await engine.search.search(query)) ?? []
            guard !Task.isCancelled else { return }
            results = hits
            isSearching = false
        }
    }

    func open(_ hit: SearchHit, query: String? = nil) {
        let query = query ?? self.query
        let normalizer = FrenchNormalizer()
        let typed = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { FrenchNormalizer.fold(String($0)) }
        var seen: Set<String> = []
        let terms = (normalizer.terms(query) + typed).filter { $0.count >= 3 && seen.insert($0).inserted }
        selectedDocumentID = hit.documentID
        highlight = Highlight(documentID: hit.documentID, chunkID: hit.chunkID, page: hit.page, bbox: hit.bbox, text: hit.snippet, terms: terms)
    }

    /// Faux tant qu'aucun modèle CamemBERT n'est installé : la recherche se fait alors par mots.
    var isSemanticSearchAvailable: Bool {
        engine?.embedder.isSemantic ?? false
    }

    func confirmDocType(_ docType: String?, for document: Document) {
        guard let engine, let id = document.id else { return }
        Task { try? await engine.confirmDocType(docType, for: id) }
    }

    func retry(_ document: Document) {
        guard let engine, let id = document.id else { return }
        try? engine.retry(id)
    }

    func delete(_ document: Document) {
        guard let engine, let id = document.id else { return }
        if selectedDocumentID == id { selectedDocumentID = nil }
        Task { try? await engine.delete(id) }
    }

    func fileURL(of document: Document) -> URL? {
        engine?.fileURL(of: document)
    }

    /// Ouvre le camembert sous le curseur pour un document de la bibliothèque.
    func showWheel(_ kind: WheelKind, for document: Document) {
        guard let url = fileURL(of: document) else { return }
        // Le fichier de la bibliothèque est une copie nommée par son empreinte : le résultat va à
        // côté du fichier importé, sous son nom.
        let original = document.originalPath.map { URL(fileURLWithPath: $0) }
        radialMenu?.present(kind, for: [url], besides: original.map { [$0] })
    }

    func label(forDocType id: String?) -> String? {
        guard let id else { return nil }
        return DocTypeDefinition.defaults.first { $0.id == id }?.label ?? id
    }
}
