import AppKit

/// Le logo de Bergamote, « le B en deux parts », dessiné en code pour la barre des menus et le
/// panneau : un fût, deux demi-disques et une feuille (le même tracé que brand/mark.svg, dans un
/// repère de 100 unités, y vers le bas).
enum BrandMark {
    /// Version d'une seule couleur pour la barre des menus : macOS la teinte selon le thème.
    /// Sans la feuille, et les deux panses séparées, pour rester lisible en 18 points.
    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: bounds.width / 100, y: bounds.height / 100)
            context.translateBy(x: 1, y: -3)
            context.setFillColor(.black)
            context.addPath(CGPath(roundedRect: CGRect(x: 26, y: 20, width: 15, height: 66), cornerWidth: 4, cornerHeight: 4, transform: nil))
            context.addPath(bowl(top: 20, bottom: 48, flat: 53))
            context.addPath(bowl(top: 54, bottom: 86, flat: 56))
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Bergamote"
        return image
    }()

    /// Version en couleurs, pour l'en-tête du panneau.
    static func coloredImage(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: bounds.width / 100, y: bounds.height / 100)
            context.translateBy(x: 0, y: 5)
            // Le fût suit le texte, pour rester visible en mode sombre comme en mode clair.
            context.setFillColor(NSColor.labelColor.cgColor)
            context.addPath(CGPath(roundedRect: CGRect(x: 26, y: 20, width: 15, height: 66), cornerWidth: 4, cornerHeight: 4, transform: nil))
            context.fillPath()
            context.setFillColor(CGColor(red: 0x2F / 255.0, green: 0x6F / 255.0, blue: 0xD6 / 255.0, alpha: 1))
            context.addPath(bowl(top: 20, bottom: 52, flat: 53))
            context.fillPath()
            context.setFillColor(CGColor(red: 0xC3 / 255.0, green: 0xCF / 255.0, blue: 0x3A / 255.0, alpha: 1))
            context.addPath(bowl(top: 48, bottom: 86, flat: 56))
            let leaf = CGMutablePath()
            leaf.move(to: CGPoint(x: 33, y: 17))
            leaf.addCurve(to: CGPoint(x: 43, y: 4), control1: CGPoint(x: 30, y: 9), control2: CGPoint(x: 36, y: 4))
            leaf.addCurve(to: CGPoint(x: 33, y: 17), control1: CGPoint(x: 44, y: 11), control2: CGPoint(x: 41, y: 16))
            context.addPath(leaf)
            context.fillPath()
            return true
        }
    }

    /// Une panse du B : un demi-disque dont le bord droit va de `top` à `bottom`, précédé d'un
    /// segment droit jusqu'à l'abscisse `flat`.
    private static func bowl(top: CGFloat, bottom: CGFloat, flat: CGFloat) -> CGPath {
        let radius = (bottom - top) / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 46, y: top))
        path.addLine(to: CGPoint(x: flat, y: top))
        // Repère retourné : les angles croissants tournent dans le sens des aiguilles d'une montre.
        path.addArc(center: CGPoint(x: flat, y: top + radius), radius: radius, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        path.addLine(to: CGPoint(x: 46, y: bottom))
        path.closeSubpath()
        return path
    }
}
