import Foundation
import GRDB

/// File de jobs persistante dans SQLite, avec bail (lease).
///
/// Un worker « réclame » un job en posant un bail ; s'il plante, le bail expire et le job est
/// repris. Les échecs sont rejoués avec un backoff exponentiel, puis le document passe en
/// `failed` après `maxAttempts` tentatives.
public struct JobQueue: Sendable {
    public let writer: any DatabaseWriter
    public var leaseDuration: TimeInterval = 300
    public var maxAttempts = 3
    public var baseRetryDelay: TimeInterval = 10

    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// Programme une étape pour un document (ou la réarme si elle existe déjà).
    public func enqueue(_ stage: Stage, documentID: Int64, priority: Int = 0, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO job(documentId, stage, priority) VALUES (?, ?, ?)
                ON CONFLICT(documentId, stage) DO UPDATE SET
                  priority = excluded.priority, attempts = 0, notBefore = 0, leaseUntil = NULL, lastError = NULL
                """,
            arguments: [documentID, stage.rawValue, priority])
    }

    /// Réclame le prochain job prêt parmi `stages`, ou `nil` si la file est vide.
    public func claim(stages: [Stage], now: Date = Date()) throws -> Job? {
        let t = now.timeIntervalSince1970
        let stageArguments = StatementArguments(stages.map(\.rawValue))
        return try writer.write { db in
            try Job.fetchOne(
                db,
                sql: """
                    UPDATE job SET leaseUntil = ?, attempts = attempts + 1
                    WHERE id = (
                      SELECT id FROM job
                      WHERE stage IN (\(databaseQuestionMarks(count: stages.count)))
                        AND notBefore <= ?
                        AND (leaseUntil IS NULL OR leaseUntil < ?)
                        AND attempts < ?
                      ORDER BY priority DESC, id
                      LIMIT 1)
                    RETURNING *
                    """,
                arguments: [t + leaseDuration] + stageArguments + [t, t, maxAttempts])
        }
    }

    public func complete(_ job: Job, in db: Database) throws {
        try db.execute(sql: "DELETE FROM job WHERE id = ?", arguments: [job.id])
    }

    public func complete(_ job: Job) throws {
        try writer.write { db in try complete(job, in: db) }
    }

    /// Rend un job à la file sans compter de tentative (ex. arrêt de l'app en cours de traitement).
    public func release(_ job: Job) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE job SET leaseUntil = NULL, attempts = max(attempts - 1, 0) WHERE id = ?",
                arguments: [job.id])
        }
    }

    public func fail(_ job: Job, error: any Error, now: Date = Date()) throws {
        let message = String(describing: error)
        try writer.write { db in
            if job.attempts >= maxAttempts {
                try db.execute(
                    sql: "UPDATE job SET leaseUntil = NULL, lastError = ? WHERE id = ?",
                    arguments: [message, job.id])
                try db.execute(
                    sql: "UPDATE document SET status = 'failed', lastError = ? WHERE id = ?",
                    arguments: [message, job.documentId])
            } else {
                let delay = pow(2, Double(job.attempts - 1)) * baseRetryDelay
                try db.execute(
                    sql: "UPDATE job SET leaseUntil = NULL, notBefore = ?, lastError = ? WHERE id = ?",
                    arguments: [now.timeIntervalSince1970 + delay, message, job.id])
            }
        }
    }

    /// À appeler au démarrage : l'app est le seul process qui écrit dans la base, donc tout bail
    /// encore posé vient d'une session précédente interrompue. On reprend sans attendre l'expiration.
    public func releaseAllLeases() throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE job SET leaseUntil = NULL WHERE leaseUntil IS NOT NULL")
        }
    }

    /// Relance un document en échec depuis la phase 1.
    public func retry(documentID: Int64) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE document SET status = 'queued', lastError = NULL WHERE id = ?",
                arguments: [documentID])
            try db.execute(sql: "DELETE FROM job WHERE documentId = ?", arguments: [documentID])
            try enqueue(.extract, documentID: documentID, priority: 10, in: db)
        }
    }

    public func pendingCount() throws -> Int {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM job WHERE attempts < ?", arguments: [maxAttempts]) ?? 0
        }
    }
}
