import CoreGraphics
import PDFKit

enum PDFRendering {
    /// Rend une page sur fond blanc à la résolution demandée (OCR, export en image).
    static func image(of page: PDFPage, dpi: CGFloat) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let scale = dpi / 72
        let width = Int(box.width * scale), height = Int(box.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}
