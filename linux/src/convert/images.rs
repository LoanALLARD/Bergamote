//! Lecture et écriture d'images avec la crate `image`.

use std::io::{BufWriter, Cursor};
use std::path::Path;

use image::codecs::jpeg::JpegEncoder;
use image::codecs::png::{CompressionType, FilterType as PngFilter, PngEncoder};
use image::imageops::FilterType;
use image::{DynamicImage, ImageDecoder, ImageFormat, ImageReader, Rgb, RgbImage};

pub enum SaveError {
    /// Format que l'app ne sait pas écrire.
    Unsupported,
    Write,
}

/// Image du fichier, redressée selon son orientation EXIF. Le format est reconnu d'après le
/// contenu, pas d'après l'extension.
pub fn load(path: &Path) -> image::ImageResult<DynamicImage> {
    let mut decoder = ImageReader::open(path)?.with_guessed_format()?.into_decoder()?;
    let orientation = decoder.orientation().ok();
    let mut image = DynamicImage::from_decoder(decoder)?;
    if let Some(orientation) = orientation {
        image.apply_orientation(orientation);
    }
    Ok(image)
}

/// Réduit l'image pour que son plus grand côté tienne dans `max_pixel_size`.
pub fn fit(image: DynamicImage, max_pixel_size: u32) -> DynamicImage {
    if image.width().max(image.height()) <= max_pixel_size {
        return image;
    }
    image.resize(max_pixel_size, max_pixel_size, FilterType::Lanczos3)
}

/// JPEG et BMP n'ont pas de transparence : on aplatit sur du blanc plutôt que sur du noir.
pub fn flatten_on_white(image: &DynamicImage) -> RgbImage {
    if !image.color().has_alpha() {
        return image.to_rgb8();
    }
    let rgba = image.to_rgba8();
    let mut flat = RgbImage::new(rgba.width(), rgba.height());
    for (source, target) in rgba.pixels().zip(flat.pixels_mut()) {
        let alpha = u32::from(source[3]);
        let blend = |channel: u8| ((u32::from(channel) * alpha + 255 * (255 - alpha) + 127) / 255) as u8;
        *target = Rgb([blend(source[0]), blend(source[1]), blend(source[2])]);
    }
    flat
}

pub fn jpeg_bytes(image: &DynamicImage, quality: u8) -> Vec<u8> {
    let mut bytes = Vec::new();
    // Écrire en mémoire ne peut échouer que pour une image vide, que `load` ne renvoie pas.
    let _ = flatten_on_white(image).write_with_encoder(JpegEncoder::new_with_quality(&mut bytes, quality.clamp(1, 100)));
    bytes
}

pub fn png_bytes(image: &DynamicImage) -> Vec<u8> {
    let mut bytes = Vec::new();
    let _ = eight_bits(image).write_to(&mut Cursor::new(&mut bytes), ImageFormat::Png);
    bytes
}

/// Encode l'image dans un nouveau fichier ; échoue si le fichier existe déjà.
pub fn save(image: &DynamicImage, path: &Path, format: &str, quality: u8) -> Result<(), SaveError> {
    let bytes = encode(image, format, quality)?;
    super::write_new(path, &bytes).map_err(|_| SaveError::Write)
}

fn encode(image: &DynamicImage, format: &str, quality: u8) -> Result<Vec<u8>, SaveError> {
    let mut bytes = Vec::new();
    let result = match format {
        "jpeg" => return Ok(jpeg_bytes(image, quality)),
        "bmp" => DynamicImage::ImageRgb8(flatten_on_white(image)).write_to(&mut Cursor::new(&mut bytes), ImageFormat::Bmp),
        // Compression maximale : le PNG reste sans perte, autant qu'il soit petit.
        "png" => eight_bits(image).write_with_encoder(PngEncoder::new_with_quality(BufWriter::new(&mut bytes), CompressionType::Best, PngFilter::Adaptive)),
        "tiff" => eight_bits(image).write_to(&mut Cursor::new(&mut bytes), ImageFormat::Tiff),
        "gif" => DynamicImage::ImageRgba8(image.to_rgba8()).write_to(&mut Cursor::new(&mut bytes), ImageFormat::Gif),
        "webp" => eight_bits(image).write_to(&mut Cursor::new(&mut bytes), ImageFormat::WebP),
        _ => return Err(SaveError::Unsupported),
    };
    result.map(|_| bytes).map_err(|_| SaveError::Write)
}

/// RGB ou RGBA en 8 bits : ce que tous les encodeurs acceptent.
fn eight_bits(image: &DynamicImage) -> DynamicImage {
    if image.color().has_alpha() {
        DynamicImage::ImageRgba8(image.to_rgba8())
    } else {
        DynamicImage::ImageRgb8(image.to_rgb8())
    }
}
