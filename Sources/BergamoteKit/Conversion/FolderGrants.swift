import Foundation

/// Autorisations de dossier accordées par l'utilisateur (signets à portée de sécurité). Sous
/// sandbox, déposer un fichier ne donne accès qu'au fichier lui-même : pour écrire le résultat à
/// côté, il faut une autorisation sur le dossier. On demande une fois le dossier personnel,
/// et tous les dossiers qu'il contient sont couverts.
public enum FolderGrants {
    /// Vrai si `folder` est l'un des dossiers autorisés ou se trouve dedans.
    public static func isCovered(_ folder: URL, by grants: [URL]) -> Bool {
        let path = canonicalPath(folder)
        return grants.contains { grant in
            let root = canonicalPath(grant)
            return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
        }
    }

    static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
