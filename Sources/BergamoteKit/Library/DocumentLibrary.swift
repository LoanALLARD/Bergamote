import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Bibliothèque de fichiers adressée par contenu : chaque original est copié sous
/// `ab/abcdef….ext` (SHA-256). Les doublons sont détectés à l'import, et renommer ou
/// déplacer le fichier source n'a aucun effet sur l'index.
public struct DocumentLibrary: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public struct StoredFile: Sendable {
        public var sha256: String
        /// Chemin relatif à `root` : la bibliothèque reste déplaçable.
        public var relativePath: String
        public var byteCount: Int64
    }

    public static let supportedTypes: [UTType] = [
        .pdf, .image, .plainText, .rtf, .rtfd,
        UTType("org.openxmlformats.wordprocessingml.document"),  // .docx
        UTType("org.oasis-open.opendocument.text"),               // .odt
        UTType("com.microsoft.word.doc"),                         // .doc
    ].compactMap { $0 }

    public static func contentType(of url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
    }

    public static func isSupported(_ type: UTType) -> Bool {
        supportedTypes.contains { type.conforms(to: $0) }
    }

    public func url(forStoredPath path: String) -> URL {
        root.appendingPathComponent(path)
    }

    /// Copie le fichier dans la bibliothèque (s'il n'y est pas déjà) et renvoie son empreinte.
    public func store(_ source: URL) throws -> StoredFile {
        let digest = try Self.sha256(of: source)
        let ext = source.pathExtension.lowercased()
        let relativePath = "\(digest.prefix(2))/\(ext.isEmpty ? digest : "\(digest).\(ext)")"
        let destination = url(forStoredPath: relativePath)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
        }
        let size = try fileManager.attributesOfItem(atPath: destination.path)[.size] as? NSNumber
        return StoredFile(sha256: digest, relativePath: relativePath, byteCount: size?.int64Value ?? 0)
    }

    public func remove(storedPath: String) {
        try? FileManager.default.removeItem(at: url(forStoredPath: storedPath))
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1 << 20), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
