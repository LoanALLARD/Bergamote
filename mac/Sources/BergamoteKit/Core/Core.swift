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

/// Langue de l'app et textes partagés avec Windows et Linux (`core/src/i18n.rs`).
public enum Localization {
    /// Clé du réglage dans UserDefaults : `system`, `fr` ou `en`.
    public static let preferenceKey = "language"
    public static let systemPreference = "system"
    /// Langues proposées : code et nom, qui ne se traduit pas.
    public static let languages: [(code: String, name: String)] = [("fr", "Français"), ("en", "English")]

    /// Langue retenue pour un réglage et une langue du système (`fr-FR`, `en-GB`…).
    public static func resolve(preference: String, system: String) -> String {
        String(cString: bgm_resolve_language(preference, system))
    }

    /// Applique le réglage au cœur : titres des parts et textes changent aussitôt.
    public static func apply(preference: String) {
        bgm_set_language(resolve(preference: preference, system: Locale.preferredLanguages.first ?? "en"))
    }

    /// Code de la langue courante : `fr` ou `en`.
    public static var current: String { String(cString: bgm_language()) }

    /// Texte d'une clé dans la langue courante (la clé elle-même si elle manque, pour qu'un oubli se voie).
    public static func text(_ key: String, _ values: [String: String] = [:]) -> String {
        values.reduce(Core.take(bgm_text(key)) ?? key) { text, value in
            text.replacingOccurrences(of: "{\(value.key)}", with: value.value)
        }
    }
}

/// Raccourci : `L("menu.quit")`, `L("error.unreadable", ["name": "photo.png"])`.
public func L(_ key: String, _ values: [String: String] = [:]) -> String {
    Localization.text(key, values)
}
