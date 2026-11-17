//! Texte d'un document : couche texte des PDF (`pdf-extract`), OCR pour les images et les pages
//! scannées (Tesseract), lecture directe des documents texte.

use std::io::Read;
use std::path::Path;

use bergamote_core::catalog::{self, Category};

use super::{extension, pdf, ConvertError, Converter, Result};

/// En dessous, la page est considérée comme scannée et passe à l'OCR.
const MINIMUM_TEXT_PER_PAGE: usize = 20;
/// Résolution de rendu des pages envoyées à l'OCR.
pub const OCR_DPI: f32 = 220.0;

pub fn of(converter: &Converter, path: &Path) -> Result<String> {
    let input = catalog::input_for_extension(&extension(path));
    match input.category {
        Category::Pdf => pdf_text(converter, path),
        Category::Image => {
            let tesseract = converter.tesseract.as_ref().ok_or_else(|| converter.error("error.ocr_missing", &[]))?;
            tesseract.recognize(&converter.load_image(path)?, converter.language).map_err(ConvertError)
        }
        Category::Text => document_text(converter, path, &input.format),
        Category::Other => Err(converter.unreadable(path)),
    }
}

fn pdf_text(converter: &Converter, path: &Path) -> Result<String> {
    let bytes = converter.read(path)?;
    let count = pdf::page_count(&bytes).ok_or_else(|| converter.unreadable(path))?;
    // `pdf-extract` peut paniquer sur un PDF inhabituel : la page passe alors pour vide.
    let extracted = std::panic::catch_unwind(|| pdf_extract::extract_text_from_mem_by_pages(&bytes)).ok().and_then(|result| result.ok());
    let mut pages: Vec<String> = extracted.unwrap_or_default().into_iter().map(|page| page.trim().to_owned()).collect();
    pages.resize(count, String::new());

    let scanned = |index: usize| pages[index].chars().count() < MINIMUM_TEXT_PER_PAGE;
    if (0..count).any(scanned) {
        match &converter.tesseract {
            Some(tesseract) => {
                let mut recognized = Vec::new();
                pdf::render_selected(&bytes, OCR_DPI, scanned, |index, _, page| {
                    recognized.push((index, tesseract.recognize(&page, converter.language).map_err(ConvertError)?));
                    Ok(())
                })
                .map_err(|error| converter.pdf_error(path, error))?;
                for (index, text) in recognized {
                    pages[index] = text;
                }
            }
            // Aucun texte du tout et pas d'OCR : on le dit plutôt que d'écrire un fichier vide.
            None if pages.iter().all(String::is_empty) => return Err(converter.error("error.ocr_missing", &[])),
            None => {}
        }
    }
    Ok(pages.join("\n\n"))
}

fn document_text(converter: &Converter, path: &Path, format: &str) -> Result<String> {
    let unreadable = || converter.unreadable(path);
    match format {
        "txt" => Ok(decode(&converter.read(path)?)),
        "rtf" => Ok(rtf_text(&converter.read(path)?)),
        "docx" => zip_xml_text(path, "word/document.xml", &Office::WORD).ok_or_else(unreadable),
        "odt" => zip_xml_text(path, "content.xml", &Office::OPEN_DOCUMENT).ok_or_else(unreadable),
        "doc" => Err(converter.error("error.doc_unsupported", &[])),
        _ => Err(unreadable()),
    }
}

/// UTF-8, sinon Windows-1252 (anciens fichiers texte).
fn decode(bytes: &[u8]) -> String {
    match std::str::from_utf8(bytes) {
        Ok(text) => text.trim_start_matches('\u{feff}').to_owned(),
        Err(_) => encoding_rs::WINDOWS_1252.decode(bytes).0.into_owned(),
    }
}

/// Balises d'un format bureautique (une archive ZIP de XML).
struct Office {
    paragraphs: &'static [&'static str],
    /// Seul le texte de cette balise compte ; `None` : tout le texte du paragraphe.
    text: Option<&'static str>,
    breaks: &'static [&'static str],
    tab: &'static str,
    /// Espaces répétées (OpenDocument : `<text:s text:c="3"/>`).
    space: Option<&'static str>,
}

impl Office {
    const WORD: Office = Office { paragraphs: &["p"], text: Some("t"), breaks: &["br", "cr"], tab: "tab", space: None };
    const OPEN_DOCUMENT: Office = Office { paragraphs: &["p", "h"], text: None, breaks: &["line-break"], tab: "tab", space: Some("s") };
}

fn zip_xml_text(path: &Path, entry: &str, office: &Office) -> Option<String> {
    let mut archive = zip::ZipArchive::new(std::fs::File::open(path).ok()?).ok()?;
    let mut xml = String::new();
    archive.by_name(entry).ok()?.read_to_string(&mut xml).ok()?;
    let document = roxmltree::Document::parse(&xml).ok()?;
    let is_paragraph = |node: &roxmltree::Node| node.is_element() && office.paragraphs.contains(&node.tag_name().name());
    let lines: Vec<String> = document
        .descendants()
        .filter(|node| is_paragraph(node) && !node.ancestors().skip(1).any(|parent| is_paragraph(&parent)))
        .map(|paragraph| {
            let mut line = String::new();
            for node in paragraph.descendants() {
                let name = node.tag_name().name();
                if node.is_text() {
                    let parent = node.parent().map(|p| p.tag_name().name());
                    if office.text.is_none() || parent == office.text {
                        line.push_str(node.text().unwrap_or(""));
                    }
                } else if !node.is_element() {
                } else if office.breaks.contains(&name) {
                    line.push('\n');
                } else if name == office.tab {
                    line.push('\t');
                } else if Some(name) == office.space {
                    let count = node.attributes().find(|a| a.name() == "c").and_then(|a| a.value().parse().ok()).unwrap_or(1);
                    line.push_str(&" ".repeat(count));
                }
            }
            line
        })
        .collect();
    Some(lines.join("\n"))
}

