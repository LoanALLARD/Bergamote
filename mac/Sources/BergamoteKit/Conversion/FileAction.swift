import BergamoteCoreFFI
import Foundation
import UniformTypeIdentifiers

public enum FileCategory: Sendable, Hashable {
    case image, pdf, text, other

    public init(_ type: UTType) {
        if type.conforms(to: .pdf) {
            self = .pdf
        } else if type.conforms(to: .image) {
            self = .image
        } else if FileTypes.isTextDocument(type) {
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
/// WEBP, HEIC…). Le choix des parts vit dans le cœur partagé (`core/src/catalog.rs`) ; ce type
/// traduit les UTType en identifiants de format, puis la réponse en `FileAction`. Un format que
/// macOS ne sait pas écrire n'apparaît pas.
public enum FileActionCatalog {
    public static let maximumSlices = 8

    /// Identifiants de format du cœur, dans l'ordre du camembert.
    static let imageFormats: [(String, UTType)] = [
        ("png", .png), ("jpeg", .jpeg), ("heic", .heic), ("webp", .webP),
        ("avif", .avif), ("tiff", .tiff), ("gif", .gif), ("bmp", .bmp),
    ]
    static let textFormats: [(String, UTType)] = [("docx", .docx), ("rtf", .rtf), ("txt", .plainText)]

    public static func actions(
        for kind: WheelKind, inputs: [UTType],
        writableImageTypes: Set<UTType> = FileConverter.writableImageTypes
    ) -> [FileAction] {
        let request = Request(
            kind: kind.coreCode, inputs: inputs.map(Input.init), common: false,
            writable: writable(writableImageTypes))
        return catalog(request)
    }

    /// Actions proposées quand le type des fichiers glissés n'est pas encore lisible.
    public static func commonActions(for kind: WheelKind, writableImageTypes: Set<UTType> = FileConverter.writableImageTypes) -> [FileAction] {
        catalog(Request(kind: kind.coreCode, inputs: [], common: true, writable: writable(writableImageTypes)))
    }

    // MARK: Échange avec le cœur

    struct Input: Encodable {
        let category: String
        let format: String

        init(_ type: UTType) {
            switch FileCategory(type) {
            case .image: category = "image"
            case .pdf: category = "pdf"
            case .text: category = "text"
            case .other: category = "other"
            }
            format = (FileActionCatalog.imageFormats + FileActionCatalog.textFormats)
                .first { type.conforms(to: $0.1) }?.0 ?? type.identifier
        }
    }

    struct Request: Encodable {
        let kind: UInt8
        let inputs: [Input]
        let common: Bool
        let writable: [String]
    }

    struct Response: Decodable {
        let title: String
        let icon: String
        let operation: String
        let format: String?
    }

    static func writable(_ types: Set<UTType>) -> [String] {
        imageFormats.filter { types.contains($0.1) }.map(\.0)
    }

    static func catalog(_ request: Request) -> [FileAction] {
        guard let json = Core.take(bgm_catalog(Core.json(request))),
              let response = try? JSONDecoder().decode([Response].self, from: Data(json.utf8))
        else { return [] }
        return response.compactMap(action)
    }

    static func action(_ response: Response) -> FileAction? {
        let format = response.format.flatMap { id in (imageFormats + textFormats).first { $0.0 == id }?.1 }
        let operation: FileAction.Operation
        switch (response.operation, format) {
        case ("convert_images", let type?): operation = .convertImages(type)
        case ("render_pages", let type?): operation = .renderPages(type)
        case ("convert_text", let type?): operation = .convertText(type)
        case ("text_to_pdf", _): operation = .textToPDF
        case ("extract_text", _): operation = .extractText
        case ("make_searchable", _): operation = .makeSearchable
        case ("compress", _): operation = .compress
        case ("strip_metadata", _): operation = .stripMetadata
        case ("merge_pdf", _): operation = .mergeIntoPDF
        default: return nil
        }
        return FileAction(title: response.title, systemImage: symbols[response.icon] ?? "doc", operation: operation)
    }

    /// Icônes abstraites du cœur → SF Symbols.
    static let symbols: [String: String] = [
        "photo": "photo",
        "pages": "photo.on.rectangle",
        "document": "doc.richtext",
        "text": "text.alignleft",
        "word": "doc.text",
        "rich_text": "doc.plaintext",
        "compress": "arrow.down.right.and.arrow.up.left",
        "anonymize": "tag.slash",
        "searchable": "text.viewfinder",
        "merge": "doc.on.doc",
        "extract": "text.quote",
    ]
}
