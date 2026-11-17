//! Chaque opération du camembert sur de vrais fichiers, dans un dossier temporaire. Tout est en
//! Rust pur : ces tests tournent sur n'importe quel système.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use bergamote_core::catalog::{self, Action};
use bergamote_core::detector::WheelKind;
use bergamote_core::i18n::Language;
use bergamote_linux::convert::{abilities, Converter};
use image::{DynamicImage, Rgb, RgbImage, Rgba, RgbaImage};
use lopdf::{dictionary, Document, Object, Stream};

/// Dossier temporaire propre à un test, supprimé à la fin.
struct Folder(PathBuf);

impl Folder {
    fn new(name: &str) -> Self {
        let path = std::env::temp_dir().join(format!("bergamote-test-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).unwrap();
        Folder(path)
    }

    fn path(&self, name: &str) -> PathBuf {
        self.0.join(name)
    }
}

impl Drop for Folder {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn converter() -> Converter {
    Converter { language: Language::French, tesseract: None, ..Converter::default() }
}

/// La part d'identifiant `id` que le camembert propose pour ces fichiers.
fn action(kind: WheelKind, id: &str, files: &[&Path]) -> Action {
    let inputs: Vec<_> = files.iter().map(|f| catalog::input_for_extension(&f.extension().unwrap().to_string_lossy())).collect();
    let actions = catalog::actions(kind, &inputs, &abilities(false), Language::French);
    actions.into_iter().find(|a| a.id == id).unwrap_or_else(|| panic!("pas de part {id}"))
}

fn gradient(width: u32, height: u32) -> DynamicImage {
    DynamicImage::ImageRgb8(RgbImage::from_fn(width, height, |x, y| Rgb([(x * 255 / width) as u8, (y * 255 / height) as u8, 180])))
}

/// Bruit : une image qui se compresse mal sans perte.
fn noise(width: u32, height: u32) -> DynamicImage {
    let mut state = 0x9E37_79B9u32;
    DynamicImage::ImageRgb8(RgbImage::from_fn(width, height, |_, _| {
        state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        Rgb([(state >> 24) as u8, (state >> 16) as u8, (state >> 8) as u8])
    }))
}

fn half_transparent(width: u32, height: u32) -> DynamicImage {
    DynamicImage::ImageRgba8(RgbaImage::from_fn(width, height, |x, _| if x < width / 2 { Rgba([255, 0, 0, 0]) } else { Rgba([0, 0, 255, 255]) }))
}

/// PDF de `pages` pages (288 × 144 points) portant chacune une ligne de texte.
fn text_pdf(path: &Path, pages: usize, author: Option<&str>) {
    let mut document = Document::with_version("1.5");
    let pages_id = document.new_object_id();
    let font_id = document.add_object(dictionary! { "Type" => "Font", "Subtype" => "Type1", "BaseFont" => "Helvetica", "Encoding" => "WinAnsiEncoding" });
    let mut kids = Vec::new();
    for index in 0..pages {
        let content = format!("BT /F1 18 Tf 20 100 Td (Bonjour Bergamote, page numero {}) Tj ET", index + 1);
        let content_id = document.add_object(Stream::new(dictionary! {}, content.into_bytes()));
        // Pas de MediaBox sur la page : elle est héritée du nœud parent.
        let page_id = document.add_object(dictionary! {
            "Type" => "Page", "Parent" => pages_id, "Contents" => content_id,
            "Resources" => dictionary! { "Font" => dictionary! { "F1" => font_id } },
        });
        kids.push(Object::Reference(page_id));
    }
    document.objects.insert(
        pages_id,
        Object::Dictionary(dictionary! { "Type" => "Pages", "Count" => pages as i64, "Kids" => kids, "MediaBox" => vec![0.into(), 0.into(), 288.into(), 144.into()] }),
    );
    let catalog_id = document.add_object(dictionary! { "Type" => "Catalog", "Pages" => pages_id });
    document.trailer.set("Root", catalog_id);
    if let Some(author) = author {
        let info_id = document.add_object(dictionary! { "Author" => Object::string_literal(author), "Title" => Object::string_literal("Confidentiel") });
        document.trailer.set("Info", info_id);
    }
    document.save(path).unwrap();
}

fn media_box(document: &Document, page: u32) -> Vec<f32> {
    let id = document.get_pages()[&page];
    let dictionary = document.get_dictionary(id).unwrap();
    dictionary.get(b"MediaBox").unwrap().as_array().unwrap().iter().map(|n| n.as_float().unwrap()).collect()
}

#[test]
fn converts_next_to_the_original_without_overwriting() {
    let folder = Folder::new("convert");
    let png = folder.path("logo.png");
    half_transparent(64, 48).save(&png).unwrap();
    let to_jpeg = action(WheelKind::Conversion, "convert_images:jpeg", &[&png]);

    let first = converter().perform(&to_jpeg, &[png.clone()]).unwrap();
    let second = converter().perform(&to_jpeg, &[png.clone()]).unwrap();

    assert_eq!(first, [folder.path("logo.jpeg")]);
    assert_eq!(second, [folder.path("logo 2.jpeg")]);
    let decoded = image::open(&first[0]).unwrap().to_rgb8();
    assert_eq!((decoded.width(), decoded.height()), (64, 48));
    // La moitié transparente est aplatie sur du blanc, pas sur du noir.
    assert!(decoded.get_pixel(5, 5).0.iter().all(|c| *c > 240), "{:?}", decoded.get_pixel(5, 5));
    assert!(png.exists(), "l'original reste en place");
}

#[test]
fn writes_every_declared_format() {
    let folder = Folder::new("formats");
    let jpeg = folder.path("photo.jpg");
    gradient(40, 30).save(&jpeg).unwrap();
    for format in ["png", "webp", "tiff", "gif", "bmp"] {
        let action = action(WheelKind::Conversion, &format!("convert_images:{format}"), &[&jpeg]);
        let output = converter().perform(&action, &[jpeg.clone()]).unwrap();
        assert_eq!(output, [folder.path(&format!("photo.{format}"))]);
        let decoded = image::open(&output[0]).unwrap();
        assert_eq!((decoded.width(), decoded.height()), (40, 30), "{format}");
    }
}

#[test]
fn compresses_large_images_and_skips_useless_results() {
    let folder = Folder::new("compress");
    let photo = folder.path("photo.png");
    noise(3000, 2000).save(&photo).unwrap();
    let compressed = converter().perform(&action(WheelKind::Tools, "compress", &[&photo]), &[photo.clone()]).unwrap();
    assert_eq!(compressed, [folder.path("photo (compressé).jpeg")]);
    assert!(fs::metadata(&compressed[0]).unwrap().len() < fs::metadata(&photo).unwrap().len());
    assert_eq!(image::open(&compressed[0]).unwrap().width(), 2560);

    // Un PNG minuscule : le JPEG, avec ses en-têtes, serait plus lourd. Rien n'est créé.
    let tiny = folder.path("tiny.png");
    gradient(8, 8).save(&tiny).unwrap();
    assert!(converter().perform(&action(WheelKind::Tools, "compress", &[&tiny]), &[tiny.clone()]).unwrap().is_empty());
    assert!(!folder.path("tiny (compressé).jpeg").exists());
}

#[test]
fn file_suffixes_follow_the_language() {
    let folder = Folder::new("language");
    let photo = folder.path("photo.png");
    noise(400, 300).save(&photo).unwrap();
    let english = Converter { language: Language::English, tesseract: None, ..Converter::default() };
    let compressed = english.perform(&action(WheelKind::Tools, "compress", &[&photo]), &[photo.clone()]).unwrap();
    assert_eq!(compressed, [folder.path("photo (compressed).jpeg")]);
}

#[test]
fn strips_metadata_from_images_and_pdfs() {
    let folder = Folder::new("metadata");
    let jpeg = folder.path("vacances.jpg");
    gradient(40, 30).save(&jpeg).unwrap();
    let clean = converter().perform(&action(WheelKind::Tools, "strip_metadata", &[&jpeg]), &[jpeg.clone()]).unwrap();
    assert_eq!(clean, [folder.path("vacances (sans métadonnées).jpeg")]);
    assert_eq!(image::open(&clean[0]).unwrap().width(), 40);

    let pdf = folder.path("rapport.pdf");
    text_pdf(&pdf, 1, Some("Camille Martin"));
    assert!(fs::read(&pdf).unwrap().windows(7).any(|w| w == b"Camille"));
    let clean = converter().perform(&action(WheelKind::Tools, "strip_metadata", &[&pdf]), &[pdf.clone()]).unwrap();
    assert_eq!(clean, [folder.path("rapport (sans métadonnées).pdf")]);
    let bytes = fs::read(&clean[0]).unwrap();
    assert!(!bytes.windows(7).any(|w| w == b"Camille"), "l'auteur a disparu");
    let reread = Document::load_mem(&bytes).unwrap();
    assert!(reread.trailer.get(b"Info").is_err());
    assert_eq!(reread.get_pages().len(), 1);
}

#[test]
fn merges_pdfs_and_images_in_drag_order() {
    let folder = Folder::new("merge");
    let pdf = folder.path("devis.pdf");
    text_pdf(&pdf, 2, None);
    let signature = folder.path("signature.png");
    half_transparent(120, 60).save(&signature).unwrap();
    let scan = folder.path("scan.jpg");
    gradient(2000, 3000).save(&scan).unwrap();
    let files = [signature.clone(), pdf.clone(), scan.clone()];
    let merge = action(WheelKind::Conversion, "merge_pdf", &[&signature, &pdf, &scan]);

    let merged = converter().perform(&merge, &files).unwrap();

    assert_eq!(merged, [folder.path("signature (fusion).pdf")]);
    let document = Document::load(&merged[0]).unwrap();
    assert_eq!(document.get_pages().len(), 4);
    // L'ordre du glisser est respecté, et les pages du PDF gardent leur taille héritée.
    assert_eq!(media_box(&document, 1), [0.0, 0.0, 120.0, 60.0]);
    assert_eq!(media_box(&document, 2), [0.0, 0.0, 288.0, 144.0]);
    assert_eq!(media_box(&document, 3), [0.0, 0.0, 288.0, 144.0]);
    // Une grande image est ramenée dans un A4.
    let scan_box = media_box(&document, 4);
    assert!((scan_box[3] - 842.0).abs() < 0.5 && (scan_box[2] - 561.3).abs() < 0.5, "{scan_box:?}");
    // Le résultat se rend, page par page.
    let pages = converter().perform(&action(WheelKind::Conversion, "render_pages:png", &[&merged[0]]), &merged).unwrap();
    assert_eq!(pages.len(), 4);
    let text = fs::read_to_string(&converter().perform(&action(WheelKind::Tools, "extract_text", &[&merged[0]]), &merged).unwrap()[0]).unwrap();
    assert!(text.contains("page numero 2"), "{text}");
}

#[test]
fn renders_each_pdf_page_as_an_image() {
    let folder = Folder::new("render");
    let pdf = folder.path("plan.pdf");
    text_pdf(&pdf, 2, None);
    let pages = converter().perform(&action(WheelKind::Conversion, "render_pages:png", &[&pdf]), &[pdf.clone()]).unwrap();

    assert_eq!(pages, [folder.path("plan-p1.png"), folder.path("plan-p2.png")]);
    let page = image::open(&pages[0]).unwrap().to_rgb8();
    assert_eq!((page.width(), page.height()), (600, 300)); // 4 × 2 pouces à 150 ppp
    assert_eq!(page.get_pixel(590, 10).0, [255, 255, 255], "fond blanc");
    assert!(page.pixels().any(|p| p.0[0] < 80), "le texte est dessiné");

    let single = folder.path("page.pdf");
    text_pdf(&single, 1, None);
    let pages = converter().perform(&action(WheelKind::Conversion, "render_pages:jpeg", &[&single]), &[single.clone()]).unwrap();
    assert_eq!(pages, [folder.path("page.jpeg")]);
}

#[test]
fn extracts_text_from_pdfs_and_office_documents() {
    let folder = Folder::new("text");
    let pdf = folder.path("lettre.pdf");
    text_pdf(&pdf, 2, None);
    let output = converter().perform(&action(WheelKind::Conversion, "extract_text", &[&pdf]), &[pdf.clone()]).unwrap();
    assert_eq!(output, [folder.path("lettre.txt")]);
    let text = fs::read_to_string(&output[0]).unwrap();
    assert!(text.contains("Bonjour Bergamote, page numero 1") && text.contains("page numero 2"), "{text}");

    let docx = folder.path("note.docx");
    let mut archive = zip::ZipWriter::new(fs::File::create(&docx).unwrap());
    archive.start_file("word/document.xml", zip::write::SimpleFileOptions::default()).unwrap();
    archive
        .write_all(
            br#"<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
<w:p><w:r><w:t>Bonjour</w:t></w:r><w:r><w:tab/><w:t xml:space="preserve">Camille</w:t></w:r></w:p>
<w:p><w:r><w:instrText>PAGE</w:instrText><w:t>Fin</w:t></w:r></w:p>
</w:body></w:document>"#,
        )
        .unwrap();
    archive.finish().unwrap();
    let extract = action(WheelKind::Tools, "extract_text", &[&docx]);
    let output = converter().perform(&extract, &[docx.clone()]).unwrap();
    assert_eq!(fs::read_to_string(&output[0]).unwrap(), "Bonjour\tCamille\nFin");

    let odt = folder.path("memo.odt");
    let mut archive = zip::ZipWriter::new(fs::File::create(&odt).unwrap());
    archive.start_file("content.xml", zip::write::SimpleFileOptions::default()).unwrap();
    archive
        .write_all(
            br#"<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"><office:body><office:text>
<text:h>Titre</text:h><text:p>Un<text:s text:c="2"/>deux<text:line-break/>trois <text:span>quatre</text:span></text:p>
</office:text></office:body></office:document-content>"#,
        )
        .unwrap();
    archive.finish().unwrap();
    let output = converter().perform(&action(WheelKind::Tools, "extract_text", &[&odt]), &[odt.clone()]).unwrap();
    assert_eq!(fs::read_to_string(&output[0]).unwrap(), "Titre\nUn  deux\ntrois quatre");

    let rtf = folder.path("memo.rtf");
    fs::write(&rtf, br"{\rtf1\ansi Premi\'e8re ligne\par Seconde ligne}").unwrap();
    let output = converter().perform(&action(WheelKind::Tools, "extract_text", &[&rtf]), &[rtf.clone()]).unwrap();
    assert_eq!(fs::read_to_string(&output[0]).unwrap(), "Première ligne\nSeconde ligne");
}

#[test]
fn wheel_offers_only_what_this_system_can_do() {
    let image = [catalog::input_for_extension("jpg")];
    let titles = |actions: Vec<Action>| actions.into_iter().map(|a| a.title).collect::<Vec<_>>();
    // Sans Tesseract : ni « Texte » ni « Cherchable » pour une image.
    assert_eq!(titles(catalog::actions(WheelKind::Tools, &image, &abilities(false), Language::French)), ["Compresser", "Anonymiser"]);
    assert_eq!(titles(catalog::actions(WheelKind::Tools, &image, &abilities(true), Language::English)), ["Compress", "Anonymize", "Searchable", "Text"]);
    assert_eq!(titles(catalog::actions(WheelKind::Conversion, &image, &abilities(false), Language::French)), ["PNG", "WEBP", "TIFF", "GIF", "BMP", "PDF"]);
    // Un format que la crate `image` ne lit pas : pas de camembert.
    assert!(catalog::actions(WheelKind::Conversion, &[catalog::input_for_extension("heic")], &abilities(false), Language::French).is_empty());
    // Sans OCR, une image seule ne peut pas donner de texte : l'erreur le dit.
    let folder = Folder::new("ocr");
    let scan = folder.path("scan.png");
    gradient(20, 20).save(&scan).unwrap();
    let text = Action { id: "extract_text".into(), title: "Texte".into(), icon: "extract".into(), operation: catalog::Operation::ExtractText, format: None };
    let error = converter().perform(&text, &[scan]).unwrap_err();
    assert_eq!(error.to_string(), "Installez Tesseract pour reconnaître le texte des images");
}
