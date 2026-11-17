//! Les opérations du camembert, en Rust pur. Les originaux ne sont jamais modifiés : chaque
//! résultat est un nouveau fichier, posé à côté de l'original (ou dans `output_dir`), sans jamais
//! écraser un fichier existant. Mêmes réglages que les apps Mac et Windows.
//!
//! Seule la reconnaissance de texte s'appuie sur un programme externe, Tesseract, quand il est
//! installé : sans lui, le camembert ne propose pas les parts qui en dépendent.

mod images;
mod ocr;
mod pdf;
mod text;

use std::fmt;
use std::path::{Path, PathBuf};

use bergamote_core::catalog::{self, Action, Category, Operation, Platform};
use bergamote_core::i18n::{self, Language};
use bergamote_core::naming;

pub use ocr::Tesseract;

/// Formats d'image que l'app sait lire et écrire (crate `image`).
pub const IMAGE_FORMATS: [&str; 6] = ["png", "jpeg", "webp", "tiff", "gif", "bmp"];

const SYSTEM: &str = "Linux";

/// Erreur d'une conversion, avec un message prêt à afficher dans la langue de l'app.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConvertError(pub String);

impl fmt::Display for ConvertError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl std::error::Error for ConvertError {}

pub type Result<T> = std::result::Result<T, ConvertError>;

/// Ce que l'app sait faire, déclaré au cœur : il ne propose que ces parts.
pub fn abilities(has_ocr: bool) -> Platform {
    let formats: Vec<String> = IMAGE_FORMATS.iter().map(|f| f.to_string()).collect();
    let mut capabilities = vec!["convert_images", "render_pages", "extract_text", "compress", "strip_metadata", "merge_pdf"];
    if has_ocr {
        capabilities.extend(["ocr", "make_searchable"]);
    }
    Platform {
        writable: formats.clone(),
        readable: Some(formats),
        capabilities: Some(capabilities.into_iter().map(String::from).collect()),
    }
}

pub struct Converter {
    /// Dossier des résultats ; `None` : à côté de chaque original.
    pub output_dir: Option<PathBuf>,
    pub image_quality: u8,
    pub compression_quality: u8,
    pub compression_max_pixel_size: u32,
    pub render_dpi: f32,
    /// Langue des messages et des suffixes de fichier.
    pub language: Language,
    pub tesseract: Option<Tesseract>,
}

impl Default for Converter {
    fn default() -> Self {
        Self {
            output_dir: None,
            image_quality: 85,
            compression_quality: 60,
            compression_max_pixel_size: 2560,
            render_dpi: 150.0,
            language: i18n::current(),
            tesseract: Tesseract::find(),
        }
    }
}

impl Converter {
    /// Exécute l'action et renvoie les fichiers créés. Une compression qui ne gagne rien ne
    /// produit pas de fichier.
    pub fn perform(&self, action: &Action, paths: &[PathBuf]) -> Result<Vec<PathBuf>> {
        if let Some(folder) = &self.output_dir {
            std::fs::create_dir_all(folder).map_err(|_| self.error("error.write_failed", &[("name", &folder.to_string_lossy())]))?;
        }
        let format = || action.format.as_deref().ok_or_else(|| self.unavailable(&action.title));
        match action.operation {
            Operation::ConvertImages => paths.iter().map(|path| self.convert_image(path, format()?)).collect(),
            Operation::RenderPages => {
                let mut outputs = Vec::new();
                for path in paths {
                    outputs.extend(self.render_pages(path, format()?)?);
                }
                Ok(outputs)
            }
            Operation::ExtractText => paths.iter().map(|path| self.extract_text(path)).collect(),
            Operation::Compress => Ok(paths.iter().map(|path| self.compress(path)).collect::<Result<Vec<_>>>()?.into_iter().flatten().collect()),
            Operation::StripMetadata => paths.iter().map(|path| self.strip_metadata(path)).collect(),
            Operation::MergePdf => Ok(vec![self.merge_into_pdf(paths)?]),
            Operation::MakeSearchable => paths.iter().map(|path| self.make_searchable(path)).collect(),
            Operation::TextToPdf | Operation::ConvertText => Err(self.unavailable(&action.title)),
        }
    }

