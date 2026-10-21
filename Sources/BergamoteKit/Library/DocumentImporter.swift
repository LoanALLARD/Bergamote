import Foundation
import GRDB

public struct ImportReport: Sendable {
    public struct Failure: Sendable {
        public var url: URL
        public var message: String
    }

    public var added: [Int64] = []
    public var duplicates = 0
    public var unsupported: [URL] = []
    public var failures: [Failure] = []
}

/// Importe des fichiers ou des dossiers : copie dans la bibliothèque, dédoublonnage par
/// SHA-256, création du document et programmation de la phase 1.
public struct DocumentImporter: Sendable {
    let database: AppDatabase
    let library: DocumentLibrary
    let queue: JobQueue

    public func importItems(_ urls: [URL]) throws -> ImportReport {
        var report = ImportReport()
        for item in urls {
            // URL issue d'un glisser-déposer ou d'un panneau d'ouverture : sous sandbox, l'accès
            // n'est valable qu'entre start/stop, et couvre le contenu d'un dossier.
            let accessing = item.startAccessingSecurityScopedResource()
            defer { if accessing { item.stopAccessingSecurityScopedResource() } }
            for url in Self.expand(item) {
                importFile(url, into: &report)
            }
        }
        return report
    }

    private func importFile(_ url: URL, into report: inout ImportReport) {
        guard let type = DocumentLibrary.contentType(of: url), DocumentLibrary.isSupported(type) else {
            report.unsupported.append(url)
            return
        }
        do {
            let stored = try library.store(url)
            let insertedID: Int64? = try database.writer.write { db in
                let known = try Document.filter(Column("sha256") == stored.sha256).fetchCount(db) > 0
                if known { return nil }
                var document = Document(
                    sha256: stored.sha256,
                    title: url.deletingPathExtension().lastPathComponent,
                    originalPath: url.path,
                    storedPath: stored.relativePath,
                    contentType: type.identifier,
                    byteCount: stored.byteCount,
                    status: .queued,
                    importedAt: Date())
                try document.insert(db)
                // Priorité haute : un fichier déposé à la main passe avant le ré-embedding de fond.
                try queue.enqueue(.extract, documentID: document.id!, priority: 10, in: db)
                return document.id
            }
            if let insertedID {
                report.added.append(insertedID)
            } else {
                report.duplicates += 1
            }
        } catch {
            report.failures.append(.init(url: url, message: error.localizedDescription))
        }
    }

    /// Développe les dossiers (récursivement, sans fichiers cachés ni paquets).
    static func expand(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return [url]
        }
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var files: [URL] = []
        while let child = enumerator?.nextObject() as? URL {
            if (try? child.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                files.append(child)
            }
        }
        return files.sorted { $0.path < $1.path }
    }
}
