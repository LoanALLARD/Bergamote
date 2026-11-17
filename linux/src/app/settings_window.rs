//! La fenêtre de réglages : touches des deux camemberts, clic sonore, lancement à l'ouverture de
//! session, langue. Elle s'ouvre au premier lancement, depuis l'icône, ou en relançant l'app.

use std::rc::Rc;

use bergamote_core::detector::{COMMAND, CONTROL, OPTION, SHIFT};
use bergamote_core::i18n::{self, Language};
use bergamote_linux::autostart;
use gtk::prelude::*;
use gtk::glib;

use super::App;

/// Touches proposées, avec la clé de leur nom.
pub const KEYS: [(u32, &str); 4] = [(SHIFT, "key.shift"), (CONTROL, "key.control"), (OPTION, "key.alt"), (COMMAND, "key.super")];

/// Réglage de langue : celle du système, puis les langues du cœur.
const LANGUAGES: [&str; 3] = ["system", "fr", "en"];

pub fn key_name(language: Language, key: u32) -> &'static str {
    KEYS.iter().find(|(bits, _)| *bits == key).map_or("?", |(_, name)| i18n::tr(language, name))
}

pub fn build(app: &Rc<App>) -> gtk::Window {
    let language = app.language();
    let tr = move |key: &'static str| i18n::tr(language, key);
    let settings = app.settings.borrow().clone();

    let window = gtk::Window::builder().application(&app.application).title(tr("settings.title")).resizable(false).default_width(460).build();
    window.set_icon_name(Some("bergamote"));
    let column = gtk::Box::new(gtk::Orientation::Vertical, 10);
    column.set_margin_top(20);
    column.set_margin_bottom(20);
    column.set_margin_start(22);
    column.set_margin_end(22);

    let note = |text: &str, class: &str| {
        let label = gtk::Label::new(Some(text));
        label.set_wrap(true);
        label.set_xalign(0.0);
        label.set_max_width_chars(58);
        label.add_css_class(class);
        label
    };

    if app.wayland {
        column.append(&note(tr("settings.wayland"), "warning"));
    }

    let enabled = gtk::CheckButton::with_label(tr("settings.enable"));
    enabled.set_active(settings.enabled);
    enabled.connect_toggled(glib::clone!(
        #[weak]
        app,
        move |button| app.change_settings(|settings| settings.enabled = button.is_active())
    ));
    column.append(&enabled);

    let conflict = note(tr("settings.key_conflict"), "warning");
    conflict.set_visible(settings.conversion_key == settings.tools_key);
    let names: Vec<&str> = KEYS.iter().map(|(_, name)| tr(name)).collect();
    let key_row = |label: &str, current: u32, apply: fn(&mut bergamote_linux::settings::Settings, u32)| {
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        let title = gtk::Label::new(Some(label));
        title.set_xalign(0.0);
        title.set_hexpand(true);
        let choices = gtk::DropDown::from_strings(&names);
        choices.set_selected(KEYS.iter().position(|(bits, _)| *bits == current).unwrap_or(0) as u32);
        choices.connect_selected_notify(glib::clone!(
            #[weak]
            app,
            #[weak]
            conflict,
            move |choices| {
                let key = KEYS.get(choices.selected() as usize).map_or(SHIFT, |(bits, _)| *bits);
                app.change_settings(|settings| apply(settings, key));
                let settings = app.settings.borrow();
                conflict.set_visible(settings.conversion_key == settings.tools_key);
            }
        ));
        row.append(&title);
        row.append(&choices);
        row
    };
    column.append(&key_row(tr("settings.conversion_key"), settings.conversion_key, |settings, key| settings.conversion_key = key));
    column.append(&key_row(tr("settings.tools_key"), settings.tools_key, |settings, key| settings.tools_key = key));
    column.append(&conflict);

    let sound_row = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    let sound = gtk::CheckButton::with_label(tr("settings.sound"));
    sound.set_active(settings.sound);
    sound.set_hexpand(true);
    sound.connect_toggled(glib::clone!(
        #[weak]
        app,
        move |button| app.change_settings(|settings| settings.sound = button.is_active())
    ));
    let listen = gtk::Button::with_label(tr("settings.listen"));
    listen.connect_clicked(glib::clone!(
        #[weak]
        app,
        move |_| {
            app.sound.tick();
            glib::timeout_add_local_once(std::time::Duration::from_millis(140), move || app.sound.tick());
        }
    ));
    sound_row.append(&sound);
    sound_row.append(&listen);
    column.append(&sound_row);

    let login = gtk::CheckButton::with_label(tr("settings.login"));
    login.set_active(autostart::is_enabled(&autostart::folder()));
    login.connect_toggled(|button| {
        if let Ok(executable) = std::env::current_exe() {
            if autostart::set_enabled(&autostart::folder(), button.is_active(), &executable).is_err() {
                button.set_active(autostart::is_enabled(&autostart::folder()));
            }
        }
    });
    column.append(&login);

    let language_row = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    let language_title = gtk::Label::new(Some(tr("settings.language")));
    language_title.set_xalign(0.0);
    language_title.set_hexpand(true);
    let languages = gtk::DropDown::from_strings(&[tr("settings.language_system"), Language::French.name(), Language::English.name()]);
    languages.set_selected(LANGUAGES.iter().position(|code| *code == settings.language).unwrap_or(0) as u32);
    languages.connect_selected_notify(glib::clone!(
        #[weak]
        app,
        move |choices| {
            let code = LANGUAGES.get(choices.selected() as usize).copied().unwrap_or("system");
            app.change_settings(|settings| settings.language = code.to_owned());
            // La fenêtre est reconstruite dans la nouvelle langue, une fois ce signal terminé.
            glib::idle_add_local_once(move || app.language_changed());
        }
    ));
    language_row.append(&language_title);
    language_row.append(&languages);
    column.append(&language_row);

    let source = tr("source.files");
    column.append(&note(&i18n::format(language, "settings.gesture_help", &[("source", source)]), "dim-label"));
    column.append(&note(tr("settings.result_help"), "dim-label"));
    if app.tesseract.is_none() {
        column.append(&note(tr("settings.no_ocr"), "dim-label"));
    }

    let buttons = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    buttons.set_halign(gtk::Align::End);
    buttons.set_margin_top(6);
    let quit = gtk::Button::with_label(tr("menu.quit"));
    quit.connect_clicked(glib::clone!(
        #[weak]
        app,
        move |_| app.application.quit()
    ));
    let close = gtk::Button::with_label(tr("settings.close"));
    close.add_css_class("suggested-action");
    close.connect_clicked(glib::clone!(
        #[weak]
        window,
        move |_| window.set_visible(false)
    ));
    buttons.append(&quit);
    buttons.append(&close);
    column.append(&note(tr("settings.running"), "dim-label"));
    column.append(&buttons);

    window.set_child(Some(&column));
    // Fermer la fenêtre ne quitte pas l'app : elle continue en arrière-plan.
    window.connect_close_request(|window| {
        window.set_visible(false);
        glib::Propagation::Stop
    });
    window
}