    // MARK: Images

    pub fn convert_image(&self, path: &Path, format: &str) -> Result<PathBuf> {
        let image = self.load_image(path)?;
        let output = self.output(path, "", format);
        self.save_image(&image, &output, format, self.image_quality)?;
        Ok(output)
    }

    /// Réduit à 2560 px au plus et réencode (JPEG, ou PNG s'il y a de la transparence).
    pub fn compress(&self, path: &Path) -> Result<Option<PathBuf>> {
        if category(path) == Category::Pdf {
            return Err(self.unavailable(i18n::tr(self.language, "action.compress")));
        }
        let image = images::fit(self.load_image(path)?, self.compression_max_pixel_size);
        let format = if image.color().has_alpha() { "png" } else { "jpeg" };
        let output = self.output(path, self.suffix("suffix.compressed"), format);
        self.save_image(&image, &output, format, self.compression_quality)?;
        if file_size(&output) >= file_size(path) {
            let _ = std::fs::remove_file(&output);
            return Ok(None);
        }
        Ok(Some(output))
    }

    /// Retire EXIF, GPS, IPTC et XMP en réécrivant l'image ; l'orientation est appliquée aux
    /// pixels pour que la photo reste à l'endroit. Pour un PDF : auteur, titre, métadonnées XMP.
    pub fn strip_metadata(&self, path: &Path) -> Result<PathBuf> {
        let input = catalog::input_for_extension(&extension(path));
        if input.category == Category::Pdf {
            let output = self.output(path, self.suffix("suffix.no_metadata"), "pdf");
            let mut document = self.open_pdf(path)?;
            pdf::strip_metadata(&mut document);
            self.save_pdf(&mut document, &output)?;
            return Ok(output);
        }
        let image = self.load_image(path)?;
        let format = if IMAGE_FORMATS.contains(&input.format.as_str()) { input.format.as_str() } else { "png" };
        let output = self.output(path, self.suffix("suffix.no_metadata"), format);
        self.save_image(&image, &output, format, 95)?;
        Ok(output)
    }

    // MARK: PDF

    /// PDF et images assemblés dans l'ordre du glisser, une page par image.
    pub fn merge_into_pdf(&self, paths: &[PathBuf]) -> Result<PathBuf> {
        let first = paths.first().ok_or_else(|| self.error("error.nothing_to_merge", &[]))?;
        let mut documents = Vec::new();
        for path in paths {
            match category(path) {
                Category::Pdf => documents.push(self.open_pdf(path)?),
                Category::Image => documents.push(pdf::image_document(&self.load_image(path)?, self.image_quality)),
                _ => return Err(self.error("error.merge_unsupported", &[("name", &file_name(path))])),
            }
        }
        let mut merged = pdf::merge(documents);
        let suffix = if paths.len() > 1 { self.suffix("suffix.merged") } else { "" };
        let output = self.output(first, suffix, "pdf");
        self.save_pdf(&mut merged, &output)?;
        Ok(output)
    }

    /// Chaque page en image, 150 ppp ; « -p2 », « -p3 »… quand il y a plusieurs pages.
    pub fn render_pages(&self, path: &Path, format: &str) -> Result<Vec<PathBuf>> {
        let mut outputs = Vec::new();
        pdf::render(&self.read(path)?, self.render_dpi, |index, count, page| {
            let suffix = if count > 1 { format!("-p{}", index + 1) } else { String::new() };
            let output = self.output(path, &suffix, format);
            self.save_image(&page, &output, format, self.image_quality)?;
            outputs.push(output);
            Ok(())
        })
        .map_err(|error| self.pdf_error(path, error))?;
        Ok(outputs)
    }

