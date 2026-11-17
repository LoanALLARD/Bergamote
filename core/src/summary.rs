//! Textes affichés au centre du camembert, identiques sur toutes les plateformes.

use std::collections::BTreeSet;

use crate::i18n::{self, Language};

/// Message une fois l'action terminée.
pub fn created(count: usize, language: Language) -> String {
    match count {
        0 => i18n::tr(language, "result.none").to_owned(),
        1 => i18n::tr(language, "result.one").to_owned(),
        n => i18n::format(language, "result.many", &[("count", &n.to_string())]),
    }
}

/// « 3 JPG · 39,7 Mo ». La taille est omise si elle est inconnue (avant que le système donne
/// accès aux fichiers).
pub fn files(extensions: &[String], total_bytes: Option<u64>, language: Language) -> String {
    if extensions.is_empty() {
        return String::new();
    }
    let count = extensions.len();
    let distinct: BTreeSet<String> = extensions.iter().map(|e| e.to_uppercase()).collect();
    let noun = match distinct.iter().next() {
        Some(only) if distinct.len() == 1 && !only.is_empty() => only.clone(),
        _ => i18n::tr(language, if count > 1 { "files.many" } else { "files.one" }).to_owned(),
    };
    match total_bytes {
        Some(bytes) => format!("{count} {noun} · {}", byte_count(bytes, language)),
        None => format!("{count} {noun}"),
    }
}

/// Taille en unités décimales : « 512 octets », « 151 Ko », « 39,7 Mo », « 1,24 Go » en français,
/// « 512 bytes », « 151 KB », « 39.7 MB », « 1.24 GB » en anglais.
pub fn byte_count(bytes: u64, language: Language) -> String {
    let value = bytes as f64;
    let unit = |key| i18n::tr(language, key);
    if bytes < 1_000 {
        format!("{bytes} {}", unit(if bytes == 1 { "bytes.one" } else { "bytes.many" }))
    } else if bytes < 1_000_000 {
        format!("{} {}", (value / 1e3).round(), unit("bytes.kilo"))
    } else if bytes < 1_000_000_000 {
        format!("{} {}", decimal(value / 1e6, 1, language), unit("bytes.mega"))
    } else {
        format!("{} {}", decimal(value / 1e9, 2, language), unit("bytes.giga"))
    }
}

fn decimal(value: f64, digits: usize, language: Language) -> String {
    let text = format!("{value:.digits$}");
    let text = if text.contains('.') { text.trim_end_matches('0').trim_end_matches('.') } else { &text };
    match language {
        Language::French => text.replace('.', ","),
        Language::English => text.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use Language::{English, French};

    #[test]
    fn created_messages() {
        assert_eq!(created(0, French), "Rien à gagner : fichiers déjà optimisés");
        assert_eq!(created(1, French), "1 fichier créé à côté de l'original");
        assert_eq!(created(4, French), "4 fichiers créés à côté des originaux");
        assert_eq!(created(1, English), "1 file created next to the original");
        assert_eq!(created(4, English), "4 files created next to the originals");
    }

    #[test]
    fn files_summary() {
        let png = vec!["png".to_owned(); 3];
        assert_eq!(files(&png, Some(39_700_000), French), "3 PNG · 39,7 Mo");
        assert_eq!(files(&png, Some(39_700_000), English), "3 PNG · 39.7 MB");
        assert_eq!(files(&png, None, French), "3 PNG");
        assert_eq!(files(&["pdf".into(), "png".into()], None, French), "2 fichiers");
        assert_eq!(files(&["pdf".into(), "png".into()], None, English), "2 files");
        assert_eq!(files(&["".into()], None, French), "1 fichier");
        assert_eq!(files(&[], None, French), "");
    }

    #[test]
    fn byte_counts() {
        assert_eq!(byte_count(0, French), "0 octets");
        assert_eq!(byte_count(1, French), "1 octet");
        assert_eq!(byte_count(512, French), "512 octets");
        assert_eq!(byte_count(151_200, French), "151 Ko");
        assert_eq!(byte_count(2_000_000, French), "2 Mo");
        assert_eq!(byte_count(1_240_000_000, French), "1,24 Go");
        assert_eq!(byte_count(1, English), "1 byte");
        assert_eq!(byte_count(151_200, English), "151 KB");
        assert_eq!(byte_count(1_240_000_000, English), "1.24 GB");
    }
}
