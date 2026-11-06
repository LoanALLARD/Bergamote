import Foundation
import UniformTypeIdentifiers

public enum FileTypes {
    /// Documents texte que les lecteurs d'AppKit savent ouvrir.
    public static let textDocuments: [UTType] = [
        .plainText, .rtf, .rtfd,
        UTType("org.openxmlformats.wordprocessingml.document"),  // .docx
        UTType("org.oasis-open.opendocument.text"),               // .odt
        UTType("com.microsoft.word.doc"),                         // .doc
    ].compactMap { $0 }

    /// Type d'un fichier, d'après son extension (lisible avant que la sandbox donne accès au
    /// fichier), sinon d'après ses métadonnées.
    public static func contentType(of url: URL) -> UTType? {
        if !url.pathExtension.isEmpty, let type = UTType(filenameExtension: url.pathExtension) { return type }
        return try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
    }

    public static func isTextDocument(_ type: UTType) -> Bool {
        textDocuments.contains { type.conforms(to: $0) }
    }
}
