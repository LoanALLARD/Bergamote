//! Bergamote pour Linux. Cette bibliothèque porte ce qui ne dépend pas de l'interface et se teste
//! sur n'importe quel système : conversions, réglages, lancement à l'ouverture de session.
//! L'interface (GTK 4, X11) est dans le binaire.

pub mod autostart;
pub mod convert;
pub mod settings;
