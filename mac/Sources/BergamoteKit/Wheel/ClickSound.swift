import BergamoteCoreFFI
import Foundation

/// Le « tic » joué quand le curseur passe d'une part du camembert à l'autre : un clic discret
/// synthétisé par le cœur partagé (`core/src/sound.rs`), identique sur Mac et Windows.
public enum ClickSound {
    public static func wav() -> Data {
        var length = 0
        guard let bytes = bgm_click_wav(&length) else { return Data() }
        defer { bgm_bytes_free(bytes, length) }
        return Data(bytes: bytes, count: length)
    }
}
