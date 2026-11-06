//! Textes affichés au centre du camembert, identiques sur toutes les plateformes.

use std::collections::BTreeSet;

/// Message une fois l'action terminée.
pub fn created(count: usize) -> String {
    match count {
        0 => "Rien à gagner : fichiers déjà optimisés".to_owned(),
        1 => "1 fichier créé à côté de l'original".to_owned(),
        n => format!("{n} fichiers créés à côté des originaux"),
    }
}

/// « 3 JPG · 39,7 Mo ». La taille est omise si elle est inconnue (avant que le système donne
/// accès aux fichiers).
pub fn files(extensions: &[String], total_bytes: Option<u64>) -> String {
    if extensions.is_empty() {
        return String::new();
    }
    let count = extensions.len();
    let distinct: BTreeSet<String> = extensions.iter().map(|e| e.to_uppercase()).collect();
    let noun = match distinct.iter().next() {
        Some(only) if distinct.len() == 1 && !only.is_empty() => only.clone(),
        _ => if count > 1 { "fichiers".to_owned() } else { "fichier".to_owned() },
    };
    match total_bytes {
        Some(bytes) => format!("{count} {noun} · {}", byte_count(bytes)),
        None => format!("{count} {noun}"),
    }
}

/// Taille en unités décimales, à la française : « 512 octets », « 151 Ko », « 39,7 Mo », « 1,24 Go ».
pub fn byte_count(bytes: u64) -> String {
    let value = bytes as f64;
    if bytes < 1_000 {
        format!("{bytes} octet{}", if bytes > 1 { "s" } else { "" })
    } else if bytes < 1_000_000 {
        format!("{} Ko", (value / 1e3).round())
    } else if bytes < 1_000_000_000 {
        format!("{} Mo", decimal(value / 1e6, 1))
    } else {
        format!("{} Go", decimal(value / 1e9, 2))
    }
}

fn decimal(value: f64, digits: usize) -> String {
    let text = format!("{value:.digits$}");
    let text = if text.contains('.') { text.trim_end_matches('0').trim_end_matches('.') } else { &text };
    text.replace('.', ",")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn created_messages() {
        assert_eq!(created(0), "Rien à gagner : fichiers déjà optimisés");
        assert_eq!(created(1), "1 fichier créé à côté de l'original");
        assert_eq!(created(4), "4 fichiers créés à côté des originaux");
    }

    #[test]
    fn files_summary() {
        let png = vec!["png".to_owned(); 3];
        assert_eq!(files(&png, Some(39_700_000)), "3 PNG · 39,7 Mo");
        assert_eq!(files(&png, None), "3 PNG");
        assert_eq!(files(&["pdf".into(), "png".into()], None), "2 fichiers");
        assert_eq!(files(&["".into()], None), "1 fichier");
        assert_eq!(files(&[], None), "");
    }

    #[test]
    fn byte_counts() {
        assert_eq!(byte_count(1), "1 octet");
        assert_eq!(byte_count(512), "512 octets");
        assert_eq!(byte_count(151_200), "151 Ko");
        assert_eq!(byte_count(2_000_000), "2 Mo");
        assert_eq!(byte_count(1_240_000_000), "1,24 Go");
    }
}
