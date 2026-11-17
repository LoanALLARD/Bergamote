//! Lancement à l'ouverture de session : un fichier `.desktop` dans `~/.config/autostart`, comme
//! le prévoit la spécification XDG. Le fichier existe quand le réglage est actif.

use std::path::{Path, PathBuf};

const FILE_NAME: &str = "bergamote.desktop";

/// Dossier `autostart` de l'utilisateur.
pub fn folder() -> PathBuf {
    crate::settings::config_dir().join("autostart")
}

pub fn is_enabled(folder: &Path) -> bool {
    folder.join(FILE_NAME).is_file()
}

/// Active ou désactive le lancement de `executable` à l'ouverture de session. L'app démarre alors
/// sans ouvrir sa fenêtre (`--background`).
pub fn set_enabled(folder: &Path, enabled: bool, executable: &Path) -> std::io::Result<()> {
    let file = folder.join(FILE_NAME);
    if !enabled {
        return match std::fs::remove_file(&file) {
            Err(error) if error.kind() != std::io::ErrorKind::NotFound => Err(error),
            _ => Ok(()),
        };
    }
    std::fs::create_dir_all(folder)?;
    std::fs::write(file, entry(executable))
}

/// Entrée de bureau. Le chemin est mis entre guillemets, avec les échappements de la
/// spécification, pour survivre aux espaces.
fn entry(executable: &Path) -> String {
    let mut quoted = String::new();
    for character in executable.to_string_lossy().chars() {
        if matches!(character, '"' | '`' | '$' | '\\') {
            quoted.push('\\');
        }
        quoted.push(character);
    }
    format!(
        "[Desktop Entry]\nType=Application\nName=Bergamote\nComment=Radial file converter\nComment[fr]=Convertisseur de fichiers en camembert\n\
         Exec=\"{quoted}\" --background\nIcon=bergamote\nTerminal=false\nX-GNOME-Autostart-enabled=true\n"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn creates_and_removes_the_entry() {
        let folder = std::env::temp_dir().join(format!("bergamote-autostart-{}", std::process::id()));
        assert!(!is_enabled(&folder));
        set_enabled(&folder, false, Path::new("/usr/bin/bergamote")).unwrap(); // rien à retirer : pas d'erreur
        set_enabled(&folder, true, Path::new("/opt/Mes apps/bergamote")).unwrap();
        assert!(is_enabled(&folder));
        let entry = std::fs::read_to_string(folder.join(FILE_NAME)).unwrap();
        assert!(entry.contains("Exec=\"/opt/Mes apps/bergamote\" --background\n"), "{entry}");
        set_enabled(&folder, false, Path::new("/usr/bin/bergamote")).unwrap();
        assert!(!is_enabled(&folder));
        std::fs::remove_dir_all(&folder).unwrap();
    }
}
