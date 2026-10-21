import AppKit
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public enum ConversionError: Error, LocalizedError {
    case unreadable(URL)
    case unsupportedOutput(String)
    case writeFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): "Impossible de lire « \(url.lastPathComponent) »"
        case .unsupportedOutput(let type): "macOS ne sait pas écrire le format \(type)"
        case .writeFailed(let url): "Impossible d'écrire « \(url.lastPathComponent) »"
        }
    }
}

/// Les opérations du camembert, uniquement avec les frameworks du système (ImageIO, PDFKit,
/// CoreText, AppKit). Les originaux ne sont jamais modifiés : chaque résultat est un nouveau
/// fichier dans `outputDirectory`, sans écraser un fichier existant.
public struct FileConverter: Sendable {
    public var outputDirectory: URL
    public var imageQuality = 0.85
    public var compressionQuality = 0.6
    public var compressionMaxPixelSize = 2560
    public var renderDPI: CGFloat = 150

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    /// Formats d'image que cette version de macOS sait écrire.
    public static var writableImageTypes: Set<UTType> {
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).compactMap { UTType($0) })
    }

    /// Exécute l'opération et renvoie les fichiers créés. Une compression qui ne gagne rien
    /// ne produit pas de fichier.
    public func perform(_ operation: FileAction.Operation, on urls: [URL]) async throws -> [URL] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        // Fichiers déposés sur le camembert : sous sandbox, l'accès n'est valable qu'entre start/stop.
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }

        switch operation {
        case .convertImages(let type): return try urls.map { try convertImage($0, to: type) }
        case .renderPages(let type): return try urls.flatMap { try renderPages(of: $0, as: type) }
        case .textToPDF: return try urls.map(textToPDF)
        case .convertText(let type): return try urls.map { try convertText($0, to: type) }
        case .makeSearchable: return try urls.map(makeSearchable)
        case .compress: return try urls.compactMap(compress)
        case .stripMetadata: return try urls.map(stripMetadata)
        case .mergeIntoPDF: return [try mergeIntoPDF(urls)]
        case .index: return []  // ajout à la bibliothèque : géré par BergamoteEngine
        case .extractText:
            var outputs: [URL] = []
            for url in urls { outputs.append(try await extractText(url)) }
            return outputs
        }
    }

    // MARK: Images

    func convertImage(_ url: URL, to type: UTType) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw ConversionError.unreadable(url)
        }
        let output = uniqueOutputURL(for: url, type: type)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.unsupportedOutput(type.identifier)
        }
        let options = [kCGImageDestinationLossyCompressionQuality: imageQuality] as CFDictionary
        // JPEG et BMP n'ont pas de transparence : on aplatit sur du blanc plutôt que sur du noir.
        if type.conforms(to: .jpeg) || type.conforms(to: .bmp), let flattened = Self.flattenedOnWhite(source) {
            CGImageDestinationAddImage(destination, flattened, options)
        } else {
            CGImageDestinationAddImageFromSource(destination, source, 0, options)
        }
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.writeFailed(output) }
        return output
    }

    func compress(_ url: URL) throws -> URL? {
        let type = DocumentLibrary.contentType(of: url) ?? .data
        let output: URL
        if type.conforms(to: .pdf) {
            guard let pdf = PDFDocument(url: url) else { throw ConversionError.unreadable(url) }
            output = uniqueOutputURL(for: url, suffix: " (compressé)", type: .pdf)
            guard pdf.write(to: output, withOptions: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]) else {
                throw ConversionError.writeFailed(output)
            }
        } else {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: compressionMaxPixelSize,
                  ] as CFDictionary)
            else { throw ConversionError.unreadable(url) }
            let outputType: UTType = Self.hasAlpha(image) ? .png : .jpeg
            output = uniqueOutputURL(for: url, suffix: " (compressé)", type: outputType)
            try write(image, to: output, type: outputType, quality: compressionQuality)
        }
        if Self.size(of: output) >= Self.size(of: url) {
            try? FileManager.default.removeItem(at: output)
            return nil
        }
        return output
    }

    /// Retire EXIF, GPS, IPTC et XMP sans réencoder quand le format le permet (JPEG, PNG, TIFF) ;
    /// l'orientation est conservée pour que la photo reste à l'endroit. Pour un PDF : auteur, titre…
    func stripMetadata(_ url: URL) throws -> URL {
        let type = DocumentLibrary.contentType(of: url) ?? .data
        let output = uniqueOutputURL(for: url, suffix: " (sans métadonnées)", type: type)
        if type.conforms(to: .pdf) {
            guard let pdf = PDFDocument(url: url) else { throw ConversionError.unreadable(url) }
            pdf.documentAttributes = [:]
            guard pdf.write(to: output) else { throw ConversionError.writeFailed(output) }
            return output
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let sourceType = CGImageSourceGetType(source) else {
            throw ConversionError.unreadable(url)
        }
        let orientation = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation]
        let metadata = CGImageMetadataCreateMutable()
        if let orientation {
            CGImageMetadataSetValueMatchingImageProperty(
                metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, orientation as CFTypeRef)
        }
        if let destination = CGImageDestinationCreateWithURL(output as CFURL, sourceType, 1, nil),
           CGImageDestinationCopyImageSource(destination, source, [
               kCGImageDestinationMetadata: metadata,
               kCGImageDestinationMergeMetadata: false,
               kCGImageMetadataShouldExcludeGPS: true,
           ] as CFDictionary, nil) {
            return output  // CopyImageSource finalise lui-même la destination
        }
        // Formats sans réécriture sans perte (HEIC…) : réencodage sans les dictionnaires sensibles.
        try? FileManager.default.removeItem(at: output)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, sourceType, 1, nil) else {
            throw ConversionError.unsupportedOutput(sourceType as String)
        }
        var tiff: [CFString: Any] = [:]
        if let orientation { tiff[kCGImagePropertyTIFFOrientation] = orientation }
        CGImageDestinationAddImageFromSource(destination, source, 0, [
            kCGImagePropertyExifDictionary: kCFNull as Any,
            kCGImagePropertyGPSDictionary: kCFNull as Any,
            kCGImagePropertyIPTCDictionary: kCFNull as Any,
            kCGImagePropertyTIFFDictionary: tiff,
            kCGImageDestinationLossyCompressionQuality: 1.0,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.writeFailed(output) }
        return output
    }

    // MARK: PDF

    /// PDF et images assemblés dans l'ordre, une page par image.
    func mergeIntoPDF(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { throw ConversionError.unreadable(outputDirectory) }
        let merged = PDFDocument()
        for url in urls {
            for page in try Self.pages(of: url) {
                merged.insert(page, at: merged.pageCount)
            }
        }
        let output = uniqueOutputURL(for: first, suffix: urls.count > 1 ? " (fusion)" : "", type: .pdf)
        guard merged.write(to: output) else { throw ConversionError.writeFailed(output) }
        return output
    }

    func renderPages(of url: URL, as type: UTType) throws -> [URL] {
        guard let pdf = PDFDocument(url: url) else { throw ConversionError.unreadable(url) }
        var outputs: [URL] = []
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index), let image = PDFRendering.image(of: page, dpi: renderDPI) else { continue }
            let output = uniqueOutputURL(for: url, suffix: pdf.pageCount > 1 ? "-p\(index + 1)" : "", type: type)
            try write(image, to: output, type: type, quality: imageQuality)
            outputs.append(output)
        }
        return outputs
    }

    /// Ajoute une couche de texte invisible issue de l'OCR (PDFKit, macOS 13+) : le document
    /// devient sélectionnable et cherchable partout, y compris dans Spotlight et Aperçu.
    func makeSearchable(_ url: URL) throws -> URL {
        let pdf = PDFDocument()
        for page in try Self.pages(of: url) { pdf.insert(page, at: pdf.pageCount) }
        let output = uniqueOutputURL(for: url, suffix: " (cherchable)", type: .pdf)
        guard pdf.write(to: output, withOptions: [.saveTextFromOCROption: true]) else { throw ConversionError.writeFailed(output) }
        return output
    }

    // MARK: Texte

    func textToPDF(_ url: URL) throws -> URL {
        let text = try Self.attributedText(of: url)
        let output = uniqueOutputURL(for: url, type: .pdf)
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4
        guard let context = CGContext(output as CFURL, mediaBox: &box, nil) else { throw ConversionError.writeFailed(output) }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: box.insetBy(dx: 56, dy: 64), transform: nil)
        var location = 0
        repeat {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            location += visible.length
        } while location < text.length
        context.closePDF()
        return output
    }

    func convertText(_ url: URL, to type: UTType) throws -> URL {
        let text = try Self.attributedText(of: url)
        var attributes: [NSAttributedString.DocumentAttributeKey: Any] = [:]
        if type.conforms(to: .rtf) {
            attributes[.documentType] = NSAttributedString.DocumentType.rtf
        } else if type.conforms(to: .plainText) {
            attributes[.documentType] = NSAttributedString.DocumentType.plain
            attributes[.characterEncoding] = String.Encoding.utf8.rawValue
        } else {
            attributes[.documentType] = NSAttributedString.DocumentType.officeOpenXML
        }
        let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: attributes)
        let output = uniqueOutputURL(for: url, type: type)
        try data.write(to: output)
        return output
    }

    func extractText(_ url: URL) async throws -> URL {
        let type = DocumentLibrary.contentType(of: url) ?? .data
        let extracted = try await NativeExtractor().extract(url, contentType: type)
        let output = uniqueOutputURL(for: url, type: .plainText)
        try extracted.text.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    // MARK: Outils

    /// `nom.ext`, puis `nom 2.ext`, `nom 3.ext`… : on n'écrase jamais rien.
    func uniqueOutputURL(for source: URL, suffix: String = "", type: UTType) -> URL {
        let base = source.deletingPathExtension().lastPathComponent + suffix
        let ext = type.preferredFilenameExtension ?? "bin"
        var candidate = outputDirectory.appendingPathComponent(base).appendingPathExtension(ext)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = outputDirectory.appendingPathComponent("\(base) \(index)").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }

    func write(_ image: CGImage, to url: URL, type: UTType, quality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.unsupportedOutput(type.identifier)
        }
        let toWrite = (type.conforms(to: .jpeg) && Self.hasAlpha(image)) ? (Self.flattenedOnWhite(image) ?? image) : image
        CGImageDestinationAddImage(destination, toWrite, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.writeFailed(url) }
    }

    static func pages(of url: URL) throws -> [PDFPage] {
        let type = DocumentLibrary.contentType(of: url) ?? .data
        if type.conforms(to: .pdf) {
            guard let pdf = PDFDocument(url: url) else { throw ConversionError.unreadable(url) }
            return (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.copy() as? PDFPage }
        }
        guard type.conforms(to: .image), let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else {
            throw ConversionError.unreadable(url)
        }
        return [page]
    }

    static func attributedText(of url: URL) throws -> NSAttributedString {
        let type = DocumentLibrary.contentType(of: url) ?? .plainText
        if type.conforms(to: .plainText) {
            let text = try (try? String(contentsOf: url, encoding: .utf8)) ?? String(contentsOf: url, encoding: .isoLatin1)
            return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11)])
        }
        return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
    }

    static func flattenedOnWhite(_ source: CGImageSource) -> CGImage? {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil), hasAlpha(image) else { return nil }
        return flattenedOnWhite(image)
    }

    static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(.white)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    static func size(of url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }
}
