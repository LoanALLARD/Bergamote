import AppKit
import ImageIO
import PDFKit

/// Texte d'un document, uniquement avec le système : couche texte des PDF, OCR Vision pour les
/// pages scannées et les images, lecteurs d'AppKit pour Word, OpenDocument et RTF.
public struct TextExtractor: Sendable {
    public var ocr = VisionOCR()
    /// En dessous de ce nombre de caractères, une page PDF est considérée comme scannée.
    public var minimumTextPerPage = 20
    /// Résolution de rendu des pages envoyées à l'OCR.
    public var ocrDPI: CGFloat = 220

    public init() {}

    public func text(of url: URL) throws -> String {
        let type = FileTypes.contentType(of: url) ?? .data
        if type.conforms(to: .pdf) {
            guard let document = PDFDocument(url: url) else { throw ConversionError.unreadable(url) }
            var pages: [String] = []
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let text = page.string ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumTextPerPage {
                    pages.append(text)
                } else if let image = PDFRendering.image(of: page, dpi: ocrDPI) {
                    pages.append(try ocr.recognize(image).joined(separator: "\n"))
                }
            }
            return pages.joined(separator: "\n\n")
        }
        if type.conforms(to: .image) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw ConversionError.unreadable(url) }
            return try ocr.recognize(image).joined(separator: "\n")
        }
        if FileTypes.isTextDocument(type) {
            return try FileConverter.attributedText(of: url).string
        }
        throw ConversionError.unreadable(url)
    }
}
