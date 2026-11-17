//! PDF : structure avec `lopdf` (fusion, métadonnées, pages d'images), rendu avec `hayro`.

use std::path::Path;

use hayro::hayro_interpret::InterpreterSettings;
use hayro::hayro_syntax::Pdf;
use hayro::vello_cpu::color::palette::css::WHITE;
use hayro::{PixmapSettings, RenderCache, RenderSettings};
use image::{DynamicImage, RgbImage};
use lopdf::{dictionary, Dictionary, Document, Object, ObjectId, Stream};

use super::{images, ConvertError};

/// Attributs qu'une page peut hériter de ses nœuds parents.
const INHERITED: [&[u8]; 4] = [b"Resources", b"MediaBox", b"CropBox", b"Rotate"];

/// Format A4 en points : une image plus grande y est ramenée, pour un PDF imprimable.
const A4: (f32, f32) = (595.0, 842.0);

/// Ouvre un PDF ; un PDF protégé sans mot de passe est déchiffré, sinon la raison est renvoyée.
pub fn open(path: &Path) -> Result<Document, String> {
    let mut document = Document::load(path).map_err(|error| error.to_string())?;
    if document.is_encrypted() {
        document.decrypt("").map_err(|error| error.to_string())?;
    }
    Ok(document)
}

/// Retire le dictionnaire d'informations (auteur, titre, logiciel…) et les métadonnées XMP.
pub fn strip_metadata(document: &mut Document) {
    document.trailer.remove(b"Info");
    if let Ok(catalog) = document.catalog_mut() {
        catalog.remove(b"Metadata");
    }
    let pages: Vec<ObjectId> = document.get_pages().into_values().collect();
    for page in pages {
        if let Ok(Object::Dictionary(dictionary)) = document.get_object_mut(page) {
            dictionary.remove(b"Metadata");
        }
    }
    document.prune_objects();
}

/// Un document d'une page portant l'image (JPEG), à sa taille ou ramenée dans un A4.
pub fn image_document(image: &DynamicImage, quality: u8) -> Document {
    let (width, height) = (image.width() as f32, image.height() as f32);
    let (max_width, max_height) = if width > height { (A4.1, A4.0) } else { A4 };
    let scale = (max_width / width).min(max_height / height).min(1.0);
    let (page_width, page_height) = (width * scale, height * scale);

    let mut document = Document::with_version("1.5");
    let pages_id = document.new_object_id();
    let image_id = document.add_object(
        Stream::new(
            dictionary! {
                "Type" => "XObject",
                "Subtype" => "Image",
                "Width" => image.width() as i64,
                "Height" => image.height() as i64,
                "ColorSpace" => "DeviceRGB",
                "BitsPerComponent" => 8,
                "Filter" => "DCTDecode",
            },
            images::jpeg_bytes(image, quality),
        )
        .with_compression(false),
    );
    let content = format!("q {page_width} 0 0 {page_height} 0 0 cm /Im0 Do Q");
    let content_id = document.add_object(Stream::new(Dictionary::new(), content.into_bytes()));
    let page_id = document.add_object(dictionary! {
        "Type" => "Page",
        "Parent" => pages_id,
        "MediaBox" => vec![0.into(), 0.into(), page_width.into(), page_height.into()],
        "Contents" => content_id,
        "Resources" => dictionary! { "XObject" => dictionary! { "Im0" => image_id } },
    });
    document.objects.insert(pages_id, Object::Dictionary(dictionary! { "Type" => "Pages", "Kids" => vec![page_id.into()], "Count" => 1 }));
    let catalog_id = document.add_object(dictionary! { "Type" => "Catalog", "Pages" => pages_id });
    document.trailer.set("Root", catalog_id);
    document
}

