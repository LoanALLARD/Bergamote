import CoreGraphics
import Foundation

/// Touches de modification, indépendantes d'AppKit pour que la logique reste testable.
public struct WheelModifier: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = WheelModifier(rawValue: 1 << 0)
    public static let control = WheelModifier(rawValue: 1 << 1)
    public static let option = WheelModifier(rawValue: 1 << 2)
    public static let command = WheelModifier(rawValue: 1 << 3)

    public var symbol: String {
        [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { contains($0.0) }.map(\.1).joined()
    }
}

/// Les deux camemberts : un pour convertir, un pour les outils.
public enum WheelKind: String, Sendable, CaseIterable, Codable {
    case conversion
    case tools

    public var title: String {
        switch self {
        case .conversion: "Convertir"
        case .tools: "Outils"
        }
    }
}

/// Machine à états du geste du camembert : « glisser des fichiers, puis taper une touche de modification ».
///
/// Elle ne reçoit que des échantillons (bouton de la souris, compteur du presse-papiers de
/// glisser-déposer, touches enfoncées). La colle AppKit (moniteurs d'événements, minuterie) reste
/// mince, et tout le comportement se teste sans écran.
public struct WheelTriggerDetector: Sendable {
    public struct Sample: Sendable {
        public var isMouseDown: Bool
        /// `NSPasteboard(name: .drag).changeCount` : il change quand un glisser-déposer démarre.
        public var dragPasteboardChangeCount: Int
        public var modifiers: WheelModifier

        public init(isMouseDown: Bool, dragPasteboardChangeCount: Int, modifiers: WheelModifier) {
            self.isMouseDown = isMouseDown
            self.dragPasteboardChangeCount = dragPasteboardChangeCount
            self.modifiers = modifiers
        }
    }

    public enum Decision: Equatable, Sendable {
        case none
        case show(WheelKind)
        case hide
    }

    public var bindings: [WheelModifier: WheelKind]
    public private(set) var visible: WheelKind?
    private var wasMouseDown = false
    private var idleChangeCount: Int?
    private var changeCountAtPress = 0
    private var isDragging = false
    private var previousModifiers: WheelModifier = []

    public init(bindings: [WheelModifier: WheelKind] = [.shift: .conversion, .command: .tools]) {
        self.bindings = bindings
    }

    public mutating func update(_ sample: Sample) -> Decision {
        defer {
            previousModifiers = sample.modifiers
            wasMouseDown = sample.isMouseDown
        }
        guard sample.isMouseDown else {
            idleChangeCount = sample.dragPasteboardChangeCount
            isDragging = false
            if visible != nil {
                visible = nil
                return .hide
            }
            return .none
        }
        if !wasMouseDown {
            // Référence prise bouton relâché : si l'échantillon d'appui arrive après le début du
            // glisser (moniteur en retard), le changement du presse-papiers reste détecté.
            changeCountAtPress = idleChangeCount ?? sample.dragPasteboardChangeCount
            isDragging = false
        }
        if sample.dragPasteboardChangeCount != changeCountAtPress {
            isDragging = true
        }
        // « Taper » une combinaison : elle devient exactement l'ensemble des touches enfoncées.
        guard isDragging, sample.modifiers != previousModifiers,
              let kind = bindings[sample.modifiers], kind != visible
        else { return .none }
        visible = kind
        return .show(kind)
    }

    /// À appeler quand le camembert se ferme de lui-même (dépôt effectué, Échap).
    public mutating func dismiss() {
        visible = nil
    }
}

/// Géométrie du camembert : la part 0 est centrée en haut, puis sens horaire.
public enum WheelGeometry {
    /// Part sous `point`, exprimé par rapport au centre avec l'axe y vers le haut ;
    /// `nil` dans le trou central ou hors du disque.
    public static func slice(at point: CGPoint, count: Int, innerRadius: CGFloat, outerRadius: CGFloat) -> Int? {
        let distance = hypot(point.x, point.y)
        guard count > 0, distance >= innerRadius, distance <= outerRadius else { return nil }
        var angle = atan2(point.x, point.y)  // 0 en haut, positif vers la droite
        if angle < 0 { angle += 2 * .pi }
        let width = 2 * .pi / CGFloat(count)
        return Int((angle + width / 2) / width) % count
    }

    /// Angle du milieu de la part, en radians depuis le haut, sens horaire.
    public static func centerAngle(of index: Int, count: Int) -> CGFloat {
        CGFloat(index) * 2 * .pi / CGFloat(max(count, 1))
    }
}
