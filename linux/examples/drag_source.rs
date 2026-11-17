//! Outil de test : une fenêtre dont le contenu se glisse comme une liste de fichiers, pour
//! simuler un glisser depuis un gestionnaire de fichiers (voir scripts/smoke-test.sh).
//!
//!   cargo run --example drag_source -- photo.png scan.pdf

#[cfg(target_os = "linux")]
fn main() {
    use gtk::prelude::*;
    use gtk::{gdk, gio, glib};

    // Comme un gestionnaire de fichiers : la liste part au format text/uri-list.
    let uris: Vec<String> = std::env::args().skip(1).map(|path| gio::File::for_path(path).uri().to_string()).collect();
    let application = gtk::Application::builder().application_id("io.github.loanallard.Bergamote.DragSource").build();
    application.connect_activate(move |application| {
        let label = gtk::Label::new(Some(&format!("Glisser {} fichier(s)", uris.len())));
        label.set_size_request(300, 200);
        let source = gtk::DragSource::new();
        source.set_actions(gdk::DragAction::COPY | gdk::DragAction::MOVE);
        let list = glib::Bytes::from_owned(uris.iter().map(|uri| format!("{uri}\r\n")).collect::<String>().into_bytes());
        source.connect_prepare(move |_, _, _| Some(gdk::ContentProvider::for_bytes("text/uri-list", &list)));
        source.connect_drag_end(|_, _, _| eprintln!("drag_source: glisser terminé"));
        source.connect_drag_cancel(|_, _, reason| {
            eprintln!("drag_source: glisser annulé ({reason:?})");
            false
        });
        label.add_controller(source);
        let window = gtk::ApplicationWindow::builder().application(application).title("Source de glisser").child(&label).build();
        window.present();
    });
    let _: glib::ExitCode = application.run_with_args::<&str>(&[]);
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("Cet outil de test ne tourne que sous Linux.");
}
