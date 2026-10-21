import CSQLiteVec
import Foundation
import GRDB

/// Index local de Bergamote. Métadonnées, plein texte (FTS5), vecteurs (sqlite-vec) et file
/// de jobs vivent dans un seul fichier SQLite : transactions atomiques par document,
/// sauvegarde = un fichier, aucune désynchronisation possible entre deux moteurs.
public struct AppDatabase: Sendable {
    public let writer: any DatabaseWriter
    public var reader: any DatabaseReader { writer }

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Ouvre (ou crée) la base sur disque, en WAL : l'UI lit pendant que l'indexation écrit.
    public static func open(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppDatabase(DatabasePool(path: url.path, configuration: configuration()))
    }

    /// Base en mémoire, pour les tests et les aperçus SwiftUI.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration()))
    }

    public static var sqliteVecVersion: String { String(cString: bgm_sqlite_vec_version()) }

    static func configuration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            // sqlite-vec doit être enregistré sur chaque connexion du pool.
            let rc = bgm_sqlite_vec_register(UnsafeMutableRawPointer(db.sqliteConnection))
            if rc != 0 {
                throw DatabaseError(
                    resultCode: ResultCode(rawValue: rc),
                    message: "sqlite-vec n'a pas pu être initialisé")
            }
        }
        return config
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE document (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  sha256 TEXT NOT NULL UNIQUE,
                  title TEXT NOT NULL,
                  originalPath TEXT,
                  storedPath TEXT NOT NULL,          -- relatif à la racine de la bibliothèque
                  contentType TEXT NOT NULL,         -- identifiant UTType
                  byteCount INTEGER NOT NULL,
                  pageCount INTEGER,
                  status TEXT NOT NULL,
                  docType TEXT,
                  docTypeConfidence REAL,
                  docTypeSource TEXT,                -- automatic | suggested | user
                  lastError TEXT,
                  importedAt DATETIME NOT NULL,
                  indexedAt DATETIME
                );
                CREATE INDEX document_status ON document(status);

                CREATE TABLE chunk (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  documentId INTEGER NOT NULL REFERENCES document(id) ON DELETE CASCADE,
                  position INTEGER NOT NULL,
                  page INTEGER,                      -- 1-based
                  bbox TEXT,                         -- JSON NormalizedRect, pour surligner dans l'aperçu
                  content TEXT NOT NULL
                );
                CREATE INDEX chunk_document ON chunk(documentId, position);

                -- rowid = chunk.id ; texte lemmatisé et sans accents (FrenchNormalizer).
                CREATE VIRTUAL TABLE chunk_fts USING fts5(lemmas, tokenize = 'unicode61 remove_diacritics 2');

                CREATE TABLE entity (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  documentId INTEGER NOT NULL REFERENCES document(id) ON DELETE CASCADE,
                  kind TEXT NOT NULL,
                  value TEXT NOT NULL,
                  normalized TEXT,
                  confidence REAL NOT NULL,
                  page INTEGER
                );
                CREATE INDEX entity_document ON entity(documentId);

                -- File de jobs persistante : survit aux crashs et aux redémarrages (voir JobQueue).
                CREATE TABLE job (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  documentId INTEGER NOT NULL REFERENCES document(id) ON DELETE CASCADE,
                  stage TEXT NOT NULL,
                  priority INTEGER NOT NULL DEFAULT 0,
                  attempts INTEGER NOT NULL DEFAULT 0,
                  notBefore REAL NOT NULL DEFAULT 0,
                  leaseUntil REAL,
                  lastError TEXT,
                  UNIQUE(documentId, stage)
                );

                CREATE TABLE setting (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                """)
            // La table vec0 (chunk_vec) dépend de la dimension du modèle d'embedding :
            // elle est créée par prepareVectorIndex(modelID:dimension:).
        }
        return migrator
    }
}

// MARK: - Index vectoriel

extension AppDatabase {
    static let embeddingSettingKey = "embeddingModel"

    /// Crée la table vec0 pour le modèle d'embedding courant. Si le modèle a changé depuis le
    /// dernier lancement, la table est recréée et les documents déjà enrichis sont renvoyés en
    /// phase « enrich » : la recherche lexicale reste disponible pendant le ré-embedding.
    /// - Returns: `true` si un ré-embedding a été programmé.
    @discardableResult
    public func prepareVectorIndex(modelID: String, dimension: Int) throws -> Bool {
        try writer.write { db in
            let signature = "\(modelID)#\(dimension)"
            let current = try String.fetchOne(
                db, sql: "SELECT value FROM setting WHERE key = ?",
                arguments: [Self.embeddingSettingKey])
            let exists = try db.tableExists("chunk_vec")
            if exists && current == signature { return false }

            if exists { try db.execute(sql: "DROP TABLE chunk_vec") }
            try db.execute(
                sql: "CREATE VIRTUAL TABLE chunk_vec USING vec0(chunkId INTEGER PRIMARY KEY, embedding float[\(dimension)])")
            try db.execute(
                sql: """
                    INSERT INTO setting(key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [Self.embeddingSettingKey, signature])

            guard current != nil else { return false }
            try db.execute(sql: """
                UPDATE document SET status = 'searchable' WHERE status IN ('enriching', 'ready');
                INSERT INTO job(documentId, stage, priority)
                  SELECT id, 'enrich', -1 FROM document WHERE status = 'searchable'
                  ON CONFLICT(documentId, stage) DO UPDATE SET attempts = 0, notBefore = 0, leaseUntil = NULL;
                """)
            return true
        }
    }

    /// Supprime les chunks d'un document et leurs entrées FTS5 et vec0.
    static func purgeChunks(of documentID: Int64, in db: Database) throws {
        let ids = try Int64.fetchAll(
            db, sql: "SELECT id FROM chunk WHERE documentId = ?", arguments: [documentID])
        try deleteVectors(chunkIDs: ids, in: db)
        for id in ids {
            try db.execute(sql: "DELETE FROM chunk_fts WHERE rowid = ?", arguments: [id])
        }
        try db.execute(sql: "DELETE FROM chunk WHERE documentId = ?", arguments: [documentID])
    }

    static func deleteVectors(chunkIDs: [Int64], in db: Database) throws {
        guard try db.tableExists("chunk_vec") else { return }
        for id in chunkIDs {
            try db.execute(sql: "DELETE FROM chunk_vec WHERE chunkId = ?", arguments: [id])
        }
    }

    /// Vecteur d'un document : moyenne normalisée de ses premiers chunks (l'en-tête est le plus
    /// discriminant pour le type). Sert au classement et aux documents similaires.
    static func documentVector(of documentID: Int64, in db: Database, chunkLimit: Int = 3) throws -> [Float]? {
        guard try db.tableExists("chunk_vec") else { return nil }
        let ids = try Int64.fetchAll(
            db, sql: "SELECT id FROM chunk WHERE documentId = ? ORDER BY position LIMIT ?",
            arguments: [documentID, chunkLimit])
        let vectors = try ids.compactMap { id in
            try Data.fetchOne(db, sql: "SELECT embedding FROM chunk_vec WHERE chunkId = ?", arguments: [id])
                .map(Embeddings.vector(from:))
        }
        return Embeddings.mean(vectors)
    }
}
