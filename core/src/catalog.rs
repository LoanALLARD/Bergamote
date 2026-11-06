//! Les parts proposées selon le camembert et les fichiers glissés (pour des JPEG : PNG, WEBP,
//! HEIC…). Chaque application déclare ce qu'elle sait faire (formats d'image qu'elle peut écrire,
//! opérations disponibles) : une part qu'elle ne saurait pas exécuter n'apparaît pas.

use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

use crate::detector::WheelKind;

pub const MAXIMUM_SLICES: usize = 8;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Category {
    Image,
    Pdf,
    Text,
    Other,
}

/// Un fichier glissé : sa catégorie et un identifiant de format (`png`, `jpeg`, `pdf`, `txt`…).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Input {
    pub category: Category,
    pub format: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Operation {
    ConvertImages,
    RenderPages,
    TextToPdf,
    ConvertText,
    ExtractText,
    MakeSearchable,
    Compress,
    StripMetadata,
    MergePdf,
}

/// Une part du camembert. `icon` est un nom abstrait que chaque application traduit dans sa
/// bibliothèque d'icônes (SF Symbols, Segoe Fluent Icons).
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Action {
    pub id: String,
    pub title: String,
    pub icon: String,
    pub operation: Operation,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub format: Option<String>,
}

impl Action {
    fn new(title: &str, icon: &str, operation: Operation, format: Option<&str>) -> Self {
        let name = serde_json::to_value(operation).ok().and_then(|v| v.as_str().map(str::to_owned)).unwrap_or_default();
        Self {
            id: format.map_or(name.clone(), |f| format!("{name}:{f}")),
            title: title.to_owned(),
            icon: icon.to_owned(),
            operation,
            format: format.map(str::to_owned),
        }
    }
}

/// Ce que l'application sait faire. `capabilities` absent : toutes les opérations.
#[derive(Clone, Debug, Default, Deserialize)]
pub struct Platform {
    #[serde(default)]
    pub writable: Vec<String>,
    #[serde(default)]
    pub capabilities: Option<Vec<String>>,
}

impl Platform {
    fn can_write(&self, format: &str) -> bool {
        self.writable.iter().any(|w| w == format)
    }

    fn supports(&self, action: &Action, inputs: &[Input]) -> bool {
        let Some(capabilities) = &self.capabilities else { return true };
        let has = |name: &str| capabilities.iter().any(|c| c == name);
        match action.operation {
            Operation::ConvertImages => has("convert_images"),
            Operation::RenderPages => has("render_pages"),
            Operation::TextToPdf => has("text_to_pdf"),
            Operation::ConvertText => has("convert_text"),
            Operation::ExtractText => has("extract_text"),
            Operation::MakeSearchable => has("make_searchable"),
            Operation::Compress => {
                has("compress") && (!inputs.iter().any(|i| i.category == Category::Pdf) || has("compress_pdf"))
            }
            Operation::StripMetadata => has("strip_metadata"),
            Operation::MergePdf => has("merge_pdf"),
        }
    }
}

const IMAGE_FORMATS: [(&str, &str); 8] = [
    ("PNG", "png"), ("JPEG", "jpeg"), ("HEIC", "heic"), ("WEBP", "webp"),
    ("AVIF", "avif"), ("TIFF", "tiff"), ("GIF", "gif"), ("BMP", "bmp"),
];

pub fn actions(kind: WheelKind, inputs: &[Input], platform: &Platform) -> Vec<Action> {
    let categories: BTreeSet<Category> = inputs.iter().map(|i| i.category).collect();
    if inputs.is_empty() || categories.contains(&Category::Other) {
        return Vec::new();
    }
    let actions = match kind {
        WheelKind::Conversion => conversions(inputs, &categories, platform),
        WheelKind::Tools => tools(inputs, &categories),
    };
    finish(actions, inputs, platform)
}

/// Actions proposées quand le type des fichiers glissés n'est pas encore lisible.
pub fn common_actions(kind: WheelKind, platform: &Platform) -> Vec<Action> {
    let inputs = [
        Input { category: Category::Image, format: "png".into() },
        Input { category: Category::Pdf, format: "pdf".into() },
    ];
    let actions = match kind {
        WheelKind::Conversion => {
            let mut actions = vec![merge()];
            actions.extend(image_formats(platform, 3).map(|(title, format)| Action::new(title, "photo", Operation::ConvertImages, Some(format))));
            actions.push(extract("TXT", "text"));
            actions
        }
        WheelKind::Tools => tools(&inputs, &[Category::Image, Category::Pdf].into()),
    };
    finish(actions, &inputs, platform)
}

