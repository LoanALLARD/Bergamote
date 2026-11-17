//! Le camembert : des parts en anneau autour d'un centre qui résume les fichiers. C'est aussi la
//! cible du dépôt : la part visée suit le curseur, et lâcher les fichiers lance l'action.
//!
//! Les fichiers d'un glisser ne sont lisibles qu'une fois le curseur sur notre fenêtre : elle
//! s'ouvre donc d'abord invisible sous le curseur (`Pending`), puis se dessine dès que le glisser
//! y entre avec des fichiers. Un glisser sans fichiers (texte, fenêtre déplacée) ne fait ainsi
//! jamais apparaître de camembert.

use std::cell::RefCell;
use std::f64::consts::{FRAC_PI_2, PI};
use std::path::PathBuf;
use std::rc::Rc;

use bergamote_core::catalog::Action;
use bergamote_core::detector::WheelKind;
use bergamote_core::i18n::{self, Language};
use bergamote_core::{geometry, summary};
use gtk::prelude::*;
use gtk::{cairo, gdk, glib};

use super::icons;
use super::x11::X11;

pub const DIAMETER: i32 = 340;
const OUTER_RADIUS: f64 = 160.0;
const INNER_RADIUS: f64 = 62.0;
const LABEL_WIDTH: i32 = 78;
const CENTRE_WIDTH: i32 = 98;
/// Décalage vertical de l'icône et du titre autour du milieu de l'étiquette.
const ICON_OFFSET: f64 = 9.0;
const TITLE_OFFSET: f64 = 10.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Hidden,
    /// Ouvert mais invisible : on attend que le glisser entre pour connaître les fichiers.
    Pending,
    Ready,
    Working,
    Done,
    Failed,
}

pub enum Event {
    /// Le glisser est entré : voici ses fichiers.
    FilesEntered(Vec<PathBuf>),
    /// Le curseur vient de passer sur une part.
    SliceEntered,
    Dropped(Action, Vec<PathBuf>),
}

type Handler = Rc<dyn Fn(Event)>;

struct Data {
    state: State,
    kind: WheelKind,
    language: Language,
    files: Option<Vec<PathBuf>>,
    actions: Vec<Action>,
    highlighted: Option<usize>,
    message: String,
    summary: String,
    xid: Option<u32>,
}

pub struct Wheel {
    window: gtk::Window,
    area: gtk::DrawingArea,
    labels: gtk::Fixed,
    x11: Rc<X11>,
    /// Sans compositeur, pas de transparence : la fenêtre est découpée en disque.
    composited: bool,
    data: RefCell<Data>,
    handler: RefCell<Option<Handler>>,
}

impl Wheel {
    pub fn new(x11: Rc<X11>) -> Rc<Self> {
        let window = gtk::Window::builder().title("Bergamote").decorated(false).resizable(false).focusable(false).can_focus(false).build();
        window.add_css_class("bergamote-wheel");
        window.set_default_size(DIAMETER, DIAMETER);

        let area = gtk::DrawingArea::new();
        area.set_content_width(DIAMETER);
        area.set_content_height(DIAMETER);
        let labels = gtk::Fixed::new();
        labels.set_can_target(false);
        let overlay = gtk::Overlay::new();
        overlay.set_child(Some(&area));
        overlay.add_overlay(&labels);
        window.set_child(Some(&overlay));

        #[allow(deprecated)]
        let composited = gdk::Display::default().is_some_and(|display| display.is_composited());
        let wheel = Rc::new(Self {
            window,
            area,
            labels,
            x11,
            composited,
            data: RefCell::new(Data {
                state: State::Hidden,
                kind: WheelKind::Conversion,
                language: i18n::current(),
                files: None,
                actions: Vec::new(),
                highlighted: None,
                message: String::new(),
                summary: String::new(),
                xid: None,
            }),
            handler: RefCell::new(None),
        });

        let weak = Rc::downgrade(&wheel);
        wheel.area.set_draw_func(move |_, context, _, _| {
            if let Some(wheel) = weak.upgrade() {
                wheel.draw(context);
            }
        });
        wheel.install_drop_target(&overlay);
        wheel
    }

    pub fn connect(&self, handler: impl Fn(Event) + 'static) {
        *self.handler.borrow_mut() = Some(Rc::new(handler));
    }

    pub fn state(&self) -> State {
        self.data.borrow().state
    }

    pub fn kind(&self) -> WheelKind {
        self.data.borrow().kind
    }

    /// Fichiers du glisser en cours, connus une fois qu'il est entré dans la fenêtre.
    pub fn files(&self) -> Option<Vec<PathBuf>> {
        self.data.borrow().files.clone()
    }

    /// Vrai si le camembert peut s'ouvrir invisible en attendant les fichiers.
    pub fn can_wait_unseen(&self) -> bool {
        self.composited
    }

