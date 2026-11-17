//! Réglages, enregistrés dans `~/.config/bergamote/settings.json`.

use std::path::{Path, PathBuf};

use bergamote_core::detector::{WheelKind, CONTROL, SHIFT};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub enabled: bool,
    /// Touche du camembert de conversion (bits du cœur : 1 Maj, 2 Ctrl, 4 Alt, 8 Super).
    pub conversion_key: u32,
    pub tools_key: u32,
    pub sound: bool,
    /// `system`, `fr` ou `en`.
    pub language: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self { enabled: true, conversion_key: SHIFT, tools_key: CONTROL, sound: true, language: "system".to_owned() }
    }
}

impl Settings {
    /// Touches et camemberts ; en cas de conflit, la conversion l'emporte.
    pub fn bindings(&self) -> Vec<(u32, WheelKind)> {
        if self.tools_key == self.conversion_key {
            vec![(self.conversion_key, WheelKind::Conversion)]
        } else {
            vec![(self.tools_key, WheelKind::Tools), (self.conversion_key, WheelKind::Conversion)]
        }
    }

    /// Réglages enregistrés, et vrai s'il n'y en avait pas encore (premier lancement).
    pub fn load(path: &Path) -> (Self, bool) {
        match std::fs::read_to_string(path) {
            Ok(json) => (serde_json::from_str(&json).unwrap_or_default(), false),
            Err(_) => (Self::default(), true),
        }
    }

    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        if let Some(folder) = path.parent() {
            std::fs::create_dir_all(folder)?;
        }
        std::fs::write(path, serde_json::to_string_pretty(self).unwrap_or_default())
    }
}

/// `$XDG_CONFIG_HOME`, sinon `~/.config`.
pub fn config_dir() -> PathBuf {
    xdg_dir("XDG_CONFIG_HOME", ".config")
}

/// `$XDG_CACHE_HOME`, sinon `~/.cache`.
pub fn cache_dir() -> PathBuf {
    xdg_dir("XDG_CACHE_HOME", ".cache")
}

pub fn settings_path() -> PathBuf {
    config_dir().join("bergamote").join("settings.json")
}

fn xdg_dir(variable: &str, fallback: &str) -> PathBuf {
    match std::env::var_os(variable).filter(|value| !value.is_empty()) {
        Some(folder) => PathBuf::from(folder),
        None => PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(fallback),
    }
}

/// Langue du système d'après `LC_ALL`, `LC_MESSAGES` puis `LANG` (`fr_FR.UTF-8`…).
pub fn system_locale() -> String {
    ["LC_ALL", "LC_MESSAGES", "LANG"].iter().filter_map(|name| std::env::var(name).ok()).find(|value| !value.is_empty()).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_and_defaults() {
        let folder = std::env::temp_dir().join(format!("bergamote-settings-{}", std::process::id()));
        let path = folder.join("nested").join("settings.json");
        let (settings, first) = Settings::load(&path);
        assert!(first);
        assert_eq!(settings, Settings::default());

        let changed = Settings { sound: false, language: "en".into(), ..settings };
        changed.save(&path).unwrap();
        assert_eq!(Settings::load(&path), (changed, false));

        // Un fichier partiel ou abîmé ne bloque pas l'app.
        std::fs::write(&path, r#"{"sound":false}"#).unwrap();
        assert_eq!(Settings::load(&path).0, Settings { sound: false, ..Settings::default() });
        std::fs::write(&path, "{").unwrap();
        assert_eq!(Settings::load(&path).0, Settings::default());
        std::fs::remove_dir_all(&folder).unwrap();
    }

    #[test]
    fn conversion_wins_a_key_conflict() {
        let settings = Settings { tools_key: SHIFT, ..Settings::default() };
        assert_eq!(settings.bindings(), [(SHIFT, WheelKind::Conversion)]);
        assert_eq!(Settings::default().bindings().len(), 2);
    }
}
