import BergamoteCoreFFI
import CoreGraphics
import Foundation

/// Touches de modification, indépendantes d'AppKit pour que la logique reste testable. Mêmes
/// bits que dans le cœur partagé.
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

    /// Code du cœur partagé : 1 conversion, 2 outils.
    var coreCode: UInt8 { self == .conversion ? 1 : 2 }

    init?(coreCode: Int) {
        switch coreCode {
        case 1: self = .conversion
        case 2: self = .tools
        default: return nil
        }
    }
}

/// Machine à états du geste du camembert : « glisser des fichiers, puis taper une touche de
/// modification ». La logique vit dans le cœur partagé (`core/src/detector.rs`) ; ce type ne fait
/// que lui transmettre les échantillons.
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

    /// Possède le détecteur du cœur et le libère avec lui.
    private final class Handle: @unchecked Sendable {
        let pointer = bgm_detector_new()
        deinit { bgm_detector_free(pointer) }
    }

    private let handle = Handle()

    public var bindings: [WheelModifier: WheelKind] {
        didSet { applyBindings() }
    }

    public var visible: WheelKind? {
        WheelKind(coreCode: Int(bgm_detector_visible(handle.pointer)))
    }

    public init(bindings: [WheelModifier: WheelKind] = [.shift: .conversion, .command: .tools]) {
        self.bindings = bindings
        applyBindings()
    }

    public mutating func update(_ sample: Sample) -> Decision {
        let code = bgm_detector_update(
            handle.pointer, sample.isMouseDown, Int64(sample.dragPasteboardChangeCount), UInt32(sample.modifiers.rawValue))
        switch code {
        case 3: return .hide
        default: return WheelKind(coreCode: Int(code)).map(Decision.show) ?? .none
        }
    }

    /// À appeler quand le camembert se ferme de lui-même (dépôt effectué, Échap).
    public mutating func dismiss() {
        bgm_detector_dismiss(handle.pointer)
    }

    private func applyBindings() {
        bgm_detector_clear_bindings(handle.pointer)
        for (modifiers, kind) in bindings {
            bgm_detector_set_binding(handle.pointer, UInt32(modifiers.rawValue), kind.coreCode)
        }
    }
}

/// Géométrie du camembert : la part 0 est centrée en haut, puis sens horaire (cœur partagé).
public enum WheelGeometry {
    /// Part sous `point`, exprimé par rapport au centre avec l'axe y vers le haut ;
    /// `nil` dans le trou central ou hors du disque.
    public static func slice(at point: CGPoint, count: Int, innerRadius: CGFloat, outerRadius: CGFloat) -> Int? {
        let index = bgm_slice_at(point.x, point.y, Int32(count), innerRadius, outerRadius)
        return index >= 0 ? Int(index) : nil
    }

    /// Angle du milieu de la part, en radians depuis le haut, sens horaire.
    public static func centerAngle(of index: Int, count: Int) -> CGFloat {
        bgm_center_angle(Int32(index), Int32(count))
    }
}
