//! Interface C du cœur, décrite dans `include/bergamote_core.h`.
//!
//! Conventions : les chaînes sont en UTF-8 ; une chaîne renvoyée par le cœur se libère avec
//! `bgm_string_free`, un tampon d'octets avec `bgm_bytes_free`. Les structures riches (catalogue)
//! passent en JSON pour garder une interface petite et stable.
//!
//! # Safety
//!
//! Contrat commun à toutes les fonctions `unsafe` de ce module : chaque pointeur reçu est soit
//! NULL (traité comme une absence de valeur), soit valide pour la durée de l'appel ; les chaînes
//! sont terminées par un zéro ; un détecteur ou un tampon n'est libéré qu'une fois, par la
//! fonction `*_free` correspondante, et n'est plus utilisé ensuite.
#![allow(clippy::missing_safety_doc)]

use std::ffi::{c_char, CStr, CString};
use std::path::Path;
use std::ptr;

use serde::Deserialize;

use crate::catalog::{self, Input, Platform};
use crate::detector::{Decision, Detector, Sample, WheelKind};
use crate::{geometry, naming, sound, summary};

fn to_c(text: String) -> *mut c_char {
    CString::new(text).map_or(ptr::null_mut(), CString::into_raw)
}

unsafe fn from_c<'a>(text: *const c_char) -> Option<&'a str> {
    if text.is_null() {
        None
    } else {
        CStr::from_ptr(text).to_str().ok()
    }
}

fn kind_from(value: u8) -> Option<WheelKind> {
    match value {
        1 => Some(WheelKind::Conversion),
        2 => Some(WheelKind::Tools),
        _ => None,
    }
}

fn kind_code(kind: Option<WheelKind>) -> u8 {
    match kind {
        None => 0,
        Some(WheelKind::Conversion) => 1,
        Some(WheelKind::Tools) => 2,
    }
}

#[no_mangle]
pub extern "C" fn bgm_core_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr().cast()
}

#[no_mangle]
pub unsafe extern "C" fn bgm_string_free(text: *mut c_char) {
    if !text.is_null() {
        drop(CString::from_raw(text));
    }
}

// MARK: Geste

#[no_mangle]
pub extern "C" fn bgm_detector_new() -> *mut Detector {
    Box::into_raw(Box::new(Detector::default()))
}

#[no_mangle]
pub unsafe extern "C" fn bgm_detector_free(detector: *mut Detector) {
    if !detector.is_null() {
        drop(Box::from_raw(detector));
    }
}

#[no_mangle]
pub unsafe extern "C" fn bgm_detector_clear_bindings(detector: *mut Detector) {
    if let Some(detector) = detector.as_mut() {
        detector.clear_bindings();
    }
}

/// `kind` : 1 conversion, 2 outils. Renvoie faux si `kind` est inconnu.
#[no_mangle]
pub unsafe extern "C" fn bgm_detector_set_binding(detector: *mut Detector, modifiers: u32, kind: u8) -> bool {
    match (detector.as_mut(), kind_from(kind)) {
        (Some(detector), Some(kind)) => {
            detector.set_binding(modifiers, kind);
            true
        }
        _ => false,
    }
}

/// Renvoie 0 rien, 1 ouvrir la conversion, 2 ouvrir les outils, 3 fermer.
#[no_mangle]
pub unsafe extern "C" fn bgm_detector_update(detector: *mut Detector, is_mouse_down: bool, drag_generation: i64, modifiers: u32) -> i32 {
    let Some(detector) = detector.as_mut() else { return 0 };
    match detector.update(Sample { is_mouse_down, drag_generation, modifiers }) {
        Decision::None => 0,
        Decision::Show(kind) => i32::from(kind_code(Some(kind))),
        Decision::Hide => 3,
    }
}

/// 0 aucun, 1 conversion, 2 outils.
#[no_mangle]
pub unsafe extern "C" fn bgm_detector_visible(detector: *const Detector) -> u8 {
    detector.as_ref().map_or(0, |d| kind_code(d.visible()))
}

#[no_mangle]
pub unsafe extern "C" fn bgm_detector_dismiss(detector: *mut Detector) {
    if let Some(detector) = detector.as_mut() {
        detector.dismiss();
    }
}

// MARK: Géométrie

/// Part sous le point (repère centré, y vers le haut), ou -1.
#[no_mangle]
pub extern "C" fn bgm_slice_at(x: f64, y: f64, count: i32, inner_radius: f64, outer_radius: f64) -> i32 {
    let count = usize::try_from(count).unwrap_or(0);
    geometry::slice_at(x, y, count, inner_radius, outer_radius).map_or(-1, |index| index as i32)
}

#[no_mangle]
pub extern "C" fn bgm_center_angle(index: i32, count: i32) -> f64 {
    geometry::center_angle(usize::try_from(index).unwrap_or(0), usize::try_from(count).unwrap_or(0))
}

// MARK: Catalogue

