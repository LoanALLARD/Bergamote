//! Nom du fichier produit : `nom.ext`, puis `nom 2.ext`, `nom 3.ext`… à côté de l'original (ou
//! dans un dossier imposé). On n'écrase jamais rien.

use std::path::{Path, PathBuf};

pub fn unique_output_path(source: &Path, suffix: &str, extension: &str, output_dir: Option<&Path>) -> PathBuf {
    let folder = output_dir.map_or_else(|| source.parent().unwrap_or(Path::new("")).to_path_buf(), Path::to_path_buf);
    let stem = source.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    let base = format!("{stem}{suffix}");
    let mut candidate = folder.join(format!("{base}.{extension}"));
    let mut index = 2;
    while candidate.exists() {
        candidate = folder.join(format!("{base} {index}.{extension}"));
        index += 1;
    }
    candidate
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn never_overwrites_and_keeps_the_folder() {
        let folder = std::env::temp_dir().join(format!("bergamote-naming-{}", std::process::id()));
        fs::create_dir_all(&folder).unwrap();
        let source = folder.join("logo.png");
        let first = unique_output_path(&source, "", "jpeg", None);
        assert_eq!(first, folder.join("logo.jpeg"));
        fs::write(&first, b"x").unwrap();
        assert_eq!(unique_output_path(&source, "", "jpeg", None), folder.join("logo 2.jpeg"));
        assert_eq!(unique_output_path(&source, " (compressé)", "jpeg", None), folder.join("logo (compressé).jpeg"));
        let elsewhere = folder.join("sortie");
        assert_eq!(unique_output_path(&source, "-p1", "png", Some(&elsewhere)), elsewhere.join("logo-p1.png"));
        fs::remove_dir_all(&folder).unwrap();
    }
}
