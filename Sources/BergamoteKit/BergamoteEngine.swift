import Foundation
import GRDB
import os

/// Point d'entrée de l'app : assemble l'index, la bibliothèque, les modèles et les workers.
public final class BergamoteEngine: Sendable {
    public let database: AppDatabase
    public let library: DocumentLibrary
    public let embedder: any EmbeddingProvider
    public let classifier: DocTypeClassifier
    public let search: SearchService
    public let runner: PipelineRunner
    let queue: JobQueue
    let importer: DocumentImporter

    /// `~/Library/Application Support/Bergamote` (dans le conteneur de l'app si elle est sandboxée).
    public static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Bergamote", isDirectory: true)
    }

    /// - Parameters:
    ///   - root: dossier de données (index.sqlite, Library/, Models/).
    ///   - embedder: modèle imposé (tests) ; sinon le premier modèle Core ML trouvé dans
    ///     `$BERGAMOTE_MODELS_DIR` (développement), `root/Models`, puis les ressources de l'app,
    ///     à défaut `HashingEmbedder` (lexical).
    public static func bootstrap(
        root: URL,
        embedder: (any EmbeddingProvider)? = nil,
        bundledModels: URL? = Bundle.main.resourceURL?.appendingPathComponent("Models"),
        policy: IndexingPolicy = .init()
    ) async throws -> BergamoteEngine {
        let database = try AppDatabase.open(at: root.appendingPathComponent("index.sqlite"))
        let library = DocumentLibrary(root: root.appendingPathComponent("Library", isDirectory: true))
        let provider: any EmbeddingProvider
        if let embedder {
            provider = embedder
        } else {
            let developmentModels = ProcessInfo.processInfo.environment["BERGAMOTE_MODELS_DIR"].map(URL.init(fileURLWithPath:))
            provider = await makeEmbedder(searching: [developmentModels, root.appendingPathComponent("Models"), bundledModels].compactMap { $0 })
        }
        if try database.prepareVectorIndex(modelID: provider.modelID, dimension: provider.dimension) {
            Logger.pipeline.notice("Modèle d'embedding changé (\(provider.modelID, privacy: .public)) : ré-embedding programmé")
        }
        Logger.pipeline.notice("Démarrage : modèle \(provider.modelID, privacy: .public) (\(provider.dimension, privacy: .public) dimensions)")

        let engine = BergamoteEngine(database: database, library: library, embedder: provider, policy: policy)
        try await engine.loadClassifierExamples()
        return engine
    }

    private init(database: AppDatabase, library: DocumentLibrary, embedder: any EmbeddingProvider, policy: IndexingPolicy) {
        let queue = JobQueue(writer: database.writer)
        let classifier = DocTypeClassifier(embedder: embedder)
        let indexer = DocumentIndexer(
            database: database, library: library, queue: queue,
            extractor: NativeExtractor(), chunker: Chunker(), normalizer: FrenchNormalizer(),
            embedder: embedder, entityExtractor: EntityExtractor(), classifier: classifier)
        self.database = database
        self.library = library
        self.embedder = embedder
        self.classifier = classifier
        self.queue = queue
        self.importer = DocumentImporter(database: database, library: library, queue: queue)
        self.search = SearchService(database: database, embedder: embedder)
        self.runner = PipelineRunner(queue: queue, indexer: indexer, policy: policy)
    }

    static func makeEmbedder(searching directories: [URL]) async -> any EmbeddingProvider {
        let fileManager = FileManager.default
        for directory in directories {
            // Accepte un dossier de modèle, ou un dossier qui contient des dossiers de modèles.
            let children = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for candidate in [directory] + children.sorted(by: { $0.path < $1.path })
            where CoreMLSentenceEncoder.isModelDirectory(candidate) {
                do {
                    return try await CoreMLSentenceEncoder.load(from: candidate)
                } catch {
                    Logger.pipeline.error("Modèle Core ML ignoré (\(candidate.lastPathComponent, privacy: .public)) : \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        Logger.pipeline.notice("Aucun modèle Core ML : recherche par mots et classement par mots-clés")
        return HashingEmbedder()
    }

    // MARK: API pour l'interface

    public func importItems(_ urls: [URL]) async throws -> ImportReport {
        let report = try importer.importItems(urls)
        Logger.pipeline.notice("""
            Import : \(report.added.count, privacy: .public) ajouté(s), \(report.duplicates, privacy: .public) doublon(s), \
            \(report.unsupported.count, privacy: .public) non pris en charge, \(report.failures.count, privacy: .public) échec(s)
            """)
        for failure in report.failures {
            Logger.pipeline.error("Import impossible : \(failure.message)")
        }
        return report
    }

    /// Le type choisi par l'utilisateur devient un exemple pour le classifieur.
    public func confirmDocType(_ docType: String?, for documentID: Int64) async throws {
        let vector = try await database.writer.write { db -> [Float]? in
            try db.execute(
                sql: "UPDATE document SET docType = ?, docTypeConfidence = ?, docTypeSource = ? WHERE id = ?",
                arguments: [docType, docType == nil ? nil : 1.0, docType == nil ? nil : Document.DocTypeSource.user.rawValue, documentID])
            return try AppDatabase.documentVector(of: documentID, in: db)
        }
        if let docType, let vector {
            await classifier.setExample(documentID: documentID, docType: docType, vector: vector)
        } else {
            await classifier.removeExample(documentID: documentID)
        }
    }

    public func entities(of documentID: Int64) async throws -> [EntityRecord] {
        try await database.reader.read { db in
            try EntityRecord.filter(Column("documentId") == documentID).order(Column("kind"), Column("page")).fetchAll(db)
        }
    }

    public func chunks(of documentID: Int64) async throws -> [Chunk] {
        try await database.reader.read { db in
            try Chunk.filter(Column("documentId") == documentID).order(Column("position")).fetchAll(db)
        }
    }

    public func retry(_ documentID: Int64) throws {
        try queue.retry(documentID: documentID)
    }

    public func delete(_ documentID: Int64) async throws {
        let storedPath = try await database.writer.write { db -> String? in
            let path = try String.fetchOne(db, sql: "SELECT storedPath FROM document WHERE id = ?", arguments: [documentID])
            try AppDatabase.purgeChunks(of: documentID, in: db)
            try db.execute(sql: "DELETE FROM document WHERE id = ?", arguments: [documentID])
            return path
        }
        await classifier.removeExample(documentID: documentID)
        if let storedPath { library.remove(storedPath: storedPath) }
    }

    public func fileURL(of document: Document) -> URL {
        library.url(forStoredPath: document.storedPath)
    }

    private func loadClassifierExamples() async throws {
        let examples = try await database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT id, docType FROM document WHERE docTypeSource = 'user' AND docType IS NOT NULL")
                .compactMap { row -> (Int64, String, [Float])? in
                    let id: Int64 = row["id"]
                    guard let vector = try AppDatabase.documentVector(of: id, in: db) else { return nil }
                    return (id, row["docType"], vector)
                }
        }
        for (id, docType, vector) in examples {
            await classifier.setExample(documentID: id, docType: docType, vector: vector)
        }
    }
}
