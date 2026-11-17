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
        vec![pie_icon(32)]
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

/// Le camembert de l'icône, en ARGB : un disque citron et sa part bleue, comme le logo.
fn pie_icon(size: i32) -> ksni::Icon {
    let mut data = Vec::with_capacity((size * size * 4) as usize);
    let centre = f64::from(size) / 2.0;
    let radius = centre - 1.5;
    for y in 0..size {
        for x in 0..size {
            // Suréchantillonnage 4 × 4 pour un bord lisse.
            let (mut alpha, mut red, mut green, mut blue) = (0.0_f64, 0.0_f64, 0.0_f64, 0.0_f64);
            for sample in 0..16 {
                let dx = f64::from(x) + (f64::from(sample % 4) + 0.5) / 4.0 - centre;
                let dy = f64::from(y) + (f64::from(sample / 4) + 0.5) / 4.0 - centre;
                if dx * dx + dy * dy <= radius * radius {
                    // Angle depuis le haut, sens horaire : la part bleue occupe le premier sixième.
                    let angle = dx.atan2(-dy).rem_euclid(std::f64::consts::TAU);
                    let (r, g, b) = if angle < std::f64::consts::TAU / 6.0 { (47.0, 111.0, 214.0) } else { (195.0, 207.0, 58.0) };
                    alpha += 1.0;
                    red += r;
                    green += g;
                    blue += b;
                }
            }
            let coverage = alpha.max(1.0);
            data.extend([(alpha / 16.0 * 255.0) as u8, (red / coverage) as u8, (green / coverage) as u8, (blue / coverage) as u8]);
        }
    }
    ksni::Icon { width: size, height: size, data }
}
