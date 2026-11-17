//! L'app : surveille le geste, ouvre le camembert sous le curseur, lance les conversions.
//!
//! Détection : relevé à 20 Hz de l'état global (bouton principal, position du curseur, touches de
//! modification) par X11. Un glisser commence quand le curseur s'éloigne du point d'appui au-delà
//! du seuil ; la décision est prise par le cœur partagé (`Detector`).

mod icons;
mod settings_window;
mod sound;
mod tray;
mod wheel;
mod x11;

use std::cell::{Cell, RefCell};
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::time::Duration;

use bergamote_core::catalog::{self, Action};
use bergamote_core::detector::{Decision, Detector, Sample, WheelKind};
use bergamote_core::i18n::{self, Language};
use bergamote_core::summary;
use bergamote_linux::convert::{self, Converter, Tesseract};
use bergamote_linux::settings::{self, Settings};
use gtk::prelude::*;
use gtk::{gdk, gio, glib};

use sound::Sound;
use tray::{Tray, TrayContent, TrayEvent};
use wheel::{Event, State, Wheel};
use x11::{Pointer, X11};

const APP_ID: &str = "io.github.loanallard.Bergamote";
/// Déplacement, en pixels, à partir duquel un appui devient un glisser (le seuil de GTK).
const DRAG_THRESHOLD: i32 = 8;

/// Résultat d'une conversion menée sur un autre fil.
type Outcome = Result<usize, String>;

pub struct App {
    application: gtk::Application,
    settings: RefCell<Settings>,
    settings_path: PathBuf,
    /// Session Wayland : le geste ne peut pas y être suivi partout.
    wayland: bool,
    tesseract: Option<Tesseract>,
    x11: Rc<X11>,
    wheel: Rc<Wheel>,
    sound: Sound,
    detector: RefCell<Detector>,
    drag: Cell<Drag>,
    outcomes: (Sender<Outcome>, Receiver<Outcome>),
    tray: RefCell<Option<Tray>>,
    tray_events: (Sender<TrayEvent>, Receiver<TrayEvent>),
    settings_window: RefCell<Option<gtk::Window>>,
    last_result: RefCell<Option<String>>,
}

/// Suivi de l'appui en cours, pour dater le début d'un glisser.
#[derive(Clone, Copy, Default)]
struct Drag {
    generation: i64,
    was_down: bool,
    counted: bool,
    press: (i32, i32),
}

pub fn run() -> std::process::ExitCode {
    let wayland = std::env::var("XDG_SESSION_TYPE").is_ok_and(|kind| kind == "wayland") || std::env::var_os("WAYLAND_DISPLAY").is_some();
    // Le geste et le placement du camembert passent par X11 (XWayland sous Wayland).
    if std::env::var_os("GDK_BACKEND").is_none() {
        std::env::set_var("GDK_BACKEND", "x11");
    }
    let application = gtk::Application::builder().application_id(APP_ID).flags(gio::ApplicationFlags::HANDLES_COMMAND_LINE).build();
    let running: Rc<RefCell<Option<Rc<App>>>> = Rc::default();

    application.connect_startup(glib::clone!(
        #[strong]
        running,
        move |application| match App::start(application, wayland) {
            Some(app) => *running.borrow_mut() = Some(app),
            None => {
                eprintln!("Bergamote : pas de serveur X11 accessible.");
                application.quit();
            }
        }
    ));
    // Reçu au lancement, puis à chaque relance pendant que l'app tourne : on ouvre les réglages,
    // sauf à l'ouverture de session (--background).
    application.connect_command_line(move |_, command_line| {
        let background = command_line.arguments().iter().any(|argument| argument == "--background");
        if let (Some(app), false) = (running.borrow().as_ref(), background) {
            app.open_settings();
        }
        0.into()
    });
    let status = application.run();
    std::process::ExitCode::from(u8::from(status))
}

