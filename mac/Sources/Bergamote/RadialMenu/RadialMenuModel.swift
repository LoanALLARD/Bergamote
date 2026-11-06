import BergamoteKit
import Foundation
import Observation

/// État du camembert affiché.
@MainActor
@Observable
final class RadialMenuModel {
    enum Status: Equatable {
        case idle
        case working(String)
        case done(String)
        case failed(String)
    }

    private(set) var kind: WheelKind = .conversion
    private(set) var files: [URL] = []
    private(set) var actions: [FileAction] = []
    var highlighted: Int?
    var status: Status = .idle
    /// Résultat de la dernière action, affiché dans le panneau de la barre des menus.
    var lastResult: String?

    func configure(kind: WheelKind, files: [URL], actions: [FileAction]) {
        self.kind = kind
        self.files = files
        self.actions = actions
        highlighted = nil
        status = .idle
    }

    /// « 3 JPG · 39,7 Mo » au centre du camembert (texte du cœur partagé).
    var summary: String { FileSummary.describe(files) }
}
