import Foundation
import UniformTypeIdentifiers

public enum FileCategory: Sendable, Hashable {
    case image, pdf, text, other

    public init(_ type: UTType) {
        if type.conforms(to: .pdf) {
            self = .pdf
        } else if type.conforms(to: .image) {
            self = .image
        } else if DocumentLibrary.isSupported(type) {
            self = .text  // texte brut, RTF, Word, OpenDocument
        } else {
            self = .other
        }
    }
}

/// Une part du camembert.
public struct FileAction: Identifiable, Hashable, Sendable {
    public enum Operation: Hashable, Sendable {
        case convertImages(UTType)
        case renderPages(UTType)
        case textToPDF
        case convertText(UTType)
        case extractText
        case makeSearchable
        case compress
        case stripMetadata
        case mergeIntoPDF
        case index
    }

    public let title: String
    public let systemImage: String
    public let operation: Operation

    public var id: String { String(describing: operation) }
}

extension UTType {
    // Types déclarés par macOS : toujours présents.
    static let docx = UTType("org.openxmlformats.wordprocessingml.document")!
    static let avif = UTType("public.avif")!
}

/// Les parts proposées selon le camembert et les fichiers glissés (pour des JPEG : PNG,
/// WEBP, HEIC…). Un format que macOS ne sait pas écrire n'apparaît pas.
public enum FileActionCatalog {
    public static let maximumSlices = 8

    static let imageFormats: [(String, UTType)] = [
        ("PNG", .png), ("JPEG", .jpeg), ("HEIC", .heic), ("WEBP", .webP),
        ("AVIF", .avif), ("TIFF", .tiff), ("GIF", .gif), ("BMP", .bmp),
    ]

    public static func actions(
        for kind: WheelKind, inputs: [UTType],
        writableImageTypes: Set<UTType> = FileConverter.writableImageTypes
    ) -> [FileAction] {
        let categories = Set(inputs.map(FileCategory.init))
        guard !inputs.isEmpty, !categories.contains(.other) else { return [] }
        let actions: [FileAction]
        switch kind {
        case .conversion: actions = conversions(inputs: inputs, categories: categories, writable: writableImageTypes)
        case .tools: actions = tools(inputs: inputs, categories: categories)
        }
        return Array(actions.prefix(maximumSlices))
    }

    private static func conversions(inputs: [UTType], categories: Set<FileCategory>, writable: Set<UTType>) -> [FileAction] {
        let text = FileAction(title: "TXT", systemImage: "text.alignleft", operation: .extractText)
        switch categories {
        case [.image]:
            // On ne propose pas le format d'origine quand tous les fichiers y sont déjà.
            let images = imageFormats
                .filter { format in writable.contains(format.1) && !inputs.allSatisfy { $0.conforms(to: format.1) } }
                .map { FileAction(title: $0.0, systemImage: "photo", operation: .convertImages($0.1)) }
            return Array(images.prefix(maximumSlices - 1))
                + [FileAction(title: "PDF", systemImage: "doc.richtext", operation: .mergeIntoPDF)]
        case [.pdf]:
            let pages = imageFormats.prefix(3).filter { writable.contains($0.1) }
                .map { FileAction(title: $0.0, systemImage: "photo.on.rectangle", operation: .renderPages($0.1)) }
            return pages + [text]
        case [.text]:
            let formats: [(String, String, UTType)] = [("DOCX", "doc.text", .docx), ("RTF", "doc.plaintext", .rtf), ("TXT", "text.alignleft", .plainText)]
            return [FileAction(title: "PDF", systemImage: "doc.richtext", operation: .textToPDF)]
                + formats.filter { format in !inputs.allSatisfy { $0.conforms(to: format.2) } }
                    .map { FileAction(title: $0.0, systemImage: $0.1, operation: .convertText($0.2)) }
        case [.image, .pdf]:
            return [FileAction(title: "PDF", systemImage: "doc.richtext", operation: .mergeIntoPDF), text]
        default:
            return [text]
        }
    }

    private static func tools(inputs: [UTType], categories: Set<FileCategory>) -> [FileAction] {
        var actions = [FileAction(title: "Indexer", systemImage: "tray.and.arrow.down", operation: .index)]
        let visual = categories.isSubset(of: [.image, .pdf])
        if visual {
            actions.append(FileAction(title: "Compresser", systemImage: "arrow.down.right.and.arrow.up.left", operation: .compress))
            // Retire EXIF, GPS, auteur… : « Anonymiser » tient dans une part, « Sans métadonnées » non.
            actions.append(FileAction(title: "Anonymiser", systemImage: "tag.slash", operation: .stripMetadata))
            actions.append(FileAction(title: "Cherchable", systemImage: "text.viewfinder", operation: .makeSearchable))
            if inputs.count > 1 {
                actions.append(FileAction(title: "Fusionner", systemImage: "doc.on.doc", operation: .mergeIntoPDF))
            }
        }
        actions.append(FileAction(title: "Texte", systemImage: "text.quote", operation: .extractText))
        return actions
    }
}