    pub fn set_language(&self, language: Language) {
        self.data.borrow_mut().language = language;
    }

    pub fn show_pending(&self, kind: WheelKind, x: i32, y: i32) {
        {
            let mut data = self.data.borrow_mut();
            data.kind = kind;
            data.actions.clear();
            data.highlighted = None;
            data.state = State::Pending;
        }
        self.render();
        self.show_at(x, y);
    }

    pub fn show_actions(&self, kind: WheelKind, actions: Vec<Action>, position: Option<(i32, i32)>) {
        {
            let mut data = self.data.borrow_mut();
            data.kind = kind;
            data.actions = actions;
            data.highlighted = None;
            data.state = State::Ready;
        }
        self.render();
        if let Some((x, y)) = position {
            self.show_at(x, y);
        }
    }

    pub fn show_status(&self, state: State, message: &str) {
        {
            let mut data = self.data.borrow_mut();
            data.state = state;
            data.message = message.to_owned();
            data.highlighted = None;
        }
        self.render();
    }

    pub fn hide(&self) {
        self.window.set_visible(false);
        let mut data = self.data.borrow_mut();
        data.state = State::Hidden;
        data.files = None;
        data.actions.clear();
        data.highlighted = None;
    }

    // MARK: Position

    /// Centre la fenêtre sur le curseur (pixels de l'écran), sans déborder du moniteur.
    fn show_at(&self, x: i32, y: i32) {
        let Some(xid) = self.overlay_window() else { return };
        let size = DIAMETER * self.window.scale_factor().max(1);
        let monitor = self.x11.monitor_at(x, y);
        let left = (x - size / 2).clamp(monitor.x, (monitor.x + monitor.width - size).max(monitor.x));
        let top = (y - size / 2).clamp(monitor.y, (monitor.y + monitor.height - size).max(monitor.y));
        self.x11.place(xid, left, top);
        self.window.set_visible(true);
        // Une fois affichée : GTK peut l'avoir reposée à l'origine.
        self.x11.place(xid, left, top);
        let x11 = self.x11.clone();
        glib::idle_add_local_once(move || x11.place(xid, left, top));
    }

    /// Identifiant X de la fenêtre, rendue libre de tout gestionnaire de fenêtres au premier appel.
    fn overlay_window(&self) -> Option<u32> {
        if let Some(xid) = self.data.borrow().xid {
            return Some(xid);
        }
        WidgetExt::realize(&self.window);
        let surface = self.window.surface()?.downcast::<gdk_x11::X11Surface>().ok()?;
        let xid = surface.xid() as u32;
        self.x11.make_overlay(xid);
        if !self.composited {
            self.x11.shape_disc(xid, DIAMETER * self.window.scale_factor().max(1));
        }
        self.data.borrow_mut().xid = Some(xid);
        Some(xid)
    }

    // MARK: Dépôt

    fn install_drop_target(self: &Rc<Self>, widget: &gtk::Overlay) {
        let target = gtk::DropTarget::new(gdk::FileList::static_type(), gdk::DragAction::COPY);
        // Charger les données dès l'entrée du glisser : c'est ce qui révèle le camembert.
        target.set_preload(true);

        let weak = Rc::downgrade(self);
        target.connect_enter(move |target, x, y| weak.upgrade().map_or(gdk::DragAction::empty(), |wheel| wheel.drag_moved(target, x, y)));
        let weak = Rc::downgrade(self);
        target.connect_motion(move |target, x, y| weak.upgrade().map_or(gdk::DragAction::empty(), |wheel| wheel.drag_moved(target, x, y)));
        let weak = Rc::downgrade(self);
        target.connect_value_notify(move |target| {
            if let Some(wheel) = weak.upgrade() {
                wheel.read_files(target);
            }
        });
        let weak = Rc::downgrade(self);
        target.connect_leave(move |_| {
            if let Some(wheel) = weak.upgrade() {
                wheel.highlight(None);
            }
        });
        let weak = Rc::downgrade(self);
        target.connect_drop(move |_, value, x, y| weak.upgrade().is_some_and(|wheel| wheel.dropped(value, x, y)));
        widget.add_controller(target);
    }

    /// Toujours une copie : l'original reste en place, quelle que soit la touche enfoncée.
    fn drag_moved(&self, target: &gtk::DropTarget, x: f64, y: f64) -> gdk::DragAction {
        self.read_files(target);
        let state = self.state();
        let slice = if state == State::Ready { self.slice_at(x, y) } else { None };
        self.highlight(slice);
        match state {
            // Pas encore de parts : on accepte, le temps que les fichiers soient lus.
            State::Pending => gdk::DragAction::COPY,
            State::Ready if slice.is_some() => gdk::DragAction::COPY,
            _ => gdk::DragAction::empty(),
        }
    }

