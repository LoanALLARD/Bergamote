// Génère les icônes des apps à partir de brand/logo.svg :
//
//   mac/Packaging/AppIcon.icns                 icône de l'app Mac (logo dans la marge habituelle)
//   windows/Bergamote.Windows/Bergamote.ico    icône de l'app Windows (16 à 256 px)
//
//   swift brand/make-icons.swift               (macOS 14 ou plus récent, depuis la racine du dépôt)
//
// Le site, le README et le paquet Linux utilisent directement le SVG.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
guard let logo = NSImage(contentsOf: root.appendingPathComponent("brand/logo.svg")) else {
    fatalError("brand/logo.svg introuvable : lancez le script depuis la racine du dépôt")
}

/// Le logo rendu en PNG dans un carré de `size` pixels, occupant la fraction `fill` du carré.
func png(size: Int, fill: CGFloat) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let side = CGFloat(size) * fill
    let inset = (CGFloat(size) - side) / 2
    logo.draw(in: CGRect(x: inset, y: inset, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

// Mac : un .iconset, converti par iconutil. Le logo occupe 824/1024 du carré, comme les icônes du système.
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Bergamote-\(ProcessInfo.processInfo.processIdentifier).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try png(size: points * scale, fill: 824.0 / 1024.0).write(to: iconset.appendingPathComponent(name))
    }
}
let icns = root.appendingPathComponent("mac/Packaging/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil a échoué") }
print("OK : \(icns.path)")

// Windows : un .ico dont chaque taille est un PNG (format accepté depuis Windows Vista).
let sizes = [16, 24, 32, 48, 64, 128, 256]
let images = sizes.map { png(size: $0, fill: 1) }
var ico = Data()
func append<T: FixedWidthInteger>(_ value: T) {
    withUnsafeBytes(of: value.littleEndian) { ico.append(contentsOf: $0) }
}
append(UInt16(0)); append(UInt16(1)); append(UInt16(sizes.count))  // réservé, type icône, nombre d'images
var offset = 6 + 16 * sizes.count
for (size, image) in zip(sizes, images) {
    ico.append(UInt8(size == 256 ? 0 : size)); ico.append(UInt8(size == 256 ? 0 : size))  // 0 signifie 256
    ico.append(0); ico.append(0)                                                        // palette, réservé
    append(UInt16(1)); append(UInt16(32))                                               // plans, bits par pixel
    append(UInt32(image.count)); append(UInt32(offset))
    offset += image.count
}
images.forEach { ico.append($0) }
let icoFile = root.appendingPathComponent("windows/Bergamote.Windows/Bergamote.ico")
try ico.write(to: icoFile)
print("OK : \(icoFile.path)")
