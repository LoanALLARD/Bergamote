//! L'icône de la zone de notification (StatusNotifierItem) : interrupteur, rappel du geste,
//! dernier résultat, réglages. Sur un bureau sans zone de notification, l'app reste pilotable en
//! la relançant : ses réglages s'ouvrent.

use std::sync::mpsc::Sender;

use ksni::blocking::TrayMethods;
use ksni::menu::{CheckmarkItem, MenuItem, StandardItem};

/// Ce que l'utilisateur a demandé depuis l'icône, traité sur le fil de l'interface.
#[derive(Clone, Copy, Debug)]
pub enum TrayEvent {
    ToggleEnabled,
    OpenSettings,
    Quit,
}

/// Contenu du menu, préparé sur le fil de l'interface dans la langue courante.
#[derive(Clone, Debug, Default)]
pub struct TrayContent {
    pub enabled: bool,
    pub enable: String,
    pub hint: String,
    pub convert_hint: String,
    pub tools_hint: String,
    pub last_result: Option<String>,
    pub settings: String,
    pub quit: String,
}

struct Icon {
    content: TrayContent,
    events: Sender<TrayEvent>,
}

impl Icon {
    fn send(&self, event: TrayEvent) {
        let _ = self.events.send(event);
    }
}

impl ksni::Tray for Icon {
    fn id(&self) -> String {
        "bergamote".into()
    }

    fn title(&self) -> String {
        "Bergamote".into()
    }

    fn icon_name(&self) -> String {
        "bergamote".into()
    }

    /// Repli si l'icône du thème n'est pas installée (exécution depuis les sources).
    fn icon_pixmap(&self) -> Vec<ksni::Icon> {
        vec![logo_icon(32)]
    }

    fn activate(&mut self, _x: i32, _y: i32) {
        self.send(TrayEvent::OpenSettings);
    }

    fn menu(&self) -> Vec<MenuItem<Self>> {
        let note = |label: &str| -> MenuItem<Self> { StandardItem { label: label.to_owned(), enabled: false, ..Default::default() }.into() };
        let send = |label: &str, event: TrayEvent| -> MenuItem<Self> {
            StandardItem { label: label.to_owned(), activate: Box::new(move |icon: &mut Self| icon.send(event)), ..Default::default() }.into()
        };
        let mut items = vec![
            CheckmarkItem {
                label: self.content.enable.clone(),
                checked: self.content.enabled,
                activate: Box::new(|icon: &mut Self| icon.send(TrayEvent::ToggleEnabled)),
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            note(&self.content.hint),
            note(&self.content.convert_hint),
            note(&self.content.tools_hint),
        ];
        if let Some(result) = &self.content.last_result {
            items.push(note(result));
        }
        items.extend([MenuItem::Separator, send(&self.content.settings, TrayEvent::OpenSettings), send(&self.content.quit, TrayEvent::Quit)]);
        items
    }
}

pub struct Tray {
    handle: ksni::blocking::Handle<Icon>,
}

impl Tray {
    /// `None` quand le bureau n'a pas de zone de notification StatusNotifierItem.
    pub fn spawn(content: TrayContent, events: Sender<TrayEvent>) -> Option<Self> {
        Icon { content, events }.spawn().ok().map(|handle| Self { handle })
    }

    pub fn update(&self, content: TrayContent) {
        self.handle.update(move |icon| icon.content = content);
    }
}

/// Le logo en ARGB, « le B en deux parts » sur son carré clair arrondi (le même dessin que
/// data/bergamote.svg), pour les bureaux qui ne trouvent pas l'icône du thème.
fn logo_icon(size: i32) -> ksni::Icon {
    const GROUND: [f64; 3] = [248.0, 248.0, 243.0];
    const STEM: [f64; 3] = [29.0, 42.0, 18.0];
    const BLUE: [f64; 3] = [47.0, 111.0, 214.0];
    const CITRON: [f64; 3] = [195.0, 207.0, 58.0];

    /// Couleur du logo en un point du carré de 100 unités, ou `None` hors du carré arrondi.
    fn color_at(x: f64, y: f64) -> Option<[f64; 3]> {
        // Carré arrondi : rayon 22.
        let (dx, dy) = ((x - 50.0).abs() - 28.0, (y - 50.0).abs() - 28.0);
        if dx > 22.0 || dy > 22.0 || (dx > 0.0 && dy > 0.0 && dx * dx + dy * dy > 22.0 * 22.0) {
            return None;
        }
        // Le B, dessiné à 72 % au centre du carré (voir brand/logo.svg).
        let (u, v) = ((x - 13.64) / 0.72, (y - 17.6) / 0.72);
        let in_bowl = |top: f64, bottom: f64, flat: f64| {
            let radius = (bottom - top) / 2.0;
            let centre = top + radius;
            v >= top && v <= bottom && u >= 46.0 && (u <= flat || (u - flat).powi(2) + (v - centre).powi(2) <= radius * radius)
        };
        Some(if (26.0..=41.0).contains(&u) && (20.0..=86.0).contains(&v) {
            STEM
        } else if in_bowl(48.0, 86.0, 56.0) {
            CITRON
        } else if in_bowl(20.0, 52.0, 53.0) {
            BLUE
        } else {
            GROUND
        })
    }

    let mut data = Vec::with_capacity((size * size * 4) as usize);
    let unit = 100.0 / f64::from(size);
    for y in 0..size {
        for x in 0..size {
            // Suréchantillonnage 4 × 4 pour des bords lisses.
            let (mut covered, mut sum) = (0.0_f64, [0.0_f64; 3]);
            for sample in 0..16 {
                let px = (f64::from(x) + (f64::from(sample % 4) + 0.5) / 4.0) * unit;
                let py = (f64::from(y) + (f64::from(sample / 4) + 0.5) / 4.0) * unit;
                if let Some(color) = color_at(px, py) {
                    covered += 1.0;
                    for (total, channel) in sum.iter_mut().zip(color) {
                        *total += channel;
                    }
                }
            }
            let coverage = covered.max(1.0);
            data.extend([(covered / 16.0 * 255.0) as u8, (sum[0] / coverage) as u8, (sum[1] / coverage) as u8, (sum[2] / coverage) as u8]);
        }
    }
    ksni::Icon { width: size, height: size, data }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn logo_icon_draws_the_b_on_its_rounded_ground() {
        let icon = logo_icon(100);
        let pixel = |x: usize, y: usize| -> [u8; 4] { icon.data[(y * 100 + x) * 4..(y * 100 + x) * 4 + 4].try_into().unwrap() };
        assert_eq!(pixel(0, 0)[0], 0, "coin transparent");
        assert_eq!(pixel(38, 50), [255, 29, 42, 18], "le fût");
        assert_eq!(pixel(57, 35), [255, 47, 111, 214], "la panse haute, bleue");
        assert_eq!(pixel(62, 65), [255, 195, 207, 58], "la panse basse, citron");
        assert_eq!(pixel(85, 50), [255, 248, 248, 243], "le fond clair");
    }
}