    /// Ajoute une couche de texte invisible issue de l'OCR : le document devient sélectionnable
    /// et cherchable.
    pub fn make_searchable(&self, path: &Path) -> Result<PathBuf> {
        let tesseract = self.tesseract.as_ref().ok_or_else(|| self.error("error.ocr_missing", &[]))?;
        let output = self.output(path, self.suffix("suffix.searchable"), "pdf");
        let mut pages = Vec::new();
        if category(path) == Category::Pdf {
            pdf::render(&self.read(path)?, text::OCR_DPI, |_, _, page| {
                pages.push(tesseract.searchable_pdf(&page, text::OCR_DPI, self.language).map_err(ConvertError)?);
                Ok(())
            })
            .map_err(|error| self.pdf_error(path, error))?;
        } else {
            pages.push(tesseract.searchable_pdf(&self.load_image(path)?, 0.0, self.language).map_err(ConvertError)?);
        }
        let documents = pages.iter().map(|bytes| lopdf::Document::load_mem(bytes)).collect::<std::result::Result<Vec<_>, _>>();
        let mut merged = pdf::merge(documents.map_err(|error| self.error("error.failed", &[("reason", &error.to_string())]))?);
        self.save_pdf(&mut merged, &output)?;
        Ok(output)
    }

    // MARK: Texte

    pub fn extract_text(&self, path: &Path) -> Result<PathBuf> {
        let text = text::of(self, path)?;
        let output = self.output(path, "", "txt");
        write_new(&output, text.as_bytes()).map_err(|_| self.error("error.write_failed", &[("name", &file_name(&output))]))?;
        Ok(output)
    }

    // MARK: Outils

    fn output(&self, source: &Path, suffix: &str, extension: &str) -> PathBuf {
        naming::unique_output_path(source, suffix, extension, self.output_dir.as_deref())
    }

    fn suffix(&self, key: &'static str) -> &'static str {
        i18n::tr(self.language, key)
    }

    fn error(&self, key: &'static str, values: &[(&str, &str)]) -> ConvertError {
        ConvertError(i18n::format(self.language, key, values))
    }

    fn unavailable(&self, title: &str) -> ConvertError {
        self.error("error.unavailable", &[("title", title), ("system", SYSTEM)])
    }

    fn unreadable(&self, path: &Path) -> ConvertError {
        self.error("error.unreadable", &[("name", &file_name(path))])
    }

    fn pdf_error(&self, path: &Path, error: pdf::RenderError) -> ConvertError {
        match error {
            pdf::RenderError::Unreadable => self.unreadable(path),
            pdf::RenderError::Page(error) => error,
        }
    }

    fn read(&self, path: &Path) -> Result<Vec<u8>> {
        std::fs::read(path).map_err(|_| self.unreadable(path))
    }

    fn load_image(&self, path: &Path) -> Result<image::DynamicImage> {
        images::load(path).map_err(|_| self.unreadable(path))
    }

    fn save_image(&self, image: &image::DynamicImage, output: &Path, format: &str, quality: u8) -> Result<()> {
        images::save(image, output, format, quality).map_err(|error| match error {
            images::SaveError::Unsupported => self.error("error.unsupported_output", &[("system", SYSTEM), ("format", &format.to_uppercase())]),
            images::SaveError::Write => self.error("error.write_failed", &[("name", &file_name(output))]),
        })
    }

    fn open_pdf(&self, path: &Path) -> Result<lopdf::Document> {
        pdf::open(path).map_err(|reason| self.error("error.open_failed", &[("name", &file_name(path)), ("reason", &reason)]))
    }

    fn save_pdf(&self, document: &mut lopdf::Document, output: &Path) -> Result<()> {
        let mut bytes = Vec::new();
        document.save_to(&mut bytes).ok().and_then(|_| write_new(output, &bytes).ok()).ok_or_else(|| self.error("error.write_failed", &[("name", &file_name(output))]))
    }
}

/// Catégorie d'un fichier d'après son extension (table du cœur).
pub fn category(path: &Path) -> Category {
    catalog::input_for_extension(&extension(path)).category
}

pub fn extension(path: &Path) -> String {
    path.extension().map(|e| e.to_string_lossy().into_owned()).unwrap_or_default()
}

fn file_name(path: &Path) -> String {
    path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
}

fn file_size(path: &Path) -> u64 {
    std::fs::metadata(path).map(|m| m.len()).unwrap_or(0)
}

/// Écrit un nouveau fichier ; échoue s'il existe déjà (on n'écrase jamais rien).
fn write_new(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    let mut file = std::fs::OpenOptions::new().write(true).create_new(true).open(path)?;
    file.write_all(bytes).inspect_err(|_| {
        let _ = std::fs::remove_file(path);
    })
}
