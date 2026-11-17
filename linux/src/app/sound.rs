//! Le clic au passage d'une part : le WAV synthétisé par le cœur, joué par le lecteur du système
//! (PipeWire, PulseAudio ou ALSA).

use std::path::PathBuf;
use std::process::{Command, Stdio};

pub struct Sound {
    /// Lecteur trouvé et ses arguments, puis le fichier du clic.
    player: Option<(PathBuf, &'static [&'static str])>,
    file: PathBuf,
}

impl Sound {
    pub fn new() -> Self {
        let file = bergamote_linux::settings::cache_dir().join("bergamote").join("click.wav");
        if let Some(folder) = file.parent() {
            let _ = std::fs::create_dir_all(folder);
        }
        let _ = std::fs::write(&file, bergamote_core::sound::click_wav());
        let candidates: [(&str, &'static [&'static str]); 3] = [("pw-play", &[]), ("paplay", &[]), ("aplay", &["-q"])];
        let player = candidates.into_iter().find_map(|(name, arguments)| find_program(name).map(|path| (path, arguments)));
        Self { player, file }
    }

    /// Joue le clic sans attendre la fin : le son dure 30 ms.
    pub fn tick(&self) {
        let Some((program, arguments)) = &self.player else { return };
        let child = Command::new(program).args(*arguments).arg(&self.file).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn();
        if let Ok(mut child) = child {
            // Un fil attend la fin du lecteur, pour ne pas laisser de processus zombie.
            std::thread::spawn(move || {
                let _ = child.wait();
            });
        }
    }
}

pub fn find_program(name: &str) -> Option<PathBuf> {
    std::env::split_paths(&std::env::var_os("PATH")?).map(|folder| folder.join(name)).find(|path| path.is_file())
}
