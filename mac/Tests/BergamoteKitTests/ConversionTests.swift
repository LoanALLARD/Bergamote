import AppKit
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import BergamoteKit

@Suite("Camembert : conversions", .serialized)
struct ConversionTests {
    let input: URL
    let output: URL
    let converter: FileConverter

    init() throws {
        let root = try TestFiles.temporaryDirectory()
        input = root.appendingPathComponent("in", isDirectory: true)
        output = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        converter = FileConverter(outputDirectory: output)
    }

    @Test func transparentPNGBecomesJPEGOnWhite() throws {
        let png = try Images.write(Images.redSquareOnTransparent(), to: input.appendingPathComponent("logo.png"), type: .png)
        let produced = try converter.perform(.convertImages(.jpeg), on: [png])
        let jpeg = try #require(produced.first)
        #expect(jpeg.lastPathComponent == "logo.jpeg")
        let image = try #require(Images.load(jpeg))
        #expect(!FileConverter.hasAlpha(image))
        let corner = Images.pixel(of: image, x: 2, y: 2)
        #expect(corner.r > 240 && corner.g > 240 && corner.b > 240, "fond attendu blanc, obtenu \(corner)")

        // Deuxième conversion du même fichier : jamais d'écrasement.
        #expect(try converter.perform(.convertImages(.jpeg), on: [png]).first?.lastPathComponent == "logo 2.jpeg")
    }

    @Test func imagesAndPDFMergeInOrder() throws {
        let first = try Images.write(Images.redSquareOnTransparent(), to: input.appendingPathComponent("a.png"), type: .png)
        let pdf = input.appendingPathComponent("b.pdf")
        try TestFiles.textPDF(["Page un", "Page deux"], at: pdf)
        let merged = try #require(try converter.perform(.mergeIntoPDF, on: [first, pdf]).first)
        let document = try #require(PDFDocument(url: merged))
        #expect(document.pageCount == 3)
        #expect(document.page(at: 1)?.string?.contains("Page un") == true)
        #expect(merged.lastPathComponent == "a (fusion).pdf")
    }

    @Test func pdfPagesBecomeImages() throws {
        let pdf = input.appendingPathComponent("rapport.pdf")
        try TestFiles.textPDF(["Un", "Deux"], at: pdf)
        let pages = try converter.perform(.renderPages(.png), on: [pdf])
        #expect(pages.map(\.lastPathComponent) == ["rapport-p1.png", "rapport-p2.png"])
        let image = try #require(Images.load(pages[0]))
        #expect(image.width == Int(595 * 150 / 72))
    }

