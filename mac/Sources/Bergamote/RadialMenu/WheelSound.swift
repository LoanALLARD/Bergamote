import AppKit
import BergamoteKit

/// Joue le clic de survol. Un même `NSSound` ne se relance pas tant qu'il joue encore : avec un
/// seul son, passer vite d'une part à l'autre restait muet. On alterne donc entre trois voix,
/// arrêtées puis relancées, pour qu'un clic parte à chaque changement de part.
@MainActor
enum WheelSound {
    private static let voices: [NSSound] = {
        let data = ClickSound.wav()
        return (0..<3).compactMap { _ in NSSound(data: data) }
    }()
    private static var next = 0

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: RadialMenuController.soundKey) as? Bool ?? true
    }

    static func tick(force: Bool = false) {
        guard force || isEnabled, !voices.isEmpty else { return }
        let voice = voices[next]
        next = (next + 1) % voices.count
        voice.stop()
        voice.play()
    }
}