/// Texte d'un document RTF : on suit les groupes, on ignore les tables (polices, couleurs,
/// styles, images) et on traduit les mots de contrôle qui portent du texte.
pub fn rtf_text(source: &[u8]) -> String {
    const SKIPPED: [&str; 14] =
        ["fonttbl", "colortbl", "stylesheet", "info", "pict", "object", "header", "footer", "footnote", "generator", "themedata", "datastore", "listtable", "listoverridetable"];
    let mut text = String::new();
    // Par groupe : (ignoré, nombre de caractères de repli après \uN).
    let mut groups: Vec<(bool, usize)> = vec![(false, 1)];
    let mut pending_skip = 0usize;
    let mut index = 0;
    while index < source.len() {
        let (skipping, fallback) = *groups.last().unwrap_or(&(false, 1));
        match source[index] {
            b'{' => {
                groups.push((skipping, fallback));
                index += 1;
            }
            b'}' => {
                if groups.len() > 1 {
                    groups.pop();
                }
                index += 1;
            }
            b'\\' => {
                index += 1;
                let Some(&next) = source.get(index) else { break };
                if next == b'\'' {
                    // \'hh : un octet Windows-1252.
                    let byte = source.get(index + 1..index + 3).and_then(|hex| u8::from_str_radix(std::str::from_utf8(hex).ok()?, 16).ok());
                    index += 3;
                    if pending_skip > 0 {
                        pending_skip -= 1;
                    } else if let (Some(byte), false) = (byte, skipping) {
                        text.push_str(&encoding_rs::WINDOWS_1252.decode(&[byte]).0);
                    }
                } else if next.is_ascii_alphabetic() {
                    let start = index;
                    while source.get(index).is_some_and(u8::is_ascii_alphabetic) {
                        index += 1;
                    }
                    let word = std::str::from_utf8(&source[start..index]).unwrap_or("");
                    let number_start = index;
                    if source.get(index) == Some(&b'-') {
                        index += 1;
                    }
                    while source.get(index).is_some_and(u8::is_ascii_digit) {
                        index += 1;
                    }
                    let number: Option<i32> = std::str::from_utf8(&source[number_start..index]).ok().and_then(|n| n.parse().ok());
                    if source.get(index) == Some(&b' ') {
                        index += 1;
                    }
                    if SKIPPED.contains(&word) {
                        if let Some(group) = groups.last_mut() {
                            group.0 = true;
                        }
                        continue;
                    }
                    match word {
                        "uc" => {
                            if let (Some(group), Some(count)) = (groups.last_mut(), number) {
                                group.1 = count.max(0) as usize;
                            }
                        }
                        "u" => {
                            if let (Some(code), false) = (number, skipping) {
                                let code = if code < 0 { code + 65_536 } else { code } as u32;
                                text.push(char::from_u32(code).unwrap_or('\u{fffd}'));
                            }
                            pending_skip = fallback;
                        }
                        _ if skipping => {}
                        "par" | "line" | "sect" | "page" => text.push('\n'),
                        "tab" | "cell" => text.push('\t'),
                        "row" => text.push('\n'),
                        "emdash" => text.push('—'),
                        "endash" => text.push('–'),
                        "lquote" => text.push('‘'),
                        "rquote" => text.push('’'),
                        "ldblquote" => text.push('“'),
                        "rdblquote" => text.push('”'),
                        "bullet" => text.push('•'),
                        _ => {}
                    }
                } else {
                    index += 1;
                    match next {
                        // \* : destination facultative, que l'on ne connaît pas.
                        b'*' => {
                            if let Some(group) = groups.last_mut() {
                                group.0 = true;
                            }
                        }
                        _ if skipping => {}
                        b'\\' | b'{' | b'}' => text.push(next as char),
                        b'~' => text.push('\u{a0}'),
                        b'_' => text.push('-'),
                        b'\n' | b'\r' => text.push('\n'),
                        _ => {}
                    }
                }
            }
            b'\r' | b'\n' => index += 1,
            byte => {
                index += 1;
                if pending_skip > 0 {
                    pending_skip -= 1;
                } else if !skipping {
                    text.push_str(&encoding_rs::WINDOWS_1252.decode(&[byte]).0);
                }
            }
        }
    }
    text.trim_end().to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rtf_keeps_text_and_drops_tables() {
        let rtf = br"{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica;}}{\*\generator Riched20;}\f0\fs24 Premi\'e8re ligne\par Seconde \u8212? ligne \{ok\}\par}";
        assert_eq!(rtf_text(rtf), "Première ligne\nSeconde — ligne {ok}");
    }

    #[test]
    fn legacy_text_files_are_decoded() {
        assert_eq!(decode("été".as_bytes()), "été");
        assert_eq!(decode(&[0xE9, 0x74, 0xE9]), "été");
    }
}
