import CoreGraphics
import CoreText
import Foundation

enum TestFiles {
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bergamote-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static let pageBox = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4 en points

    /// PDF avec une vraie couche texte (une page par élément de `pages`).
    static func textPDF(_ pages: [String], at url: URL) throws {
        var box = pageBox
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        for text in pages {
            context.beginPDFPage(nil)
            draw(text, in: context, rect: box.insetBy(dx: 50, dy: 60), fontSize: 13)
            context.endPDFPage()
        }
        context.closePDF()
    }

    /// PDF « scanné » : la page ne contient qu'une image, sans couche texte.
    static func scannedPDF(_ text: String, at url: URL) throws {
        let scale: CGFloat = 3
        let width = Int(pageBox.width * scale), height = Int(pageBox.height * scale)
        guard let bitmap = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        bitmap.setFillColor(.white)
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        bitmap.scaleBy(x: scale, y: scale)
        draw(text, in: bitmap, rect: pageBox.insetBy(dx: 50, dy: 60), fontSize: 16)
        guard let image = bitmap.makeImage() else { throw CocoaError(.fileWriteUnknown) }

        var box = pageBox
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        pdf.beginPDFPage(nil)
        pdf.draw(image, in: pageBox)
        pdf.endPDFPage()
        pdf.closePDF()
    }

    private static func draw(_ text: String, in context: CGContext, rect: CGRect, fontSize: CGFloat) {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
        CTFrameDraw(frame, context)
    }
}

enum Samples {
    static let invoice = """
        FACTURE N° 2025-118
        Volt & Fils SARL – 12 rue des Lilas, 69003 Lyon
        SIRET : 732 829 320 00074
        Fourniture d'électricité – période du 01/02/2025 au 28/02/2025
        Consommation : 412 kWh
        Total HT : 1 028,80 €
        TVA 20 % : 205,76 €
        Total TTC : 1 234,56 €
        Échéance : 15 mars 2025
        Règlement par virement – IBAN : FR76 3000 6000 0112 3456 7890 189
        Contact : facturation@volt-fils.fr – 04 72 00 11 22
        """

    static let lease = """
        CONTRAT DE BAIL D'HABITATION
        Entre les soussignés, le bailleur et le locataire, il a été convenu ce qui suit.
        Article 1 – Objet : location d'un appartement de trois pièces à usage d'habitation principale.
        Article 2 – Durée : le présent bail est conclu pour une durée de trois ans renouvelable.
        Article 3 – Loyer : le loyer mensuel est payable d'avance, charges locatives en sus.
        Article 4 – Résiliation : le locataire peut donner congé à tout moment avec un préavis.
        Fait en deux exemplaires, signatures des parties.
        """
}
