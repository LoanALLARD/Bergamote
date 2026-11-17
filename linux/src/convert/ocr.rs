//! Reconnaissance de texte avec Tesseract, s'il est installé (`tesseract` dans le PATH).

use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicU32, Ordering};

use bergamote_core::i18n::Language;
use image::DynamicImage;

use super::images;

#[derive(Clone, Debug)]
pub struct Tesseract {
    program: PathBuf,
    /// Langues installées (`fra`, `eng`…).
    languages: Vec<String>,
}

impl Tesseract {
    /// Cherche `tesseract` dans le PATH et relève ses langues.
    pub fn find() -> Option<Self> {
        let program = std::env::split_paths(&std::env::var_os("PATH")?).map(|folder| folder.join("tesseract")).find(|path| path.is_file())?;
        let listing = Command::new(&program).arg("--list-langs").output().ok()?;
        let languages = String::from_utf8_lossy(&listing.stdout)
            .lines()
            .chain(String::from_utf8_lossy(&listing.stderr).lines())
            .map(str::trim)
            .filter(|line| !line.is_empty() && !line.contains(' ') && !line.contains(':'))
            .map(str::to_owned)
            .collect();
        Some(Self { program, languages })
    }

    /// Langues à reconnaître : celle de l'app d'abord, puis l'autre, si elles sont installées.
    fn language_argument(&self, language: Language) -> Option<String> {
        let preferred = match language {
            Language::French => ["fra", "eng"],
            Language::English => ["eng", "fra"],
        };
        let available: Vec<&str> = preferred.into_iter().filter(|code| self.languages.iter().any(|l| l == code)).collect();
        (!available.is_empty()).then(|| available.join("+"))
    }

    /// Texte de l'image, ligne par ligne.
    pub fn recognize(&self, image: &DynamicImage, language: Language) -> Result<String, String> {
        self.run(image, 0.0, language, None).map(|bytes| String::from_utf8_lossy(&bytes).trim_end().to_owned())
    }

    /// PDF d'une page : l'image, avec une couche de texte invisible. `dpi` : résolution de
    /// l'image, pour une page aux bonnes dimensions (0 si elle est inconnue).
    pub fn searchable_pdf(&self, image: &DynamicImage, dpi: f32, language: Language) -> Result<Vec<u8>, String> {
        self.run(image, dpi, language, Some("pdf"))
    }

    fn run(&self, image: &DynamicImage, dpi: f32, language: Language, output: Option<&str>) -> Result<Vec<u8>, String> {
        let folder = TempFolder::new().map_err(|error| error.to_string())?;
        let input = folder.path.join("page.png");
        std::fs::write(&input, images::png_bytes(image)).map_err(|error| error.to_string())?;
        let base = folder.path.join("out");
        let mut command = Command::new(&self.program);
        command.arg(&input).arg(&base);
        if let Some(languages) = self.language_argument(language) {
            command.args(["-l", &languages]);
        }
        if dpi > 0.0 {
            command.args(["--dpi", &format!("{}", dpi.round() as u32)]);
        }
        command.arg(output.unwrap_or("txt"));
        let result = command.output().map_err(|error| error.to_string())?;
        if !result.status.success() {
            let message = String::from_utf8_lossy(&result.stderr);
            return Err(format!("Tesseract : {}", message.lines().last().unwrap_or("").trim()));
        }
        std::fs::read(base.with_extension(output.unwrap_or("txt"))).map_err(|error| error.to_string())
    }
}

/// Dossier temporaire privé, supprimé à la fin.
struct TempFolder {
    path: PathBuf,
}

impl TempFolder {
    fn new() -> std::io::Result<Self> {
        static COUNTER: AtomicU32 = AtomicU32::new(0);
        let name = format!("bergamote-{}-{}", std::process::id(), COUNTER.fetch_add(1, Ordering::Relaxed));
        let path = std::env::temp_dir().join(name);
        std::fs::create_dir_all(&path)?;
        Ok(Self { path })
    }
}

impl Drop for TempFolder {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}
