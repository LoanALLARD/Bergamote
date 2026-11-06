import BergamoteCoreFFI
import Foundation

/// Accès au cœur Rust partagé (`core/`), via son interface C.
enum Core {
    static var version: String { String(cString: bgm_core_version()) }

    /// Copie une chaîne renvoyée par le cœur, puis la libère.
    static func take(_ text: UnsafeMutablePointer<CChar>?) -> String? {
        guard let text else { return nil }
        defer { bgm_string_free(text) }
        return String(cString: text)
    }

    static func json(_ value: some Encodable) -> String {
        String(decoding: (try? JSONEncoder().encode(value)) ?? Data("null".utf8), as: UTF8.self)
    }
}

/// Texte affiché au centre du camembert : « 3 JPG · 39,7 Mo ». La taille est omise si la
/// sandbox ne permet pas encore de lire les fichiers (avant le dépôt).
public enum FileSummary {
    public static func describe(_ files: [URL]) -> String {
        let sizes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
        let total = sizes.count == files.count ? Int64(sizes.reduce(0, +)) : -1
        return Core.take(bgm_files_summary(Core.json(files.map(\.pathExtension)), total)) ?? ""
    }
}