#[derive(Deserialize)]
struct CatalogRequest {
    kind: u8,
    #[serde(default)]
    inputs: Vec<Input>,
    /// Vrai quand les types sont encore inconnus : actions courantes.
    #[serde(default)]
    common: bool,
    #[serde(flatten)]
    platform: Platform,
}

/// Requête JSON : `{"kind":1,"inputs":[{"category":"image","format":"png"}],"writable":["png"],
/// "capabilities":null,"common":false}`. Réponse : tableau JSON d'actions, ou NULL si la requête
/// est invalide.
#[no_mangle]
pub unsafe extern "C" fn bgm_catalog(request_json: *const c_char) -> *mut c_char {
    let Some(request) = from_c(request_json).and_then(|json| serde_json::from_str::<CatalogRequest>(json).ok()) else {
        return ptr::null_mut();
    };
    let Some(kind) = kind_from(request.kind) else { return ptr::null_mut() };
    let actions = if request.common {
        catalog::common_actions(kind, &request.platform)
    } else {
        catalog::actions(kind, &request.inputs, &request.platform)
    };
    serde_json::to_string(&actions).map_or(ptr::null_mut(), to_c)
}

/// Catégorie et format d'après une extension : `{"category":"image","format":"jpeg"}`.
#[no_mangle]
pub unsafe extern "C" fn bgm_input_for_extension(extension: *const c_char) -> *mut c_char {
    let input = catalog::input_for_extension(from_c(extension).unwrap_or(""));
    serde_json::to_string(&input).map_or(ptr::null_mut(), to_c)
}

// MARK: Nommage et textes

/// `output_dir` NULL : à côté de `source`.
#[no_mangle]
pub unsafe extern "C" fn bgm_unique_output_path(
    source: *const c_char,
    suffix: *const c_char,
    extension: *const c_char,
    output_dir: *const c_char,
) -> *mut c_char {
    let (Some(source), Some(extension)) = (from_c(source), from_c(extension)) else { return ptr::null_mut() };
    let path = naming::unique_output_path(
        Path::new(source),
        from_c(suffix).unwrap_or(""),
        extension,
        from_c(output_dir).map(Path::new),
    );
    to_c(path.to_string_lossy().into_owned())
}

#[no_mangle]
pub extern "C" fn bgm_created_summary(count: u32) -> *mut c_char {
    to_c(summary::created(count as usize))
}

/// `extensions_json` : tableau JSON d'extensions ; `total_bytes` négatif : taille inconnue.
#[no_mangle]
pub unsafe extern "C" fn bgm_files_summary(extensions_json: *const c_char, total_bytes: i64) -> *mut c_char {
    let extensions: Vec<String> = from_c(extensions_json).and_then(|json| serde_json::from_str(json).ok()).unwrap_or_default();
    to_c(summary::files(&extensions, u64::try_from(total_bytes).ok()))
}

// MARK: Son

/// Fichier WAV du clic ; sa longueur est écrite dans `length`.
#[no_mangle]
pub unsafe extern "C" fn bgm_click_wav(length: *mut usize) -> *mut u8 {
    let bytes = sound::click_wav().into_boxed_slice();
    if let Some(length) = length.as_mut() {
        *length = bytes.len();
    }
    Box::into_raw(bytes).cast()
}

#[no_mangle]
pub unsafe extern "C" fn bgm_bytes_free(bytes: *mut u8, length: usize) {
    if !bytes.is_null() {
        drop(Box::from_raw(ptr::slice_from_raw_parts_mut(bytes, length)));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    unsafe fn take(text: *mut c_char) -> String {
        let value = CStr::from_ptr(text).to_str().unwrap().to_owned();
        bgm_string_free(text);
        value
    }

    #[test]
    fn catalog_round_trip() {
        unsafe {
            let request = CString::new(r#"{"kind":1,"inputs":[{"category":"image","format":"png"}],"writable":["png","jpeg"]}"#).unwrap();
            let response = take(bgm_catalog(request.as_ptr()));
            assert!(response.starts_with(r#"[{"id":"convert_images:jpeg","title":"JPEG""#), "{response}");
            let invalid = CString::new("{").unwrap();
            assert!(bgm_catalog(invalid.as_ptr()).is_null());
        }
    }

    #[test]
    fn detector_through_ffi() {
        unsafe {
            let detector = bgm_detector_new();
            assert_eq!(bgm_detector_update(detector, false, 1, 0), 0);
            assert_eq!(bgm_detector_update(detector, true, 1, 0), 0);
            assert_eq!(bgm_detector_update(detector, true, 2, 1), 1);
            assert_eq!(bgm_detector_visible(detector), 1);
            assert_eq!(bgm_detector_update(detector, false, 2, 0), 3);
            bgm_detector_free(detector);
        }
    }

    #[test]
    fn click_sound_through_ffi() {
        unsafe {
            let mut length = 0usize;
            let bytes = bgm_click_wav(&mut length);
            assert_eq!(length, 44 + 1_323 * 2);
            bgm_bytes_free(bytes, length);
        }
    }
}
