import Foundation
import GRDB
import os

public struct SearchHit: Identifiable, Hashable, Sendable {
    public var id: Int64 { chunkID }
    public let documentID: Int64
    public let chunkID: Int64
    public let title: String
    public let docType: String?
    public let page: Int?
    public let bbox: NormalizedRect?
    public let snippet: String
    public let score: Double
    public let matchedLexically: Bool
    public let matchedSemantically: Bool
}

/// Recherche hybride : BM25 (FTS5, texte lemmatisé) et KNN (sqlite-vec), fusionnés par
/// Reciprocal Rank Fusion. Un seul résultat par document, avec son meilleur passage.
public struct SearchService: Sendable {
    let database: AppDatabase
    let embedder: any EmbeddingProvider
    let normalizer = FrenchNormalizer()
    public var candidateCount = 50
    public var rrfK = 60.0
    /// Distance L2 maximale entre vecteurs normalisés (1,2 ≈ similarité cosinus > 0,28).
    /// Au-delà, un passage n'est pas proposé sur la seule base sémantique. À calibrer par modèle.
    public var maxSemanticDistance = 1.2

    public func search(_ query: String, limit: Int = 20, docType: String? = nil) async throws -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let ftsQuery = normalizer.ftsQuery(trimmed)
        let terms = normalizer.terms(trimmed)
        let started = Date()
        // Avec un embedding lexical, le KNN ne ferait que dupliquer BM25 en moins bien.
        let queryVector = embedder.isSemantic ? try await embedder.embed([trimmed], as: .query).first : nil
        let (candidateCount, rrfK, maxDistance) = (candidateCount, rrfK, maxSemanticDistance)

        let hits = try await database.reader.read { db -> [SearchHit] in
            var lexical: [Int64] = []
            if let ftsQuery {
                lexical = try Int64.fetchAll(
                    db,
                    sql: "SELECT rowid FROM chunk_fts WHERE chunk_fts MATCH ? ORDER BY bm25(chunk_fts) LIMIT ?",
                    arguments: [ftsQuery, candidateCount])
            }
            var semantic: [Int64] = []
            if let queryVector, try db.tableExists("chunk_vec") {
                semantic = try Row.fetchAll(
                    db,
                    sql: "SELECT chunkId, distance FROM chunk_vec WHERE embedding MATCH ? AND k = ?",
                    arguments: [Embeddings.blob(queryVector), candidateCount])
                    .filter { ($0["distance"] as Double) <= maxDistance }
                    .map { $0["chunkId"] }
            }

            var scores: [Int64: (score: Double, lexical: Bool, semantic: Bool)] = [:]
            for (rank, id) in lexical.enumerated() {
                scores[id, default: (0, false, false)].score += 1 / (rrfK + Double(rank + 1))
                scores[id]?.lexical = true
            }
            for (rank, id) in semantic.enumerated() {
                scores[id, default: (0, false, false)].score += 1 / (rrfK + Double(rank + 1))
                scores[id]?.semantic = true
            }
            guard !scores.isEmpty else { return [] }

            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT chunk.id, chunk.documentId, chunk.page, chunk.bbox, chunk.content, document.title, document.docType
                    FROM chunk JOIN document ON document.id = chunk.documentId
                    WHERE chunk.id IN (\(databaseQuestionMarks(count: scores.count)))
                    """,
                arguments: StatementArguments(Array(scores.keys)))

            var bestPerDocument: [Int64: SearchHit] = [:]
            for row in rows {
                let chunkID: Int64 = row["id"]
                let documentID: Int64 = row["documentId"]
                let rowDocType: String? = row["docType"]
                guard let entry = scores[chunkID], docType == nil || rowDocType == docType else { continue }
                if let current = bestPerDocument[documentID], current.score >= entry.score { continue }
                let bboxJSON: String? = row["bbox"]
                bestPerDocument[documentID] = SearchHit(
                    documentID: documentID, chunkID: chunkID, title: row["title"], docType: rowDocType,
                    page: row["page"],
                    bbox: bboxJSON.flatMap { try? JSONDecoder().decode(NormalizedRect.self, from: Data($0.utf8)) },
                    snippet: Snippet.make(from: row["content"], terms: terms),
                    score: entry.score, matchedLexically: entry.lexical, matchedSemantically: entry.semantic)
            }
            return bestPerDocument.values.sorted { $0.score > $1.score }.prefix(limit).map { $0 }
        }
        // La requête elle-même n'est pas journalisée : elle peut contenir des données personnelles.
        Logger.pipeline.notice("""
            Recherche : \(hits.count, privacy: .public) document(s) en \(DocumentIndexer.milliseconds(since: started), privacy: .public) ms \
            (\(hits.filter(\.matchedLexically).count, privacy: .public) par mots, \(hits.filter(\.matchedSemantically).count, privacy: .public) par sens)
            """)
        return hits
    }

    /// Documents dont le vecteur est le plus proche de celui de `documentID`.
    public func similarDocuments(to documentID: Int64, limit: Int = 5) async throws -> [Int64] {
        try await database.reader.read { db in
            guard let vector = try AppDatabase.documentVector(of: documentID, in: db) else { return [] }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT chunk.documentId AS documentId, MIN(knn.distance) AS distance
                    FROM (SELECT chunkId, distance FROM chunk_vec WHERE embedding MATCH ? AND k = 100) AS knn
                    JOIN chunk ON chunk.id = knn.chunkId
                    WHERE chunk.documentId <> ?
                    GROUP BY chunk.documentId ORDER BY distance LIMIT ?
                    """,
                arguments: [Embeddings.blob(vector), documentID, limit])
            return rows.map { $0["documentId"] }
        }
    }
}

enum Snippet {
    /// Extrait d'environ 220 caractères centré sur le premier terme de la requête trouvé.
    static func make(from content: String, terms: [String], length: Int = 220) -> String {
        let flat = content.replacingOccurrences(of: "\n", with: " ")
        let folded = FrenchNormalizer.fold(flat)
        var start = flat.startIndex
        // `fold` conserve le nombre de caractères pour le texte latin courant : les positions concordent.
        if folded.count == flat.count,
           let hit = terms.lazy.compactMap({ folded.range(of: $0) }).first {
            let offset = max(0, folded.distance(from: folded.startIndex, to: hit.lowerBound) - length / 3)
            start = flat.index(flat.startIndex, offsetBy: offset)
        }
        let end = flat.index(start, offsetBy: length, limitedBy: flat.endIndex) ?? flat.endIndex
        let prefix = start > flat.startIndex ? "…" : ""
        let suffix = end < flat.endIndex ? "…" : ""
        return prefix + flat[start..<end].trimmingCharacters(in: .whitespaces) + suffix
    }
}
