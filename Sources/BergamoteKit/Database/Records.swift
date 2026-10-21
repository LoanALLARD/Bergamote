import CoreGraphics
import Foundation
import GRDB

public struct Document: Codable, Hashable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public enum Status: String, Codable, Sendable, CaseIterable {
        /// En attente d'extraction.
        case queued
        case extracting
        /// Phase 1 terminée : texte extrait et indexé en plein texte.
        case searchable
        case enriching
        /// Phase 2 terminée : embeddings, entités et type calculés.
        case ready
        case failed
    }

    public enum DocTypeSource: String, Codable, Sendable {
        /// Appliqué par le modèle (confiance haute et classe déjà validée par l'utilisateur).
        case automatic
        /// Proposé par le modèle, en attente de validation.
        case suggested
        /// Choisi ou validé par l'utilisateur : sert d'exemple au classifieur.
        case user
    }

    public var id: Int64?
    public var sha256: String
    public var title: String
    public var originalPath: String?
    public var storedPath: String
    public var contentType: String
    public var byteCount: Int64
    public var pageCount: Int?
    public var status: Status
    public var docType: String?
    public var docTypeConfidence: Double?
    public var docTypeSource: DocTypeSource?
    public var lastError: String?
    public var importedAt: Date
    public var indexedAt: Date?

    public static let databaseTableName = "document"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Rectangle normalisé (0…1) dans le repère de la page, origine en bas à gauche :
/// c'est le repère commun à PDFKit et à Vision.
public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    public func union(_ other: NormalizedRect) -> NormalizedRect {
        NormalizedRect(cgRect.union(other.cgRect))
    }

    /// Projette le rectangle dans un repère absolu (ex. `PDFPage.bounds(for: .mediaBox)`).
    public func denormalized(in box: CGRect) -> CGRect {
        CGRect(
            x: box.minX + x * box.width, y: box.minY + y * box.height,
            width: width * box.width, height: height * box.height)
    }
}

public struct Chunk: Codable, Hashable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var documentId: Int64
    public var position: Int
    public var page: Int?
    public var bbox: NormalizedRect?
    public var content: String

    public static let databaseTableName = "chunk"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct EntityRecord: Codable, Hashable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var documentId: Int64
    public var kind: EntityKind
    public var value: String
    public var normalized: String?
    public var confidence: Double
    public var page: Int?

    public static let databaseTableName = "entity"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public enum Stage: String, Codable, Sendable, CaseIterable {
    /// Phase 1 : extraction (texte natif ou OCR), découpage, index plein texte.
    case extract
    /// Phase 2 : embeddings, entités, type de document.
    case enrich
}

public struct Job: Codable, Hashable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var documentId: Int64
    public var stage: Stage
    public var priority: Int
    public var attempts: Int
    public var notBefore: Double
    public var leaseUntil: Double?
    public var lastError: String?

    public static let databaseTableName = "job"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
