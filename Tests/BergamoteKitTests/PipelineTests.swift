import Foundation
import GRDB
import Testing
@testable import BergamoteKit

@Suite("Pipeline de bout en bout", .serialized)
struct PipelineTests {
    @Test func importIndexSearchAndLearn() async throws {
        let root = try TestFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let invoiceURL = inbox.appendingPathComponent("facture-volt.pdf")
        let leaseURL = inbox.appendingPathComponent("bail.pdf")
        try TestFiles.textPDF([Samples.invoice], at: invoiceURL)
        try TestFiles.textPDF([Samples.lease, "Annexe : état des lieux du logement."], at: leaseURL)

        let engine = try await BergamoteEngine.bootstrap(root: root, embedder: HashingEmbedder(dimension: 128), bundledModels: nil)

        // Import d'un dossier, puis ré-import : dédoublonnage par SHA-256.
        let report = try await engine.importItems([inbox])
        #expect(report.added.count == 2)
        #expect(try await engine.importItems([invoiceURL]).duplicates == 1)

        try await engine.runner.drain()

        let documents = try await engine.database.reader.read { db in try Document.order(Column("title")).fetchAll(db) }
        #expect(documents.map(\.status) == [.ready, .ready])
        #expect(documents.first { $0.title == "bail" }?.pageCount == 2)

        // Recherche hybride : forme fléchie et sans accents.
        let hits = try await engine.search.search("factures electricite")
        #expect(hits.first?.title == "facture-volt")
        #expect(hits.first?.page == 1)
        #expect(hits.first?.bbox != nil, "le passage doit pouvoir être surligné")
        #expect(try await engine.search.search("loyer du logement").first?.title == "bail")

        // Entités validées stockées.
        let invoiceID = try #require(documents.first { $0.title == "facture-volt" }?.id)
        let kinds = Set(try await engine.entities(of: invoiceID).map(\.kind))
        #expect(kinds.isSuperset(of: [.iban, .siret, .amount, .date]))

        // Apprentissage local : le type validé devient un exemple du classifieur.
        try await engine.confirmDocType("facture", for: invoiceID)
        #expect(await engine.classifier.exampleCount(for: "facture") == 1)
        let source = try await engine.database.reader.read { db in try Document.fetchOne(db, id: invoiceID)?.docTypeSource }
        #expect(source == .user)

        // Suppression : document, chunks, vecteurs et fichier.
        let leaseID = try #require(documents.first { $0.title == "bail" }?.id)
        try await engine.delete(leaseID)
        let remaining = try await engine.database.reader.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chunk_vec")!, try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chunk_fts")!)
        }
        let invoiceChunks = try await engine.chunks(of: invoiceID).count
        #expect(remaining == (invoiceChunks, invoiceChunks))
    }

    @Test func scannedPDFIsReadWithVisionOCR() async throws {
        let root = try TestFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("scan.pdf")
        try TestFiles.scannedPDF("FACTURE N° 2025-118\nTotal TTC : 1 234,56 €\nÉchéance : 15/03/2025", at: url)

        let extracted = try await NativeExtractor().extract(url, contentType: .pdf)
        #expect(extracted.pages.first?.usedOCR == true)
        let text = extracted.text
        #expect(text.localizedCaseInsensitiveContains("facture"))
        #expect(text.contains("1 234,56"))
        #expect(extracted.pages.first?.blocks.allSatisfy { $0.bbox != nil } == true)
    }

    @Test func extractionTimeoutReturnsEvenIfWorkDoesNotCooperate() async throws {
        let start = ContinuousClock.now
        await #expect(throws: PipelineError.self) {
            try await withTimeout(.milliseconds(100)) { Self.blockingWork() }
        }
        #expect(ContinuousClock.now - start < .milliseconds(800))
    }

    /// Travail bloquant, sourd à l'annulation (comme un PDFKit coincé sur un fichier corrompu).
    static func blockingWork() -> Int {
        Thread.sleep(forTimeInterval: 1)
        return 1
    }

    @Test func lexicalFallbackDoesNotClaimSemanticMatches() async throws {
        let root = try TestFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("facture.pdf")
        try TestFiles.textPDF([Samples.invoice], at: url)
        let engine = try await BergamoteEngine.bootstrap(root: root, embedder: HashingEmbedder(), bundledModels: nil)
        _ = try await engine.importItems([url])
        try await engine.runner.drain()
        #expect(try await engine.search.search("chat qui dort sur le canapé").isEmpty)
        let hit = try #require(try await engine.search.search("facture électricité").first)
        #expect(hit.matchedLexically && !hit.matchedSemantically)
    }
}
