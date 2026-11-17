//! Ce que GTK 4 ne fait pas sous X11 : lire l'état global de la souris et du clavier, et poser
//! une fenêtre à un endroit précis, au-dessus de tout, sans passer par le gestionnaire de fenêtres.

use bergamote_core::detector::{COMMAND, CONTROL, OPTION, SHIFT};
use x11rb::connection::Connection;
use x11rb::protocol::randr::ConnectionExt as _;
use x11rb::protocol::shape::{self, ConnectionExt as _};
use x11rb::protocol::xproto::{ChangeWindowAttributesAux, ClipOrdering, ConfigureWindowAux, ConnectionExt as _, Rectangle, StackMode, Window};
use x11rb::rust_connection::RustConnection;

/// Bits du masque de `QueryPointer`.
const MASK_SHIFT: u16 = 1 << 0;
const MASK_CONTROL: u16 = 1 << 2;
const MASK_ALT: u16 = 1 << 3;
const MASK_SUPER: u16 = 1 << 6;
const MASK_BUTTON1: u16 = 1 << 8;

pub struct X11 {
    connection: RustConnection,
    root: Window,
    screen: (i32, i32),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Pointer {
    pub x: i32,
    pub y: i32,
    /// Bouton principal (le serveur X tient compte des souris de gaucher).
    pub button_down: bool,
    /// Touches de modification, en bits du cœur.
    pub modifiers: u32,
}

#[derive(Clone, Copy, Debug)]
pub struct Area {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

impl X11 {
    pub fn connect() -> Option<Self> {
        let (connection, screen_number) = x11rb::connect(None).ok()?;
        let screen = connection.setup().roots.get(screen_number)?;
        let (root, size) = (screen.root, (i32::from(screen.width_in_pixels), i32::from(screen.height_in_pixels)));
        Some(Self { connection, root, screen: size })
    }

    /// État global, lisible aussi pendant un glisser mené par une autre application.
    pub fn pointer(&self) -> Option<Pointer> {
        let reply = self.connection.query_pointer(self.root).ok()?.reply().ok()?;
        let mask = u16::from(reply.mask);
        let mut modifiers = 0;
        for (bit, modifier) in [(MASK_SHIFT, SHIFT), (MASK_CONTROL, CONTROL), (MASK_ALT, OPTION), (MASK_SUPER, COMMAND)] {
            if mask & bit != 0 {
                modifiers |= modifier;
            }
        }
        Some(Pointer { x: i32::from(reply.root_x), y: i32::from(reply.root_y), button_down: mask & MASK_BUTTON1 != 0, modifiers })
    }

    /// Écran (moniteur) qui contient le point, sinon l'écran X entier.
    pub fn monitor_at(&self, x: i32, y: i32) -> Area {
        let monitors = self.connection.randr_get_monitors(self.root, true).ok().and_then(|cookie| cookie.reply().ok()).map(|reply| reply.monitors);
        monitors
            .unwrap_or_default()
            .iter()
            .map(|m| Area { x: i32::from(m.x), y: i32::from(m.y), width: i32::from(m.width), height: i32::from(m.height) })
            .find(|area| x >= area.x && x < area.x + area.width && y >= area.y && y < area.y + area.height)
            .unwrap_or(Area { x: 0, y: 0, width: self.screen.0, height: self.screen.1 })
    }

    /// Fait de la fenêtre un calque libre : ni cadre, ni focus, ni placement par le gestionnaire
    /// de fenêtres. À appeler avant qu'elle soit affichée.
    pub fn make_overlay(&self, window: Window) {
        let _ = self.connection.change_window_attributes(window, &ChangeWindowAttributesAux::new().override_redirect(1));
        let _ = self.connection.flush();
    }

    /// Place la fenêtre (coin haut gauche, en pixels) et la passe au-dessus des autres.
    pub fn place(&self, window: Window, x: i32, y: i32) {
        let _ = self.connection.configure_window(window, &ConfigureWindowAux::new().x(x).y(y).stack_mode(StackMode::ABOVE));
        let _ = self.connection.flush();
    }

    /// Découpe la fenêtre en disque : sans compositeur, pas de transparence, et le carré de la
    /// fenêtre se verrait.
    pub fn shape_disc(&self, window: Window, diameter: i32) {
        let radius = f64::from(diameter) / 2.0;
        let rows: Vec<Rectangle> = (0..diameter)
            .map(|row| {
                let dy = f64::from(row) + 0.5 - radius;
                let half = (radius * radius - dy * dy).max(0.0).sqrt();
                Rectangle { x: (radius - half).round() as i16, y: row as i16, width: (2.0 * half).round() as u16, height: 1 }
            })
            .collect();
        let _ = self.connection.shape_rectangles(shape::SO::SET, shape::SK::BOUNDING, ClipOrdering::Y_SORTED, window, 0, 0, &rows);
        let _ = self.connection.flush();
    }
}
