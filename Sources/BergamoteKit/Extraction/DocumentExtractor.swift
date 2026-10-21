import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public struct TextBlock: Sendable, Hashable {
    public var text: String
    /// Position sur la page, si connue (PDF avec couche texte, ou OCR).
    public var bbox: NormalizedRect?

    public init(text: String, bbox: NormalizedRect? = nil) {
        self.text = text
        self.bbox = bbox
    }
}

public struct ExtractedPage: Sendable, Hashable {
    /// Numéro de page, à partir de 1.
    public var number: Int
    public var blocks: [TextBlock]
    public var usedOCR: Bool
}

public struct ExtractedDocument: Sendable, Hashable {
    public var pages: [ExtractedPage]

    public var text: String {
        pages.flatMap(\.blocks).map(\.text).joined(separator: "\n")
    }
}

public enum ExtractionError: Error, LocalizedError {
    case unsupported(String)
    case unreadable(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let type): "Format non pris en charge : \(type)"
        case .unreadable(let url): "Fichier illisible : \(url.lastPathComponent)"
        }
    }
}

/// Abstraction de l'extraction, pour pouvoir la déplacer dans un service XPC isolé
/// (PDFKit et l'OCR sont la principale source de crashs sur des fichiers corrompus).
public protocol DocumentExtracting: Sendable {
    func extract(_ url: URL, contentType: UTType) async throws -> ExtractedDocument
}

/// Extraction 100 % système : PDFKit pour la couche texte, Vision pour les pages scannées
/// et les images, NSAttributedString pour .docx / .odt / .doc / .rtf.
public struct NativeExtractor: DocumentExtracting {
    public var ocr = VisionOCR()
    /// En dessous de ce nombre de caractères, une page PDF est considérée comme scannée.
    public var minimumTextPerPage = 20
    /// Résolution de rendu des pages envoyées à l'OCR.
    public var ocrDPI: CGFloat = 220

    public init() {}

    public func extract(_ url: URL, contentType: UTType) async throws -> ExtractedDocument {
        if contentType.conforms(to: .pdf) {
            return try extractPDF(url)
        }
        if contentType.conforms(to: .image) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw ExtractionError.unreadable(url) }
            return ExtractedDocument(pages: [ExtractedPage(number: 1, blocks: try ocr.recognize(image), usedOCR: true)])
        }
        if contentType.conforms(to: .plainText) {
            let text = try String(contentsOf: url, encoding: .utf8)
            return ExtractedDocument(pages: [ExtractedPage(number: 1, blocks: Self.paragraphs(text), usedOCR: false)])
        }
        if DocumentLibrary.isSupported(contentType) {
            // .docx, .odt, .doc, .rtf : lecteurs intégrés à AppKit, sans dépendance.
            let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            return ExtractedDocument(pages: [ExtractedPage(number: 1, blocks: Self.paragraphs(attributed.string), usedOCR: false)])
        }
        throw ExtractionError.unsupported(contentType.identifier)
    }

    func extractPDF(_ url: URL) throws -> ExtractedDocument {
        guard let document = PDFDocument(url: url) else { throw ExtractionError.unreadable(url) }
        var pages: [ExtractedPage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumTextPerPage {
                pages.append(ExtractedPage(number: index + 1, blocks: Self.lines(of: page, text: text), usedOCR: false))
            } else if let image = PDFRendering.image(of: page, dpi: ocrDPI) {
                pages.append(ExtractedPage(number: index + 1, blocks: try ocr.recognize(image), usedOCR: true))
            }
        }
        return ExtractedDocument(pages: pages)
    }

    /// Une ligne de texte = un bloc, avec sa position (sert à surligner le passage trouvé).
    static func lines(of page: PDFPage, text: String) -> [TextBlock] {
        let box = page.bounds(for: .mediaBox)
        var blocks: [TextBlock] = []
        let nsText = text as NSString
        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: .byLines) { line, range, _, _ in
            guard let line, !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            var bbox: NormalizedRect?
            if let bounds = page.selection(for: range)?.bounds(for: page), box.width > 0, box.height > 0 {
                bbox = NormalizedRect(CGRect(
                    x: (bounds.minX - box.minX) / box.width, y: (bounds.minY - box.minY) / box.height,
                    width: bounds.width / box.width, height: bounds.height / box.height))
            }
            blocks.append(TextBlock(text: line, bbox: bbox))
        }
        return blocks
    }

    static func paragraphs(_ text: String) -> [TextBlock] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { TextBlock(text: $0) }
    }
}