impl App {
    fn start(application: &gtk::Application, wayland: bool) -> Option<Rc<Self>> {
        let x11 = Rc::new(X11::connect()?);
        let settings_path = settings::settings_path();
        let (settings, first_launch) = Settings::load(&settings_path);
        if first_launch {
            let _ = settings.save(&settings_path);
        }
        i18n::set_current(i18n::resolve(&settings.language, &settings::system_locale()));

        let provider = gtk::CssProvider::new();
        #[allow(deprecated)]
        provider.load_from_data(wheel::CSS);
        if let Some(display) = gdk::Display::default() {
            gtk::style_context_add_provider_for_display(&display, &provider, gtk::STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        let app = Rc::new(Self {
            application: application.clone(),
            settings: RefCell::new(settings),
            settings_path,
            wayland,
            tesseract: Tesseract::find(),
            wheel: Wheel::new(x11.clone()),
            x11,
            sound: Sound::new(),
            detector: RefCell::new(Detector::empty()),
            drag: Cell::default(),
            outcomes: channel(),
            tray: RefCell::new(None),
            tray_events: channel(),
            settings_window: RefCell::new(None),
            last_result: RefCell::new(None),
        });
        app.apply_bindings();
        *app.tray.borrow_mut() = Tray::spawn(app.tray_content(), app.tray_events.0.clone());

        app.wheel.connect(glib::clone!(
            #[weak]
            app,
            move |event| match event {
                Event::FilesEntered(files) => app.reveal(app.wheel.kind(), &files, None),
                Event::SliceEntered => {
                    if app.settings.borrow().sound {
                        app.sound.tick();
                    }
                }
                Event::Dropped(action, files) => app.run_action(action, files),
            }
        ));
        glib::timeout_add_local(
            Duration::from_millis(50),
            glib::clone!(
                #[weak]
                app,
                #[upgrade_or]
                glib::ControlFlow::Break,
                move || {
                    app.tick();
                    glib::ControlFlow::Continue
                }
            ),
        );
        // Pas de fenêtre principale : l'app reste en vie sans fenêtre ouverte.
        std::mem::forget(application.hold());
        debug(&format!("démarrée ; zone de notification : {}", if app.tray.borrow().is_some() { "oui" } else { "non" }));
        Some(app)
    }

    fn language(&self) -> Language {
        i18n::current()
    }

    fn abilities(&self) -> catalog::Platform {
        convert::abilities(self.tesseract.is_some())
    }

    // MARK: Réglages

    /// Modifie les réglages, les enregistre et les applique.
    fn change_settings(&self, change: impl FnOnce(&mut Settings)) {
        {
            let mut settings = self.settings.borrow_mut();
            change(&mut settings);
            let _ = settings.save(&self.settings_path);
        }
        self.apply_bindings();
        if !self.settings.borrow().enabled && matches!(self.wheel.state(), State::Pending | State::Ready) {
            self.hide_wheel();
        }
        self.refresh_tray();
    }

    fn apply_bindings(&self) {
        let mut detector = self.detector.borrow_mut();
        detector.clear_bindings();
        for (key, kind) in self.settings.borrow().bindings() {
            detector.set_binding(key, kind);
        }
    }

    /// Applique la langue choisie partout, fenêtre de réglages comprise.
    fn language_changed(self: &Rc<Self>) {
        let language = i18n::resolve(&self.settings.borrow().language, &settings::system_locale());
        i18n::set_current(language);
        self.wheel.set_language(language);
        self.refresh_tray();
        let previous = self.settings_window.borrow_mut().take();
        if let Some(window) = previous {
            let was_open = window.is_visible();
            window.destroy();
            if was_open {
                self.open_settings();
            }
        }
    }

    fn open_settings(self: &Rc<Self>) {
        let existing = self.settings_window.borrow().clone();
        let window = existing.unwrap_or_else(|| {
            let window = settings_window::build(self);
            *self.settings_window.borrow_mut() = Some(window.clone());
            window
        });
        window.present();
    }

    fn tray_content(&self) -> TrayContent {
        let language = self.language();
        let settings = self.settings.borrow();
        let hint = |key, modifier| format!("    {}", i18n::format(language, key, &[("key", settings_window::key_name(language, modifier))]));
        TrayContent {
            enabled: settings.enabled,
            enable: i18n::tr(language, "settings.enable").to_owned(),
            hint: i18n::tr(language, "menu.tap_hint").to_owned(),
            convert_hint: hint("menu.convert_hint", settings.conversion_key),
            tools_hint: hint("menu.tools_hint", settings.tools_key),
            last_result: self.last_result.borrow().as_ref().map(|result| i18n::format(language, "menu.last_result", &[("result", result)])),
            settings: i18n::tr(language, "menu.settings").to_owned(),
            quit: i18n::tr(language, "menu.quit").to_owned(),
        }
    }

    fn refresh_tray(&self) {
        if let Some(tray) = self.tray.borrow().as_ref() {
            tray.update(self.tray_content());
        }
    }

    // MARK: Geste

    fn tick(self: &Rc<Self>) {
        while let Ok(event) = self.tray_events.1.try_recv() {
            match event {
                TrayEvent::ToggleEnabled => self.change_settings(|settings| settings.enabled = !settings.enabled),
                TrayEvent::OpenSettings => self.open_settings(),
                TrayEvent::Quit => self.application.quit(),
            }
        }
        while let Ok(outcome) = self.outcomes.1.try_recv() {
            match outcome {
                Ok(count) => self.finish(State::Done, summary::created(count, self.language())),
                Err(message) => self.finish(State::Failed, message),
            }
        }
        if !self.settings.borrow().enabled {
            return;
        }
        let Some(pointer) = self.x11.pointer() else { return };
        let mut drag = self.drag.get();
        if pointer.button_down && !drag.was_down {
            drag.press = (pointer.x, pointer.y);
            drag.counted = false;
        }
        let moved = (pointer.x - drag.press.0).abs() > DRAG_THRESHOLD || (pointer.y - drag.press.1).abs() > DRAG_THRESHOLD;
        if pointer.button_down && !drag.counted && moved {
            drag.generation += 1;
            drag.counted = true;
        }
        drag.was_down = pointer.button_down;
        self.drag.set(drag);

        let sample = Sample { is_mouse_down: pointer.button_down, drag_generation: drag.generation, modifiers: pointer.modifiers };
        let decision = self.detector.borrow_mut().update(sample);
        match decision {
            Decision::Show(kind) => self.present(kind, pointer),
            Decision::Hide => self.dismiss_after_drag(),
            Decision::None => {}
        }
    }

    fn present(&self, kind: WheelKind, pointer: Pointer) {
        debug(&format!("geste : {kind:?} en ({}, {})", pointer.x, pointer.y));
        if matches!(self.wheel.state(), State::Working | State::Done | State::Failed) {
            return;
        }
        match self.wheel.files() {
            Some(files) => self.reveal(kind, &files, Some((pointer.x, pointer.y))),
            None if self.wheel.can_wait_unseen() => self.wheel.show_pending(kind, pointer.x, pointer.y),
            // Sans compositeur, pas de fenêtre invisible : les parts courantes, en attendant les fichiers.
            None => {
                let actions = catalog::common_actions(kind, &self.abilities(), self.language());
                self.wheel.show_actions(kind, actions, Some((pointer.x, pointer.y)));
            }
        }
    }

    /// Les fichiers sont connus : on dessine les parts qui leur conviennent, sinon on referme.
    fn reveal(&self, kind: WheelKind, files: &[PathBuf], position: Option<(i32, i32)>) {
        let inputs: Vec<catalog::Input> = files.iter().map(|file| catalog::input_for_extension(&convert::extension(file))).collect();
        let actions = catalog::actions(kind, &inputs, &self.abilities(), self.language());
        debug(&format!("fichiers : {} ; parts : {}", files.len(), actions.iter().map(|a| a.id.as_str()).collect::<Vec<_>>().join(", ")));
        if actions.is_empty() {
            self.hide_wheel();
            return;
        }
        self.wheel.show_actions(kind, actions, position);
    }

    /// Le dépôt arrive au même moment que le relâchement du bouton : on laisse un instant à
    /// l'action pour démarrer, sinon on ferme.
    fn dismiss_after_drag(self: &Rc<Self>) {
        glib::timeout_add_local_once(
            Duration::from_millis(250),
            glib::clone!(
                #[weak(rename_to = app)]
                self,
                move || {
                    if matches!(app.wheel.state(), State::Pending | State::Ready) {
                        app.wheel.hide();
                    }
                }
            ),
        );
    }

    fn hide_wheel(&self) {
        self.wheel.hide();
        self.detector.borrow_mut().dismiss();
    }

    // MARK: Action

    fn run_action(self: &Rc<Self>, action: Action, files: Vec<PathBuf>) {
        if self.wheel.state() != State::Ready || files.is_empty() {
            return;
        }
        let language = self.language();
        debug(&format!("action : {} sur {} fichier(s)", action.id, files.len()));
        let inputs: Vec<catalog::Input> = files.iter().map(|file| catalog::input_for_extension(&convert::extension(file))).collect();
        if !catalog::actions(self.wheel.kind(), &inputs, &self.abilities(), language).iter().any(|a| a.operation == action.operation) {
            self.finish(State::Failed, i18n::format(language, "error.not_applicable", &[("title", &action.title)]));
            return;
        }
        self.wheel.show_status(State::Working, &action.title);
        // Conversion hors du fil de l'interface ; rien ne s'ouvre : le résultat apparaît
        // simplement à côté de l'original.
        let converter = Converter { language, tesseract: self.tesseract.clone(), ..Converter::default() };
        let sender = self.outcomes.0.clone();
        std::thread::spawn(move || {
            let result = std::panic::catch_unwind(|| converter.perform(&action, &files));
            let outcome = match result {
                Ok(Ok(produced)) => Ok(produced.len()),
                Ok(Err(error)) => Err(error.to_string()),
                Err(_) => Err(i18n::format(language, "error.failed", &[("reason", &action.title)])),
            };
            let _ = sender.send(outcome);
        });
    }

    /// Affiche le résultat au centre du camembert, le garde pour le menu, puis referme.
    fn finish(self: &Rc<Self>, state: State, message: String) {
        debug(&format!("résultat : {message}"));
        self.wheel.show_status(state, &message);
        *self.last_result.borrow_mut() = Some(message);
        self.refresh_tray();
        glib::timeout_add_local_once(
            Duration::from_millis(1200),
            glib::clone!(
                #[weak(rename_to = app)]
                self,
                move || app.hide_wheel()
            ),
        );
    }
}

/// Journal de diagnostic sur la sortie d'erreur, avec `BERGAMOTE_DEBUG=1`.
fn debug(message: &str) {
    if std::env::var_os("BERGAMOTE_DEBUG").is_some() {
        eprintln!("bergamote: {message}");
    }
}
