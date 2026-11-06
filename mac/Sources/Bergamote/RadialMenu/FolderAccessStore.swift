import AppKit
import BergamoteKit
import Darwin
import Observation

/// Dossiers où Bergamote a le droit d'écrire les résultats du camembert, mémorisés sous forme de
/// signets à portée de sécurité. On propose d'autoriser le dossier personnel une seule
/// fois : tous les dossiers qu'il contient sont inclus.
@MainActor
@Observable
final class FolderAccessStore {
    static let bookmarksKey = "folderAccessBookmarks"

    private(set) var grants: [URL] = []

    init() {
        reload()
    }

    /// Hors sandbox (`swift run`), l'app écrit partout : rien à demander.
    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Le vrai dossier personnel : sous sandbox, `NSHomeDirectory()` renvoie celui du conteneur.
    static var homeFolder: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    func covers(_ folders: Set<URL>) -> Bool {
        !Self.isSandboxed || folders.allSatisfy { FolderGrants.isCovered($0, by: grants) }
    }

    /// À appeler avant d'écrire ; chaque URL renvoyée doit ensuite recevoir `stopAccessingSecurityScopedResource()`.
    func startAccessing() -> [URL] {
        grants.filter { $0.startAccessingSecurityScopedResource() }
    }

    /// Demande l'autorisation, en proposant le dossier personnel. Renvoie vrai si `folders` sont
    /// alors tous couverts.
    func requestAccess(covering folders: Set<URL>) -> Bool {
        let panel = NSOpenPanel()
        panel.message = "Bergamote enregistre les résultats à côté des originaux. Autorisez votre dossier personnel une fois : tous les dossiers qu'il contient seront inclus."
        panel.prompt = "Autoriser l'accès"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = Self.homeFolder
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        add(url)
        return covers(folders)
    }

    func add(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        let stored = UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? []
        UserDefaults.standard.set(stored + [bookmark], forKey: Self.bookmarksKey)
        reload()
    }

    func remove(_ url: URL) {
        let path = url.standardizedFileURL.path
        let kept = (UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? []).filter { data in
            Self.resolve(data)?.standardizedFileURL.path != path
        }
        UserDefaults.standard.set(kept, forKey: Self.bookmarksKey)
        reload()
    }

    private func reload() {
        let stored = UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? []
        var seen: Set<String> = []
        grants = stored.compactMap(Self.resolve).filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func resolve(_ bookmark: Data) -> URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }
}
