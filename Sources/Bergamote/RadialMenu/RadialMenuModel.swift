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

    /// « 3 JPG · 39,7 Mo » au centre du camembert. La taille est omise si la
    /// sandbox ne permet pas encore de lire les fichiers (avant le dépôt).
    var summary: String {
        guard !files.isEmpty else { return "" }
        let extensions = Set(files.map { $0.pathExtension.uppercased() })
        let noun = extensions.count == 1 && !extensions.first!.isEmpty ? extensions.first! : "fichier\(files.count > 1 ? "s" : "")"
        let sizes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
        guard sizes.count == files.count else { return "\(files.count) \(noun)" }
        let total = ByteCountFormatter.string(fromByteCount: Int64(sizes.reduce(0, +)), countStyle: .file)
        return "\(files.count) \(noun) · \(total)"
    }
}