    fn read_files(&self, target: &gtk::DropTarget) {
        if !matches!(self.state(), State::Pending | State::Ready) {
            return;
        }
        let Some(files) = target.value().and_then(|value| files_of(&value)) else { return };
        {
            let mut data = self.data.borrow_mut();
            if data.files.as_ref() == Some(&files) {
                return;
            }
            let extensions: Vec<String> = files.iter().map(|f| f.extension().map(|e| e.to_string_lossy().into_owned()).unwrap_or_default()).collect();
            let total: Option<u64> = files.iter().map(|f| std::fs::metadata(f).ok().map(|m| m.len())).sum();
            data.summary = summary::files(&extensions, total, data.language);
            data.files = Some(files.clone());
        }
        self.emit(Event::FilesEntered(files));
    }

    fn dropped(&self, value: &glib::Value, x: f64, y: f64) -> bool {
        if self.state() != State::Ready {
            return false;
        }
        let (Some(index), Some(files)) = (self.slice_at(x, y), files_of(value).or_else(|| self.files())) else { return false };
        let Some(action) = self.data.borrow().actions.get(index).cloned() else { return false };
        if files.is_empty() {
            return false;
        }
        self.emit(Event::Dropped(action, files));
        true
    }

    fn slice_at(&self, x: f64, y: f64) -> Option<usize> {
        let centre = f64::from(DIAMETER) / 2.0;
        geometry::slice_at(x - centre, centre - y, self.data.borrow().actions.len(), INNER_RADIUS, OUTER_RADIUS)
    }

    fn highlight(&self, slice: Option<usize>) {
        if self.data.borrow().highlighted == slice {
            return;
        }
        self.data.borrow_mut().highlighted = slice;
        self.render();
        if slice.is_some() {
            self.emit(Event::SliceEntered);
        }
    }

    fn emit(&self, event: Event) {
        let handler = self.handler.borrow().clone();
        if let Some(handler) = handler {
            handler(event);
        }
    }

    // MARK: Dessin

    /// Redessine les formes et repose les étiquettes.
    fn render(&self) {
        while let Some(child) = self.labels.first_child() {
            self.labels.remove(&child);
        }
        let data = self.data.borrow();
        let centre = f64::from(DIAMETER) / 2.0;
        if data.state != State::Pending && data.state != State::Hidden {
            let count = data.actions.len();
            for (index, action) in data.actions.iter().enumerate() {
                let (x, y) = slice_anchor(index, count);
                // L'icône est dessinée avec les parts ; le titre vient juste en dessous.
                self.place(&slice_title(action, data.highlighted == Some(index)), LABEL_WIDTH, x, y + TITLE_OFFSET);
            }
            self.place(&centre_label(&data), CENTRE_WIDTH, centre, centre);
        }
        drop(data);
        self.area.queue_draw();
    }

    /// Pose un élément de largeur fixe, centré sur (x, y).
    fn place(&self, widget: &gtk::Box, width: i32, x: f64, y: f64) {
        widget.set_size_request(width, -1);
        let (_, height, _, _) = widget.measure(gtk::Orientation::Vertical, width);
        self.labels.put(widget, x - f64::from(width) / 2.0, y - f64::from(height) / 2.0);
    }

    fn draw(&self, context: &cairo::Context) {
        let data = self.data.borrow();
        let centre = f64::from(DIAMETER) / 2.0;
        if matches!(data.state, State::Pending | State::Hidden) {
            return;
        }
        // Disque de fond, sombre et translucide, avec un liseré.
        context.arc(centre, centre, OUTER_RADIUS, 0.0, 2.0 * PI);
        context.set_source_rgba(0.125, 0.125, 0.125, 0.92);
        let _ = context.fill_preserve();
        context.set_source_rgba(1.0, 1.0, 1.0, 0.35);
        context.set_line_width(1.0);
        let _ = context.stroke();

        let count = data.actions.len();
        for index in 0..count {
            slice_path(context, index, count, INNER_RADIUS + 6.0, OUTER_RADIUS - 6.0);
            if data.highlighted == Some(index) {
                context.set_source_rgba(0.184, 0.435, 0.839, 0.95);
            } else {
                context.set_source_rgba(1.0, 1.0, 1.0, 0.08);
            }
            let _ = context.fill();
        }
        for (index, action) in data.actions.iter().enumerate() {
            let (x, y) = slice_anchor(index, count);
            let alpha = if data.highlighted == Some(index) { 1.0 } else { 0.86 };
            context.set_source_rgba(1.0, 1.0, 1.0, alpha);
            icons::draw(context, &action.icon, x, y - ICON_OFFSET);
        }

        context.arc(centre, centre, INNER_RADIUS - 4.0, 0.0, 2.0 * PI);
        context.set_source_rgba(0.165, 0.165, 0.165, 1.0);
        let _ = context.fill();
    }
}

