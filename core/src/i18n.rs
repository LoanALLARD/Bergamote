//! Langues et textes partagés. Tout texte qui doit être identique sur Mac, Windows et Linux est
//! ici, dans les deux langues : titres des parts, textes du centre, réglages, menus, erreurs.
//!
//! Les fonctions pures prennent la langue en paramètre ; la langue courante (globale) n'est lue
//! que par l'interface C et par les applications qui utilisent le cœur comme crate.

use std::sync::atomic::{AtomicU8, Ordering};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum Language {
    #[default]
    French,
    English,
}

impl Language {
    pub const ALL: [Language; 2] = [Language::French, Language::English];

    pub fn code(self) -> &'static str {
        match self {
            Language::French => "fr",
            Language::English => "en",
        }
    }

    /// Nom de la langue dans cette langue : il ne se traduit pas.
    pub fn name(self) -> &'static str {
        match self {
            Language::French => "Français",
            Language::English => "English",
        }
    }

    /// `fr`, `fr-FR`, `fr_CA.UTF-8`… ; `None` pour une langue que l'on ne propose pas.
    pub fn from_code(code: &str) -> Option<Self> {
        let prefix: String = code.trim().chars().take_while(char::is_ascii_alphabetic).collect::<String>().to_lowercase();
        match prefix.as_str() {
            "fr" => Some(Language::French),
            "en" => Some(Language::English),
            _ => None,
        }
    }
}

/// Langue à utiliser d'après le réglage (`system`, `fr`, `en`) et la langue du système
/// (`fr-FR`, `en_US.UTF-8`…). Un système dans une autre langue reçoit l'anglais.
pub fn resolve(preference: &str, system_locale: &str) -> Language {
    Language::from_code(preference)
        .or_else(|| Language::from_code(system_locale))
        .unwrap_or(Language::English)
}

static CURRENT: AtomicU8 = AtomicU8::new(0);

/// Langue courante du processus (français au départ).
pub fn current() -> Language {
    match CURRENT.load(Ordering::Relaxed) {
        1 => Language::English,
        _ => Language::French,
    }
}

pub fn set_current(language: Language) {
    CURRENT.store(language as u8, Ordering::Relaxed);
}

/// Texte d'une clé dans une langue ; `None` si la clé n'existe pas.
pub fn text(language: Language, key: &str) -> Option<&'static str> {
    TEXTS.iter().find(|(k, _, _)| *k == key).map(|(_, fr, en)| match language {
        Language::French => *fr,
        Language::English => *en,
    })
}

