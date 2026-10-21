import Foundation
import GRDB
import os
import UniformTypeIdentifiers

public enum PipelineError: Error, LocalizedError {
    case timeout(Duration)

    public var errorDescription: String? {
        switch self {
        case .timeout(let duration): "Extraction interrompue après \(duration)"
        }
    }
}

/// Exécute les deux phases d'indexation d'un document.
struct DocumentIndexer: Sendable {
    let database: AppDatabase
    let library: DocumentLibrary
    let queue: JobQueue
    let extractor: any DocumentExtracting
    let chunker: Chunker
    let normalizer: FrenchNormalizer
    let embedder: any EmbeddingProvider
    let entityExtractor: EntityExtractor
    let classifier: DocTypeClassifier
    var extractionTimeout: Duration = .seconds(120)
    var embeddingBatchSize = 16

    func process(_ job: Job) async throws {
        switch job.stage {
        case .extract: try await extract(job)
        case .enrich: try await enrich(job)
        }
    }

    // MARK: Phase 1 — extraction, découpage, plein texte

    private func extract(_ job: Job) async throws {
        let started = Date()
        let documentID = job.documentId
        guard let document = try await fetchDocument(documentID) else {
            try queue.complete(job)
            return
        }
        try await setStatus(.extracting, of: documentID)

        let url = library.url(forStoredPath: document.storedPath)
        let type = UTType(document.contentType) ?? .data
        let extractor = extractor
        let extracted = try await withTimeout(extractionTimeout) {
            try await extractor.extract(url, contentType: type)
        }
        let drafts = chunker.chunk(extracted)
        let lemmas = drafts.map { normalizer.indexText($0.content) }

        try await database.writer.write { [queue] db in
            try AppDatabase.purgeChunks(of: documentID, in: db)
            for (position, (draft, lemma)) in zip(drafts, lemmas).enumerated() {
                var chunk = Chunk(documentId: documentID, position: position, page: draft.page, bbox: draft.bbox, content: draft.content)
                try chunk.insert(db)
                try db.execute(sql: "INSERT INTO chunk_fts(rowid, lemmas) VALUES (?, ?)", arguments: [chunk.id, lemma])
            }
            try db.execute(
                sql: "UPDATE document SET status = 'searchable', pageCount = ?, lastError = NULL WHERE id = ?",
                arguments: [extracted.pages.count, documentID])
            try queue.enqueue(.enrich, documentID: documentID, priority: 0, in: db)
            try queue.complete(job, in: db)
        }
        let ocrPages = extracted.pages.filter(\.usedOCR).count
        Logger.pipeline.notice("""
            Document \(documentID, privacy: .public) cherchable : \(extracted.pages.count, privacy: .public) page(s) \
            dont \(ocrPages, privacy: .public) en OCR, \(drafts.count, privacy: .public) passage(s), \(Self.milliseconds(since: started), privacy: .public) ms
            """)
    }

    static func milliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    // MARK: Phase 2 — embeddings, entités, type de document

    private func enrich(_ job: Job) async throws {
        let started = Date()
        let documentID = job.documentId
        let chunks = try await database.reader.read { db in
            try Chunk.filter(Column("documentId") == documentID).order(Column("position")).fetchAll(db)
        }
        guard try await fetchDocument(documentID) != nil else {
            try queue.complete(job)
            return
        }
        try await setStatus(.enriching, of: documentID)

        var vectors: [[Float]] = []
        for start in stride(from: 0, to: chunks.count, by: embeddingBatchSize) {
            try Task.checkCancellation()
            let batch = chunks[start..<min(start + embeddingBatchSize, chunks.count)].map(\.content)
            vectors += try await embedder.embed(batch, as: .passage)
        }

        let entities = EntityExtractor.deduplicated(chunks.flatMap { entityExtractor.extract(from: $0.content, page: $0.page) })
        var prediction: DocTypePrediction?
        if let documentVector = Embeddings.mean(Array(vectors.prefix(3))) {
            prediction = try await classifier.predict(documentVector)
        }

        try await database.writer.write { [queue, vectors, prediction] db in
            try AppDatabase.deleteVectors(chunkIDs: chunks.compactMap(\.id), in: db)
            for (chunk, vector) in zip(chunks, vectors) {
                try db.execute(
                    sql: "INSERT INTO chunk_vec(chunkId, embedding) VALUES (?, ?)",
                    arguments: [chunk.id, Embeddings.blob(vector)])
            }
            try db.execute(sql: "DELETE FROM entity WHERE documentId = ?", arguments: [documentID])
            for entity in entities {
                var record = EntityRecord(
                    documentId: documentID, kind: entity.kind, value: entity.value,
                    normalized: entity.normalized, confidence: entity.confidence, page: entity.page)
                try record.insert(db)
            }
            // Relecture dans la transaction : ne jamais écraser un type choisi par l'utilisateur
            // pendant que l'enrichissement tournait.
            guard var document = try Document.fetchOne(db, id: documentID) else { return }
            if document.docTypeSource != .user {
                switch prediction?.decision {
                case .automatic?, .suggested?:
                    document.docType = prediction?.docType
                    document.docTypeConfidence = prediction?.confidence
                    document.docTypeSource = prediction?.decision == .automatic ? .automatic : .suggested
                default:
                    document.docType = nil
                    document.docTypeConfidence = prediction?.confidence
                    document.docTypeSource = nil
                }
            }
            document.status = .ready
            document.indexedAt = Date()
            try document.update(db)
            try queue.complete(job, in: db)
        }
        let confidence = Int((prediction?.confidence ?? 0) * 100)
        Logger.pipeline.notice("""
            Document \(documentID, privacy: .public) prêt : type \(prediction?.docType ?? "–", privacy: .public) \
            (\(confidence, privacy: .public) %, \(prediction?.decision.rawValue ?? "–", privacy: .public)), \
            \(entities.count, privacy: .public) entité(s), \(vectors.count, privacy: .public) vecteur(s), \(Self.milliseconds(since: started), privacy: .public) ms
            """)
    }

    // MARK: Outils

    private func fetchDocument(_ id: Int64) async throws -> Document? {
        try await database.reader.read { db in try Document.fetchOne(db, id: id) }
    }

    private func setStatus(_ status: Document.Status, of id: Int64) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE document SET status = ? WHERE id = ?", arguments: [status.rawValue, id])
        }
    }
}

/// Exécute `operation` avec une limite de temps, et rend la main à l'échéance même si
/// l'opération ne coopère pas à l'annulation (PDFKit ne le fait pas).
/// L'opération abandonnée continue jusqu'à son terme : seule une isolation dans un service
/// XPC permet de la tuer réellement (voir README, « Prochaines étapes »).
func withTimeout<T: Sendable>(_ duration: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    let resumed = OSAllocatedUnfairLock(initialState: false)
    let claim: @Sendable () -> Bool = {
        resumed.withLock { done in
            defer { done = true }
            return !done
        }
    }
    return try await withCheckedThrowingContinuation { continuation in
        let work = Task {
            do {
                let value = try await operation()
                if claim() { continuation.resume(returning: value) }
            } catch {
                if claim() { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(for: duration)
            if claim() {
                work.cancel()
                continuation.resume(throwing: PipelineError.timeout(duration))
            }
        }
    }
}