/// Assemble les documents dans l'ordre, page après page. Signets et formulaires ne sont pas repris.
pub fn merge(documents: Vec<Document>) -> Document {
    let mut merged = Document::with_version("1.5");
    let mut pages: Vec<ObjectId> = Vec::new();
    let mut next_id = 1;

    for mut document in documents {
        document.renumber_objects_with(next_id);
        next_id = document.max_id + 1;
        let page_ids: Vec<ObjectId> = document.get_pages().into_values().collect();
        // Une page hérite de ses parents : on recopie ces attributs avant de jeter l'arbre d'origine.
        for page_id in &page_ids {
            let inherited = inherited_attributes(&document, *page_id);
            if let Ok(Object::Dictionary(page)) = document.get_object_mut(*page_id) {
                for (key, value) in inherited {
                    if !page.has(&key) {
                        page.set(key, value);
                    }
                }
            }
        }
        pages.extend(&page_ids);
        for (id, object) in document.objects {
            let kind = object.as_dict().ok().and_then(|d| d.get(b"Type").ok()).and_then(|t| t.as_name().ok()).unwrap_or(b"");
            // L'arbre des pages et le catalogue sont reconstruits ; les signets pointeraient dans le vide.
            if !matches!(kind, b"Catalog" | b"Pages" | b"Outlines" | b"Outline") || page_ids.contains(&id) {
                merged.objects.insert(id, object);
            }
        }
    }

    merged.max_id = next_id.saturating_sub(1);
    let pages_id = merged.new_object_id();
    for page_id in &pages {
        if let Ok(Object::Dictionary(page)) = merged.get_object_mut(*page_id) {
            page.set("Parent", pages_id);
        }
    }
    let kids: Vec<Object> = pages.iter().map(|id| Object::Reference(*id)).collect();
    merged.objects.insert(pages_id, Object::Dictionary(dictionary! { "Type" => "Pages", "Count" => kids.len() as i64, "Kids" => kids }));
    let catalog_id = merged.add_object(dictionary! { "Type" => "Catalog", "Pages" => pages_id });
    merged.trailer.set("Root", catalog_id);
    merged.prune_objects();
    merged.renumber_objects();
    merged.compress();
    merged
}

/// Attributs hérités des nœuds parents de la page (le plus proche l'emporte).
fn inherited_attributes(document: &Document, page_id: ObjectId) -> Vec<(Vec<u8>, Object)> {
    let mut found: Vec<(Vec<u8>, Object)> = Vec::new();
    let mut current = document.get_dictionary(page_id).ok();
    let mut depth = 0;
    while let Some(node) = current {
        for key in INHERITED {
            if let (Ok(value), false) = (node.get(key), found.iter().any(|(k, _)| k == key)) {
                found.push((key.to_vec(), value.clone()));
            }
        }
        depth += 1;
        current = match node.get(b"Parent").and_then(Object::as_reference) {
            Ok(parent) if depth < 64 => document.get_dictionary(parent).ok(),
            _ => None,
        };
    }
    found
}

pub enum RenderError {
    /// Le PDF ne s'ouvre pas.
    Unreadable,
    /// L'appelant a échoué sur une page.
    Page(ConvertError),
}

/// Rend chaque page sur fond blanc à la résolution demandée et la passe à `each(index, total, image)`.
pub fn render(bytes: &[u8], dpi: f32, each: impl FnMut(usize, usize, DynamicImage) -> Result<(), ConvertError>) -> Result<(), RenderError> {
    render_selected(bytes, dpi, |_| true, each)
}

/// Comme [`render`], pour les seules pages retenues par `wanted(index)`.
pub fn render_selected(
    bytes: &[u8],
    dpi: f32,
    wanted: impl Fn(usize) -> bool,
    mut each: impl FnMut(usize, usize, DynamicImage) -> Result<(), ConvertError>,
) -> Result<(), RenderError> {
    let pdf = Pdf::new(bytes.to_vec()).map_err(|_| RenderError::Unreadable)?;
    let cache = RenderCache::new();
    let scale = dpi / 72.0;
    let settings = PixmapSettings { x_scale: scale, y_scale: scale, bg_color: WHITE };
    let pages = pdf.pages();
    let count = pages.len();
    for (index, page) in pages.iter().enumerate().filter(|(index, _)| wanted(*index)) {
        let pixmap = hayro::render(page, &cache, &InterpreterSettings::default(), &RenderSettings::default(), &settings);
        let (width, height) = (u32::from(pixmap.width()), u32::from(pixmap.height()));
        // Fond blanc opaque : les valeurs prémultipliées sont les valeurs réelles.
        let rgb: Vec<u8> = pixmap.data_as_u8_slice().as_chunks::<4>().0.iter().flat_map(|pixel| [pixel[0], pixel[1], pixel[2]]).collect();
        let image = RgbImage::from_raw(width, height, rgb).ok_or(RenderError::Unreadable)?;
        each(index, count, DynamicImage::ImageRgb8(image)).map_err(RenderError::Page)?;
    }
    Ok(())
}

/// Nombre de pages, ou `None` si le PDF ne s'ouvre pas.
pub fn page_count(bytes: &[u8]) -> Option<usize> {
    Pdf::new(bytes.to_vec()).ok().map(|pdf| pdf.pages().len())
}
