//! Bergamote pour Linux : le camembert de conversion, dans la zone de notification.
//!
//!   bergamote                 démarre l'app et ouvre ses réglages (ou les rouvre si elle tourne déjà)
//!   bergamote --background    démarre sans fenêtre (ouverture de session)
//!   bergamote --autostart on|off   active ou désactive le lancement à l'ouverture de session
//!   bergamote --version

#[cfg(target_os = "linux")]
mod app;

fn main() -> std::process::ExitCode {
    if std::env::args().any(|argument| argument == "--version") {
        println!("Bergamote {} (cœur {})", env!("CARGO_PKG_VERSION"), bergamote_core::VERSION);
        return std::process::ExitCode::SUCCESS;
    }
    let arguments: Vec<String> = std::env::args().collect();
    if let Some(position) = arguments.iter().position(|argument| argument == "--autostart") {
        return set_autostart(arguments.get(position + 1).map(String::as_str));
    }
    run()
}

/// Le réglage « lancer à l'ouverture de session », sans passer par la fenêtre : pour un script
/// d'installation ou un administrateur.
fn set_autostart(choice: Option<&str>) -> std::process::ExitCode {
    use bergamote_linux::autostart;
    let enabled = match choice {
        Some("on") => true,
        Some("off") => false,
        _ => {
            eprintln!("Usage : bergamote --autostart on|off");
            return std::process::ExitCode::FAILURE;
        }
    };
    let result = std::env::current_exe().and_then(|executable| autostart::set_enabled(&autostart::folder(), enabled, &executable));
    match result {
        Ok(()) => {
            println!("{}", autostart::folder().join("bergamote.desktop").display());
            std::process::ExitCode::SUCCESS
        }
        Err(error) => {
            eprintln!("Bergamote : {error}");
            std::process::ExitCode::FAILURE
        }
    }
}

#[cfg(target_os = "linux")]
fn run() -> std::process::ExitCode {
    app::run()
}

#[cfg(not(target_os = "linux"))]
fn run() -> std::process::ExitCode {
    eprintln!("Ce binaire est l'app Linux de Bergamote : sur ce système, seules ses conversions se compilent (cargo test).");
    std::process::ExitCode::FAILURE
}