    @Test func wordDocumentConvertsToPDFAndText() throws {
        let text = NSAttributedString(string: Samples.lease, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let docx = input.appendingPathComponent("bail.docx")
        try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
            .write(to: docx)

        let pdf = try #require(try converter.perform(.textToPDF, on: [docx]).first)
        #expect(PDFDocument(url: pdf)?.string?.contains("CONTRAT DE BAIL") == true)

        let txt = try #require(try converter.perform(.convertText(.plainText), on: [docx]).first)
        #expect(try String(contentsOf: txt, encoding: .utf8).contains("Article 3"))

        let rtf = try #require(try converter.perform(.convertText(.rtf), on: [txt]).first)
        #expect(rtf.pathExtension == "rtf")
        #expect(try NSAttributedString(url: rtf, options: [:], documentAttributes: nil).string.contains("Article 3"))
    }

    @Test func longTextIsPaginated() throws {
        let txt = input.appendingPathComponent("long.txt")
        try String(repeating: "Une ligne de texte assez longue pour remplir plusieurs pages.\n", count: 400).write(to: txt, atomically: true, encoding: .utf8)
        let pdf = try #require(try converter.perform(.textToPDF, on: [txt]).first)
        #expect((PDFDocument(url: pdf)?.pageCount ?? 0) > 3)
    }

    @Test func scannedPDFBecomesSearchableAndExtractable() throws {
        let scan = input.appendingPathComponent("scan.pdf")
        try TestFiles.scannedPDF("FACTURE N° 2025-118\nTotal TTC : 1 234,56 €", at: scan)
        let scanText = PDFDocument(url: scan)?.string ?? ""
        #expect(scanText.isEmpty, "le scan de départ n'a pas de couche texte")

        let searchable = try #require(try converter.perform(.makeSearchable, on: [scan]).first)
        #expect(searchable.lastPathComponent == "scan (cherchable).pdf")
        #expect(PDFDocument(url: searchable)?.string?.localizedCaseInsensitiveContains("facture") == true)

        let txt = try #require(try converter.perform(.extractText, on: [scan]).first)
        #expect(try String(contentsOf: txt, encoding: .utf8).contains("1 234,56"))
    }

    @Test func metadataIsStrippedButOrientationKept() throws {
        let photo = input.appendingPathComponent("photo.jpg")
        try Images.writeJPEGWithMetadata(to: photo)
        let before = try #require(Images.properties(photo))
        #expect(before[kCGImagePropertyGPSDictionary] != nil)

        let clean = try #require(try converter.perform(.stripMetadata, on: [photo]).first)
        let after = try #require(Images.properties(clean))
        #expect(after[kCGImagePropertyGPSDictionary] == nil)
        #expect((after[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect((after[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] == nil)
        #expect(after[kCGImagePropertyOrientation] as? Int == 6)
    }

    @Test func pdfMetadataIsStripped() throws {
        let pdf = input.appendingPathComponent("signe.pdf")
        var box = TestFiles.pageBox
        let context = try #require(CGContext(pdf as CFURL, mediaBox: &box, [kCGPDFContextAuthor: "Camille Martin", kCGPDFContextTitle: "Bail"] as CFDictionary))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        #expect(PDFDocument(url: pdf)?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String == "Camille Martin")

        let clean = try #require(try converter.perform(.stripMetadata, on: [pdf]).first)
        #expect(PDFDocument(url: clean)?.documentAttributes?[PDFDocumentAttribute.authorAttribute] == nil)
    }

    @Test func compressionKeepsOnlyRealGains() throws {
        let big = try Images.write(Images.noise(width: 3000, height: 2000), to: input.appendingPathComponent("grande.png"), type: .png)
        let compressed = try #require(try converter.perform(.compress, on: [big]).first)
        #expect(compressed.lastPathComponent == "grande (compressé).jpeg")
        #expect(FileConverter.size(of: compressed) < FileConverter.size(of: big) / 4)
        #expect(try #require(Images.load(compressed)).width == 2560)

        // Une petite image déjà compacte : rien à gagner, aucun fichier produit.
        let tiny = try Images.write(Images.solid(width: 40, height: 40), to: input.appendingPathComponent("petite.jpg"), type: .jpeg, quality: 0.3)
        #expect(try converter.perform(.compress, on: [tiny]).isEmpty)
    }

    @Test func resultsLandBesideTheOriginal() throws {
        let png = try Images.write(Images.redSquareOnTransparent(), to: input.appendingPathComponent("logo.png"), type: .png)
        let produced = try FileConverter().perform(.convertImages(.jpeg), on: [png])
        #expect(produced.map(\.path) == [input.appendingPathComponent("logo.jpeg").path])
        #expect(FileManager.default.fileExists(atPath: png.path), "l'original reste en place")
    }

    @Test func folderGrantsCoverSubfolders() {
        let home = URL(fileURLWithPath: "/Users/camille", isDirectory: true)
        #expect(FolderGrants.isCovered(URL(fileURLWithPath: "/Users/camille/Documents/Factures"), by: [home]))
        #expect(FolderGrants.isCovered(home, by: [home]))
        #expect(!FolderGrants.isCovered(URL(fileURLWithPath: "/Users/camilleB/Documents"), by: [home]))
        #expect(!FolderGrants.isCovered(URL(fileURLWithPath: "/Volumes/Cle"), by: [home]))
    }

    @Test func clickSoundIsShortAndSoft() throws {
        let wav = ClickSound.wav()
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<16], as: UTF8.self) == "WAVEfmt ")
        let samples = wav.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        #expect(samples.count == 1_323)  // 30 ms à 44,1 kHz
        let peak = Double(samples.map { abs(Int($0)) }.max() ?? 0) / Double(Int16.max)
        #expect(peak > 0.05 && peak <= 0.17, "niveau de crête \(peak)")
        #expect(samples.suffix(10).allSatisfy { abs(Int($0)) < 200 }, "le clic doit finir sans craquement")
        #expect(NSSound(data: wav) != nil)
    }

}

/// Fabrique d'images de test.
enum Images {
    static func context(width: Int, height: Int, alpha: Bool) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    }

    static func redSquareOnTransparent() -> CGImage {
        let context = context(width: 64, height: 64, alpha: true)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 16, y: 16, width: 32, height: 32))
        return context.makeImage()!
    }

    static func solid(width: Int, height: Int) -> CGImage {
        let context = context(width: width, height: height, alpha: false)
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Bruit déterministe : se compresse mal en PNG, comme une photo.
    static func noise(width: Int, height: Int) -> CGImage {
        let context = context(width: width, height: height, alpha: false)
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
        var state: UInt32 = 42
        for index in 0..<(context.bytesPerRow * height) {
            state = state &* 1_664_525 &+ 1_013_904_223
            pixels[index] = UInt8(truncatingIfNeeded: state >> 24)
        }
        return context.makeImage()!
    }

    @discardableResult
    static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double = 0.9) throws -> URL {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    static func writeJPEGWithMetadata(to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, solid(width: 80, height: 60), [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 45.7578, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 4.8320, kCGImagePropertyGPSLongitudeRef: "E",
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2025:04:12 15:42:00"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Appareil de test"],
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }

    static func load(_ url: URL) -> CGImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    static func properties(_ url: URL) -> [CFString: Any]? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
    }

    static func pixel(of image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let context = context(width: 1, height: 1, alpha: false)
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        let data = context.data!.bindMemory(to: UInt8.self, capacity: 4)
        return (Int(data[0]), Int(data[1]), Int(data[2]))
    }
}