/// Retire ce que la plateforme ne sait pas faire, puis limite le nombre de parts.
fn finish(actions: Vec<Action>, inputs: &[Input], platform: &Platform) -> Vec<Action> {
    actions.into_iter().filter(|a| platform.supports(a, inputs)).take(MAXIMUM_SLICES).collect()
}

fn image_formats<'a>(platform: &'a Platform, limit: usize) -> impl Iterator<Item = (&'static str, &'static str)> + 'a {
    IMAGE_FORMATS.into_iter().take(limit).filter(|(_, format)| platform.can_write(format))
}

fn merge() -> Action {
    Action::new("PDF", "document", Operation::MergePdf, None)
}

fn extract(title: &str, icon: &str) -> Action {
    Action::new(title, icon, Operation::ExtractText, None)
}

fn conversions(inputs: &[Input], categories: &BTreeSet<Category>, platform: &Platform) -> Vec<Action> {
    let all_in = |format: &str| inputs.iter().all(|i| i.format == format);
    match categories.iter().copied().collect::<Vec<_>>().as_slice() {
        [Category::Image] => {
            // On ne propose pas le format d'origine quand tous les fichiers y sont déjà.
            let mut actions: Vec<Action> = IMAGE_FORMATS
                .into_iter()
                .filter(|(_, format)| platform.can_write(format) && !all_in(format))
                .map(|(title, format)| Action::new(title, "photo", Operation::ConvertImages, Some(format)))
                .take(MAXIMUM_SLICES - 1)
                .collect();
            actions.push(merge());
            actions
        }
        [Category::Pdf] => {
            let mut actions: Vec<Action> = image_formats(platform, 3)
                .map(|(title, format)| Action::new(title, "pages", Operation::RenderPages, Some(format)))
                .collect();
            actions.push(extract("TXT", "text"));
            actions
        }
        [Category::Text] => {
            let formats = [("DOCX", "word", "docx"), ("RTF", "rich_text", "rtf"), ("TXT", "text", "txt")];
            let mut actions = vec![Action::new("PDF", "document", Operation::TextToPdf, None)];
            actions.extend(
                formats
                    .into_iter()
                    .filter(|(_, _, format)| !all_in(format))
                    .map(|(title, icon, format)| Action::new(title, icon, Operation::ConvertText, Some(format))),
            );
            actions
        }
        [Category::Image, Category::Pdf] => vec![merge(), extract("TXT", "text")],
        _ => vec![extract("TXT", "text")],
    }
}

fn tools(inputs: &[Input], categories: &BTreeSet<Category>) -> Vec<Action> {
    let mut actions = Vec::new();
    if categories.iter().all(|c| matches!(c, Category::Image | Category::Pdf)) {
        actions.push(Action::new("Compresser", "compress", Operation::Compress, None));
        // Retire EXIF, GPS, auteur… : « Anonymiser » tient dans une part, « Sans métadonnées » non.
        actions.push(Action::new("Anonymiser", "anonymize", Operation::StripMetadata, None));
        actions.push(Action::new("Cherchable", "searchable", Operation::MakeSearchable, None));
        if inputs.len() > 1 {
            actions.push(Action::new("Fusionner", "merge", Operation::MergePdf, None));
        }
    }
    actions.push(extract("Texte", "extract"));
    actions
}