/// Secteur d'anneau, part 0 centrée en haut puis sens horaire. Cairo mesure ses angles depuis
/// l'axe des x : un quart de tour de décalage.
fn slice_path(context: &cairo::Context, index: usize, count: usize, inner: f64, outer: f64) {
    let centre = f64::from(DIAMETER) / 2.0;
    context.new_path();
    if count <= 1 {
        context.arc(centre, centre, outer, 0.0, 2.0 * PI);
        context.close_path();
        context.new_sub_path();
        context.arc_negative(centre, centre, inner, 2.0 * PI, 0.0);
        context.close_path();
        return;
    }
    let width = 2.0 * PI / count as f64;
    let gap = 0.025;
    let start = geometry::center_angle(index, count) - width / 2.0 + gap - FRAC_PI_2;
    let end = start + width - 2.0 * gap;
    context.arc(centre, centre, outer, start, end);
    context.arc_negative(centre, centre, inner, end, start);
    context.close_path();
}

/// Milieu de l'étiquette d'une part (icône au-dessus, titre en dessous).
fn slice_anchor(index: usize, count: usize) -> (f64, f64) {
    let centre = f64::from(DIAMETER) / 2.0;
    let angle = geometry::center_angle(index, count);
    let radius = (INNER_RADIUS + OUTER_RADIUS) / 2.0 + 4.0;
    (centre + angle.sin() * radius, centre - angle.cos() * radius)
}

fn slice_title(action: &Action, lit: bool) -> gtk::Box {
    let column = gtk::Box::new(gtk::Orientation::Vertical, 0);
    column.add_css_class("slice");
    if lit {
        column.add_css_class("lit");
    }
    let title = gtk::Label::new(Some(&action.title.to_uppercase()));
    title.add_css_class("slice-title");
    title.set_ellipsize(gtk::pango::EllipsizeMode::End);
    column.append(&title);
    column
}

fn centre_label(data: &Data) -> gtk::Box {
    let column = gtk::Box::new(gtk::Orientation::Vertical, 3);
    column.set_valign(gtk::Align::Center);
    let line = |text: &str, class: &str| {
        let label = gtk::Label::new(Some(text));
        label.add_css_class(class);
        label.set_wrap(true);
        label.set_wrap_mode(gtk::pango::WrapMode::WordChar);
        label.set_justify(gtk::Justification::Center);
        label.set_max_width_chars(16);
        label
    };
    let glyph = |name: &str, class: &str| {
        let icon = gtk::Image::from_icon_name(name);
        icon.set_pixel_size(22);
        icon.add_css_class(class);
        icon
    };
    match data.state {
        State::Working => {
            let spinner = gtk::Spinner::new();
            spinner.set_spinning(true);
            column.append(&spinner);
            column.append(&line(&data.message, "centre-text"));
        }
        State::Done => {
            column.append(&glyph("object-select-symbolic", "done"));
            column.append(&line(&data.message, "centre-message"));
        }
        State::Failed => {
            column.append(&glyph("dialog-warning-symbolic", "failed"));
            column.append(&line(&data.message, "centre-message"));
        }
        _ => {
            let key = if data.kind == WheelKind::Conversion { "wheel.convert" } else { "wheel.tools" };
            column.append(&line(&i18n::tr(data.language, key).to_uppercase(), "centre-kind"));
            column.append(&line(&data.summary, "centre-text"));
        }
    }
    column
}

fn files_of(value: &glib::Value) -> Option<Vec<PathBuf>> {
    let list = value.get::<gdk::FileList>().ok()?;
    Some(list.files().iter().filter_map(|file| file.path()).collect())
}

/// Feuille de style du camembert : fond transparent, textes clairs sur le disque sombre.
pub const CSS: &str = "
window.bergamote-wheel { background: transparent; box-shadow: none; }
.bergamote-wheel *:drop(active) { box-shadow: none; outline: none; }
.bergamote-wheel .slice { color: rgba(255, 255, 255, 0.86); }
.bergamote-wheel .slice.lit { color: white; }
.bergamote-wheel .slice-title { font-size: 10px; font-weight: 700; letter-spacing: 0.6px; }
.bergamote-wheel .centre-kind { color: rgba(255, 255, 255, 0.55); font-size: 9px; font-weight: 800; }
.bergamote-wheel .centre-text { color: rgba(255, 255, 255, 0.92); font-size: 11px; font-weight: 700; }
.bergamote-wheel .centre-message { color: rgba(255, 255, 255, 0.92); font-size: 9px; }
.bergamote-wheel spinner { color: white; }
.bergamote-wheel .done { color: #34c759; }
.bergamote-wheel .failed { color: #ff9f0a; }
";
