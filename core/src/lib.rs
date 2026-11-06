//! Cœur partagé de Bergamote.
//!
//! Tout ce qui ne dépend pas du système vit ici, écrit une seule fois pour macOS et Windows :
//! la machine à états du geste, la géométrie du camembert, le catalogue des parts, le nommage des
//! fichiers produits, les textes affichés et le son du clic. Les conversions elles-mêmes restent
//! natives (frameworks Apple sur Mac, API Windows et bibliothèques .NET sur Windows).
//!
//! Les applications l'appellent par l'interface C de [`ffi`] (`include/bergamote_core.h`).

pub mod catalog;
pub mod detector;
pub mod ffi;
pub mod geometry;
pub mod naming;
pub mod sound;
pub mod summary;
