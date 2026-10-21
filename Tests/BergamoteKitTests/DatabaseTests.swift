import Foundation
import GRDB
import Testing
@testable import BergamoteKit

@Suite("Index SQLite")
struct DatabaseTests {
    @Test func sqliteVecIsCompiledIn() throws {
        let database = try AppDatabase.inMemory()
        let version = try database.reader.read { db in try String.fetchOne(db, sql: "SELECT vec_version()") }
        #expect(version == AppDatabase.sqliteVecVersion)
        #expect(version?.hasPrefix("v0.1.") == true)
    }

    @Test func vectorTableReturnsNearestNeighbours() throws {
        let database = try AppDatabase.inMemory()
        try database.prepareVectorIndex(modelID: "test", dimension: 3)
        let nearest = try database.writer.write { db -> [Int64] in
            let vectors: [Int64: [Float]] = [1: [1, 0, 0], 2: [0, 1, 0], 3: [0.9, 0.1, 0]]
            for (id, vector) in vectors {
                try db.execute(
                    sql: "INSERT INTO chunk_vec(chunkId, embedding) VALUES (?, ?)",
                    arguments: [id, Embeddings.blob(Embeddings.normalized(vector))])
            }
            return try Int64.fetchAll(
                db, sql: "SELECT chunkId FROM chunk_vec WHERE embedding MATCH ? AND k = 2 ORDER BY distance",
                arguments: [Embeddings.blob(Embeddings.normalized([1, 0.05, 0]))])
        }
        #expect(nearest == [1, 3])
    }

    @Test func changingEmbeddingModelSchedulesReembedding() throws {
        let database = try AppDatabase.inMemory()
        #expect(try database.prepareVectorIndex(modelID: "a", dimension: 4) == false)
        #expect(try database.prepareVectorIndex(modelID: "a", dimension: 4) == false)
        try database.writer.write { db in
            var document = Document(
                sha256: "x", title: "doc", storedPath: "x.pdf", contentType: "com.adobe.pdf",
                byteCount: 1, status: .ready, importedAt: Date())
            try document.insert(db)
        }
        #expect(try database.prepareVectorIndex(modelID: "b", dimension: 8) == true)
        let (status, stages) = try database.reader.read { db in
            (try String.fetchOne(db, sql: "SELECT status FROM document"), try String.fetchAll(db, sql: "SELECT stage FROM job"))
        }
        #expect(status == "searchable")
        #expect(stages == ["enrich"])
    }

    @Test func frenchFullTextMatchesInflectedForms() throws {
        let database = try AppDatabase.inMemory()
        let normalizer = FrenchNormalizer()
        let hits = try database.writer.write { db -> [Int64] in
            try db.execute(sql: "INSERT INTO chunk_fts(rowid, lemmas) VALUES (1, ?)", arguments: [normalizer.indexText("Les factures d'électricité de février")])
            try db.execute(sql: "INSERT INTO chunk_fts(rowid, lemmas) VALUES (2, ?)", arguments: [normalizer.indexText("Contrat de bail")])
            return try Int64.fetchAll(db, sql: "SELECT rowid FROM chunk_fts WHERE chunk_fts MATCH ?", arguments: [normalizer.ftsQuery("facture electricite")!])
        }
        #expect(hits == [1])
    }
}
