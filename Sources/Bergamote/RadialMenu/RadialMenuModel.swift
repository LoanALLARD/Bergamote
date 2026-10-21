import BergamoteKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// État du camembert affiché.
@MainActor
@Observable
final class RadialMenuModel {
    enum Mode {
        /// Ouvert pendant un glisser-déposer : on lâche les fichiers sur une part.
        case drop
        /// Ouvert depuis la bibliothèque : les fichiers sont connus, on clique sur une part.
        case click
    }

    enum Status: Equatable {
        case idle
        case working(String)
        case done(String)
        case failed(String)
    }

    private(set) var kind: WheelKind = .conversion
    private(set) var mode: Mode = .drop
    private(set) var files: [URL] = []
    private(set) var actions: [FileAction] = []
    var highlighted: Int?
    var status: Status = .idle

    func configure(kind: WheelKind, mode: Mode, files: [URL], actions: [FileAction]) {
        self.kind = kind
        self.mode = mode
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
