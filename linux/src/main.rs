//! Bergamote pour Linux : le camembert de conversion, dans la zone de notification.
//!
//!   bergamote                 démarre l'app et ouvre ses réglages (ou les rouvre si elle tourne déjà)
//!   bergamote --background    démarre sans fenêtre (ouverture de session)
//!   bergamote --version

#[cfg(target_os = "linux")]
mod app;

fn main() -> std::process::ExitCode {
    if std::env::args().any(|argument| argument == "--version") {
        println!("Bergamote {} (cœur {})", env!("CARGO_PKG_VERSION"), bergamote_core::VERSION);
        return std::process::ExitCode::SUCCESS;
    }
    run()
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