/// Catégorie et format d'après l'extension, pour les plateformes sans système de types riche.
/// (Sur Mac, l'app s'appuie sur les UTType et n'utilise pas cette table.)
pub fn input_for_extension(extension: &str) -> Input {
    let extension = extension.trim_start_matches('.').to_lowercase();
    let (category, format) = match extension.as_str() {
        "pdf" => (Category::Pdf, "pdf"),
        "png" => (Category::Image, "png"),
        "jpg" | "jpeg" | "jpe" | "jfif" => (Category::Image, "jpeg"),
        "heic" | "heif" => (Category::Image, "heic"),
        "webp" => (Category::Image, "webp"),
        "avif" => (Category::Image, "avif"),
        "tif" | "tiff" => (Category::Image, "tiff"),
        "gif" => (Category::Image, "gif"),
        "bmp" | "dib" => (Category::Image, "bmp"),
        "txt" | "text" | "md" | "markdown" => (Category::Text, "txt"),
        "rtf" => (Category::Text, "rtf"),
        "docx" => (Category::Text, "docx"),
        "odt" => (Category::Text, "odt"),
        "doc" => (Category::Text, "doc"),
        _ => (Category::Other, extension.as_str()),
    };
    Input { category, format: format.to_owned() }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn image(format: &str) -> Input {
        Input { category: Category::Image, format: format.into() }
    }

    fn mac(writable: &[&str]) -> Platform {
        Platform { writable: writable.iter().map(|s| s.to_string()).collect(), capabilities: None }
    }

    fn titles(actions: &[Action]) -> Vec<&str> {
        actions.iter().map(|a| a.title.as_str()).collect()
    }

    #[test]
    fn conversion_wheel_adapts_to_inputs() {
        let platform = mac(&["png", "jpeg", "heic", "tiff", "gif", "bmp"]);
        let for_jpeg = actions(WheelKind::Conversion, &[image("jpeg"), image("jpeg")], &platform);
        assert_eq!(titles(&for_jpeg), ["PNG", "HEIC", "TIFF", "GIF", "BMP", "PDF"]);
        assert_eq!(for_jpeg.last().unwrap().operation, Operation::MergePdf);

        let pdf = Input { category: Category::Pdf, format: "pdf".into() };
        let for_pdf = actions(WheelKind::Conversion, &[pdf], &platform);
        assert_eq!(
            for_pdf.iter().map(|a| a.id.as_str()).collect::<Vec<_>>(),
            ["render_pages:png", "render_pages:jpeg", "render_pages:heic", "extract_text"]
        );

        let word = Input { category: Category::Text, format: "docx".into() };
        assert_eq!(titles(&actions(WheelKind::Conversion, &[word], &platform)), ["PDF", "RTF", "TXT"]);

        let mp3 = Input { category: Category::Other, format: "mp3".into() };
        assert!(actions(WheelKind::Conversion, &[mp3], &platform).is_empty());
    }

    #[test]
    fn tools_wheel_adapts_to_inputs() {
        let platform = mac(&[]);
        let for_images = actions(WheelKind::Tools, &[image("png"), image("jpeg")], &platform);
        assert_eq!(
            for_images.iter().map(|a| a.operation).collect::<Vec<_>>(),
            [Operation::Compress, Operation::StripMetadata, Operation::MakeSearchable, Operation::MergePdf, Operation::ExtractText]
        );
        let text = Input { category: Category::Text, format: "txt".into() };
        assert_eq!(actions(WheelKind::Tools, &[text], &platform).iter().map(|a| a.operation).collect::<Vec<_>>(), [Operation::ExtractText]);
    }

    #[test]
    fn common_actions_when_types_are_unknown() {
        let conversion = common_actions(WheelKind::Conversion, &mac(&["png", "jpeg"]));
        assert_eq!(titles(&conversion), ["PDF", "PNG", "JPEG", "TXT"]);
        let tools = common_actions(WheelKind::Tools, &mac(&[]));
        assert_eq!(tools[0].operation, Operation::Compress);
        assert!(tools.iter().any(|a| a.operation == Operation::MakeSearchable));
    }

    #[test]
    fn platform_capabilities_hide_unsupported_slices() {
        let windows = Platform {
            writable: vec!["png".into(), "jpeg".into(), "tiff".into(), "gif".into(), "bmp".into()],
            capabilities: Some(["convert_images", "render_pages", "extract_text", "compress", "strip_metadata", "merge_pdf"].map(String::from).to_vec()),
        };
        let for_images = actions(WheelKind::Tools, &[image("png"), image("png")], &windows);
        assert_eq!(titles(&for_images), ["Compresser", "Anonymiser", "Fusionner", "Texte"]);
        // Compresser un PDF demande « compress_pdf ».
        let pdf = Input { category: Category::Pdf, format: "pdf".into() };
        assert_eq!(titles(&actions(WheelKind::Tools, &[pdf], &windows)), ["Anonymiser", "Texte"]);
        // Sans conversion de texte, un document Word n'a pas de camembert de conversion.
        let word = Input { category: Category::Text, format: "docx".into() };
        assert!(actions(WheelKind::Conversion, &[word], &windows).is_empty());
    }

    #[test]
    fn extension_table() {
        assert_eq!(input_for_extension("JPG"), image("jpeg"));
        assert_eq!(input_for_extension(".tif"), image("tiff"));
        assert_eq!(input_for_extension("md").category, Category::Text);
        assert_eq!(input_for_extension("mp3"), Input { category: Category::Other, format: "mp3".into() });
    }

    #[test]
    fn json_shape() {
        let action = Action::new("PNG", "photo", Operation::ConvertImages, Some("png"));
        assert_eq!(
            serde_json::to_string(&action).unwrap(),
            r#"{"id":"convert_images:png","title":"PNG","icon":"photo","operation":"convert_images","format":"png"}"#
        );
    }
}
