//! Cœur partagé de Bergamote.
//!
//! Tout ce qui ne dépend pas du système vit ici, écrit une seule fois pour macOS, Windows et
//! Linux : la machine à états du geste, la géométrie du camembert, le catalogue des parts, le
//! nommage des fichiers produits, les textes (français et anglais) et le son du clic. Les
//! conversions elles-mêmes restent du ressort de chaque application.
//!
//! Les applications Mac et Windows l'appellent par l'interface C de [`ffi`]
//! (`include/bergamote_core.h`) ; l'application Linux, écrite en Rust, l'utilise comme crate.

pub mod catalog;
pub mod detector;
pub mod ffi;
pub mod geometry;
pub mod i18n;
pub mod naming;
pub mod sound;
pub mod summary;
