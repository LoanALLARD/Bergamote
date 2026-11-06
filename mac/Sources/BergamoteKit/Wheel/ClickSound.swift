import Foundation

/// Le « tic » joué quand le curseur passe d'une part du camembert à l'autre. Il est synthétisé
/// plutôt que livré en fichier : une sinusoïde amortie très brève, une pointe de bruit pour
/// l'attaque, et un volume bas, pour un clic discret plutôt qu'un bip.
public enum ClickSound {
    public static func wav(
        sampleRate: Int = 44_100,
        duration: Double = 0.03,
        frequency: Double = 1_800,
        decay: Double = 0.006,
        level: Double = 0.16
    ) -> Data {
        let count = Int(Double(sampleRate) * duration)
        var noise: UInt32 = 0x9E37_79B9
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / Double(sampleRate)
            noise = noise &* 1_664_525 &+ 1_013_904_223
            let white = Double(Int32(bitPattern: noise)) / Double(Int32.max)
            let attack = min(1, t / 0.0008)                       // pas de « pop » au départ
            let release = min(1, (duration - t) / 0.004)          // fin à zéro
            let body = sin(2 * .pi * frequency * t) * exp(-t / decay)
            let snap = white * exp(-t / 0.0007)
            let value = level * attack * release * (0.85 * body + 0.15 * snap)
            samples[index] = Int16((max(-1, min(1, value)) * Double(Int16.max)).rounded())
        }
        return wavFile(samples, sampleRate: sampleRate)
    }

    /// En-tête WAV PCM 16 bits mono, petit-boutiste.
    static func wavFile(_ samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))                      // PCM, mono
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))                     // alignement, bits
        data.append(contentsOf: Array("data".utf8)); append(UInt32(byteCount))
        samples.forEach(append)
        return data
    }
}
