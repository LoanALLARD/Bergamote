import Foundation
import GRDB
import Testing
@testable import BergamoteKit

@Suite("File de jobs")
struct JobQueueTests {
    let database: AppDatabase
    let queue: JobQueue
    let documentID: Int64

    init() throws {
        database = try AppDatabase.inMemory()
        queue = JobQueue(writer: database.writer)
        documentID = try database.writer.write { db in
            var document = Document(
                sha256: "abc", title: "doc", storedPath: "a/abc.pdf", contentType: "com.adobe.pdf",
                byteCount: 1, status: .queued, importedAt: Date())
            try document.insert(db)
            return document.id!
        }
    }

    @Test func leasePreventsDoubleClaim() throws {
        try database.writer.write { db in try queue.enqueue(.extract, documentID: documentID, in: db) }
        let first = try queue.claim(stages: [.extract])
        #expect(first?.attempts == 1)
        #expect(try queue.claim(stages: [.extract]) == nil)
    }

    @Test func expiredLeaseIsReclaimedAfterCrash() throws {
        try database.writer.write { db in try queue.enqueue(.extract, documentID: documentID, in: db) }
        let now = Date()
        _ = try queue.claim(stages: [.extract], now: now)
        // Le worker « plante » : aucun complete/fail. Après expiration du bail, le job revient.
        let reclaimed = try queue.claim(stages: [.extract], now: now.addingTimeInterval(queue.leaseDuration + 1))
        #expect(reclaimed?.attempts == 2)
    }

    @Test func startupReleasesLeasesImmediately() throws {
        try database.writer.write { db in try queue.enqueue(.extract, documentID: documentID, in: db) }
        _ = try queue.claim(stages: [.extract])
        try queue.releaseAllLeases()
        #expect(try queue.claim(stages: [.extract]) != nil)
    }

    @Test func failuresBackOffThenMarkDocumentFailed() throws {
        try database.writer.write { db in try queue.enqueue(.extract, documentID: documentID, in: db) }
        var now = Date()
        for attempt in 1...queue.maxAttempts {
            let job = try #require(try queue.claim(stages: [.extract], now: now))
            #expect(job.attempts == attempt)
            try queue.fail(job, error: CocoaError(.fileReadCorruptFile), now: now)
            #expect(try queue.claim(stages: [.extract], now: now) == nil, "le backoff doit différer la tentative suivante")
            now.addTimeInterval(3_600)
        }
        let status = try database.reader.read { db in try String.fetchOne(db, sql: "SELECT status FROM document") }
        #expect(status == "failed")
        #expect(try queue.claim(stages: [.extract], now: now) == nil)
    }

    @Test func stagesArePickedByPriority() throws {
        try database.writer.write { db in
            try queue.enqueue(.enrich, documentID: documentID, priority: 0, in: db)
            try queue.enqueue(.extract, documentID: documentID, priority: 10, in: db)
        }
        #expect(try queue.claim(stages: Stage.allCases)?.stage == .extract)
        #expect(try queue.claim(stages: [.extract]) == nil)
        #expect(try queue.claim(stages: [.enrich])?.stage == .enrich)
    }
}