/// Texte d'une clé connue du cœur (la clé elle-même si elle manque, pour qu'un oubli se voie).
pub fn tr(language: Language, key: &'static str) -> &'static str {
    text(language, key).unwrap_or(key)
}

/// Texte avec ses variables : `format(lang, "result.many", &[("count", "3")])`.
pub fn format(language: Language, key: &'static str, values: &[(&str, &str)]) -> String {
    let mut result = tr(language, key).to_owned();
    for (name, value) in values {
        result = result.replace(&format!("{{{name}}}"), value);
    }
    result
}

/// (clé, français, anglais). Les variables sont entre accolades : `{count}`, `{name}`…
pub const TEXTS: &[(&str, &str, &str)] = &[
    // Camemberts et parts
    ("wheel.convert", "Convertir", "Convert"),
    ("wheel.tools", "Outils", "Tools"),
    ("action.compress", "Compresser", "Compress"),
    // « Anonymiser » tient dans une part, « Sans métadonnées » non.
    ("action.anonymize", "Anonymiser", "Anonymize"),
    ("action.searchable", "Cherchable", "Searchable"),
    ("action.merge", "Fusionner", "Merge"),
    ("action.text", "Texte", "Text"),
    // Centre du camembert
    ("result.none", "Rien à gagner : fichiers déjà optimisés", "Nothing to gain: files already optimized"),
    ("result.one", "1 fichier créé à côté de l'original", "1 file created next to the original"),
    ("result.many", "{count} fichiers créés à côté des originaux", "{count} files created next to the originals"),
    ("files.one", "fichier", "file"),
    ("files.many", "fichiers", "files"),
    ("bytes.one", "octet", "byte"),
    ("bytes.many", "octets", "bytes"),
    ("bytes.kilo", "Ko", "KB"),
    ("bytes.mega", "Mo", "MB"),
    ("bytes.giga", "Go", "GB"),
    // Suffixes des fichiers produits
    ("suffix.compressed", " (compressé)", " (compressed)"),
    ("suffix.no_metadata", " (sans métadonnées)", " (no metadata)"),
    ("suffix.merged", " (fusion)", " (merged)"),
    ("suffix.searchable", " (cherchable)", " (searchable)"),
    // Erreurs
    ("error.not_applicable", "« {title} » ne s'applique pas à ces fichiers", "“{title}” does not apply to these files"),
    ("error.unreadable", "Impossible de lire « {name} »", "Cannot read “{name}”"),
    ("error.write_failed", "Impossible d'écrire « {name} »", "Cannot write “{name}”"),
    ("error.open_failed", "Impossible d'ouvrir « {name} » ({reason})", "Cannot open “{name}” ({reason})"),
    ("error.unsupported_output", "{system} ne sait pas écrire le format {format}", "{system} cannot write the {format} format"),
    ("error.unavailable", "« {title} » n'est pas encore disponible sur {system}", "“{title}” is not available on {system} yet"),
    ("error.failed", "Échec : {reason}", "Failed: {reason}"),
    ("error.merge_unsupported", "« {name} » ne peut pas être ajouté à un PDF", "“{name}” cannot be added to a PDF"),
    ("error.nothing_to_merge", "Aucun fichier à fusionner", "No file to merge"),
    ("error.doc_unsupported", "Les documents Word 97-2003 (.doc) ne sont pas pris en charge : enregistrez-les en .docx", "Word 97-2003 documents (.doc) are not supported: save them as .docx"),
    ("error.install_extension", "Impossible de lire « {name} » : installez « {extension} » depuis le Microsoft Store", "Cannot read “{name}”: install “{extension}” from the Microsoft Store"),
    ("error.no_ocr_language", "Aucune langue de reconnaissance de texte n'est installée (Paramètres › Heure et langue)", "No text recognition language is installed (Settings › Time & language)"),
    ("error.ocr_missing", "Installez Tesseract pour reconnaître le texte des images", "Install Tesseract to recognize text in images"),
    ("error.folder_denied", "Accès au dossier refusé : rien n'a été enregistré", "Folder access denied: nothing was saved"),
    // Menu de l'icône
    ("menu.enable", "Activer", "Enable"),
    ("menu.drag_hint", "Glissez des fichiers depuis {source}, puis :", "Drag files from {source}, then:"),
    ("menu.tap_hint", "Glissez des fichiers, puis tapez :", "Drag files, then tap:"),
    ("menu.convert_detail", "PNG, JPEG, HEIC, PDF, DOCX…", "PNG, JPEG, HEIC, PDF, DOCX…"),
    ("menu.tools_detail", "compresser, anonymiser, OCR…", "compress, anonymize, OCR…"),
    ("menu.convert_hint", "{key} : convertir (PNG, JPEG, PDF…)", "{key}: convert (PNG, JPEG, PDF…)"),
    ("menu.tools_hint", "{key} : outils (compresser, anonymiser…)", "{key}: tools (compress, anonymize…)"),
    ("menu.drop_hint", "Lâchez-les sur une part : le résultat apparaît à côté de l'original.", "Drop them on a slice: the result appears next to the original."),
    ("menu.last_result", "Dernier résultat : {result}", "Last result: {result}"),
    ("menu.settings", "Réglages…", "Settings…"),
    ("menu.quit", "Quitter", "Quit"),
    ("welcome.title", "Bergamote est prêt", "Bergamote is ready"),
    ("welcome.body", "Glissez des fichiers depuis {source}, puis tapez {convert} pour convertir ou {tools} pour les outils.", "Drag files from {source}, then tap {convert} to convert or {tools} for tools."),
    // Réglages
    ("settings.title", "Réglages de Bergamote", "Bergamote Settings"),
    ("settings.enable", "Activer le camembert", "Enable the wheel"),
    ("settings.conversion_key", "Camembert de conversion", "Conversion wheel"),
    ("settings.tools_key", "Camembert d'outils", "Tools wheel"),
    ("settings.key_conflict", "Les deux camemberts utilisent la même touche : seul celui de conversion s'ouvrira.", "Both wheels use the same key: only the conversion wheel will open."),
    ("settings.sound", "Clic au passage d'une part", "Click when crossing a slice"),
    ("settings.listen", "Écouter", "Listen"),
    ("settings.login", "Lancer Bergamote à l'ouverture de session", "Start Bergamote at login"),
    ("settings.login_approval", "À approuver dans Réglages Système › Général › Ouverture.", "Approve it in System Settings › General › Login Items."),
    ("settings.login_unavailable", "Disponible une fois Bergamote.app installé dans Applications.", "Available once Bergamote.app is installed in Applications."),
    ("settings.language", "Langue", "Language"),
    ("settings.language_system", "Celle du système", "Same as the system"),
    ("settings.gesture_help", "Glissez des fichiers depuis {source}, puis tapez la touche choisie (ou maintenez-la avant de glisser) : le camembert s'ouvre sous le curseur. Lâchez les fichiers sur une part.", "Drag files from {source}, then tap the chosen key (or hold it before dragging): the wheel opens under the cursor. Drop the files on a slice."),
    ("settings.result_help", "Le résultat est créé à côté de l'original, qui n'est jamais modifié.", "The result is created next to the original, which is never modified."),
    ("settings.close", "Fermer", "Close"),
    ("settings.running", "Bergamote tourne en arrière-plan.", "Bergamote is running in the background."),
    ("settings.wayland", "Session Wayland : le geste a besoin d'une session X11 (choisissez « Xorg » à l'ouverture de session).", "Wayland session: the gesture needs an X11 session (choose “Xorg” at login)."),
    ("settings.no_ocr", "Tesseract n'est pas installé : pas de reconnaissance de texte dans les images.", "Tesseract is not installed: no text recognition in images."),
    // Dossiers autorisés (Mac, sandbox)
    ("folders.title", "Enregistrement à côté des originaux", "Saving next to the originals"),
    ("folders.help", "Les résultats sont créés dans le même dossier que le fichier d'origine, qui n'est jamais modifié. macOS demande d'autoriser une fois votre dossier personnel : tous les dossiers qu'il contient sont inclus.", "Results are created in the same folder as the original file, which is never modified. macOS asks you to allow your home folder once: every folder inside it is included."),
    ("folders.remove", "Retirer", "Remove"),
    ("folders.allow_home", "Autoriser le dossier personnel…", "Allow the home folder…"),
    ("folders.panel_message", "Bergamote enregistre les résultats à côté des originaux. Autorisez votre dossier personnel une fois : tous les dossiers qu'il contient seront inclus.", "Bergamote saves results next to the originals. Allow your home folder once: every folder inside it will be included."),
    ("folders.panel_prompt", "Autoriser l'accès", "Allow access"),
    // Noms
    ("source.finder", "le Finder", "Finder"),
    ("source.explorer", "l'Explorateur", "Explorer"),
    ("source.files", "votre gestionnaire de fichiers", "your file manager"),
    ("key.shift", "Maj", "Shift"),
    ("key.control", "Ctrl", "Ctrl"),
    ("key.alt", "Alt", "Alt"),
    ("key.windows", "Windows", "Windows"),
    ("key.super", "Super", "Super"),
];

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    fn variables(text: &str) -> BTreeSet<&str> {
        text.split('{').skip(1).filter_map(|part| part.split('}').next()).collect()
    }

    #[test]
    fn every_text_exists_in_both_languages_with_the_same_variables() {
        let mut keys = BTreeSet::new();
        for (key, fr, en) in TEXTS {
            assert!(keys.insert(*key), "clé en double : {key}");
            assert!(!fr.is_empty() && !en.is_empty(), "texte vide : {key}");
            assert_eq!(variables(fr), variables(en), "variables différentes : {key}");
        }
    }

    #[test]
    fn language_codes_and_resolution() {
        assert_eq!(Language::from_code("fr_CA.UTF-8"), Some(Language::French));
        assert_eq!(Language::from_code("EN-us"), Some(Language::English));
        assert_eq!(Language::from_code("system"), None);
        assert_eq!(resolve("system", "fr-FR"), Language::French);
        assert_eq!(resolve("system", "de-DE"), Language::English);
        assert_eq!(resolve("en", "fr-FR"), Language::English);
        assert_eq!(resolve("", ""), Language::English);
    }

    #[test]
    fn lookup_and_format() {
        assert_eq!(text(Language::English, "menu.quit"), Some("Quit"));
        assert_eq!(text(Language::French, "inconnue"), None);
        assert_eq!(format(Language::French, "result.many", &[("count", "3")]), "3 fichiers créés à côté des originaux");
        assert_eq!(format(Language::English, "error.unreadable", &[("name", "a.png")]), "Cannot read “a.png”");
    }
}
