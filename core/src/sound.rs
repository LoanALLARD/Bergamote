//! Le « tic » joué quand le curseur passe d'une part du camembert à l'autre. Il est synthétisé
//! plutôt que livré en fichier : une sinusoïde amortie très brève, une pointe de bruit pour
//! l'attaque, et un volume bas, pour un clic discret plutôt qu'un bip. Format WAV PCM 16 bits mono,
//! lisible tel quel par `NSSound` (Mac) et `SoundPlayer` (Windows).

use std::f64::consts::PI;

pub const SAMPLE_RATE: u32 = 44_100;
const DURATION: f64 = 0.03;
const FREQUENCY: f64 = 1_800.0;
const DECAY: f64 = 0.006;
const LEVEL: f64 = 0.16;

pub fn click_wav() -> Vec<u8> {
    let count = (SAMPLE_RATE as f64 * DURATION) as usize;
    let mut noise: u32 = 0x9E37_79B9;
    let samples: Vec<i16> = (0..count)
        .map(|index| {
            let t = index as f64 / SAMPLE_RATE as f64;
            noise = noise.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            let white = (noise as i32) as f64 / i32::MAX as f64;
            let attack = (t / 0.0008).min(1.0); // pas de « pop » au départ
            let release = ((DURATION - t) / 0.004).min(1.0); // fin à zéro
            let body = (2.0 * PI * FREQUENCY * t).sin() * (-t / DECAY).exp();
            let snap = white * (-t / 0.0007).exp();
            let value = LEVEL * attack * release * (0.85 * body + 0.15 * snap);
            (value.clamp(-1.0, 1.0) * i16::MAX as f64).round() as i16
        })
        .collect();
    wav_file(&samples, SAMPLE_RATE)
}

/// En-tête WAV PCM 16 bits mono, petit-boutiste.
fn wav_file(samples: &[i16], sample_rate: u32) -> Vec<u8> {
    let byte_count = (samples.len() * 2) as u32;
    let mut data = Vec::with_capacity(44 + byte_count as usize);
    data.extend_from_slice(b"RIFF");
    data.extend_from_slice(&(36 + byte_count).to_le_bytes());
    data.extend_from_slice(b"WAVEfmt ");
    data.extend_from_slice(&16u32.to_le_bytes());
    data.extend_from_slice(&1u16.to_le_bytes()); // PCM
    data.extend_from_slice(&1u16.to_le_bytes()); // mono
    data.extend_from_slice(&sample_rate.to_le_bytes());
    data.extend_from_slice(&(sample_rate * 2).to_le_bytes());
    data.extend_from_slice(&2u16.to_le_bytes()); // alignement
    data.extend_from_slice(&16u16.to_le_bytes()); // bits
    data.extend_from_slice(b"data");
    data.extend_from_slice(&byte_count.to_le_bytes());
    for sample in samples {
        data.extend_from_slice(&sample.to_le_bytes());
    }
    data
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn click_is_short_and_soft() {
        let wav = click_wav();
        assert_eq!(&wav[0..4], b"RIFF");
        assert_eq!(&wav[8..16], b"WAVEfmt ");
        let samples: Vec<i16> = wav[44..].as_chunks::<2>().0.iter().map(|b| i16::from_le_bytes(*b)).collect();
        assert_eq!(samples.len(), 1_323); // 30 ms à 44,1 kHz
        let peak = samples.iter().map(|s| (*s as i32).abs()).max().unwrap() as f64 / i16::MAX as f64;
        assert!(peak > 0.05 && peak <= 0.17, "niveau de crête {peak}");
        assert!(samples[samples.len() - 10..].iter().all(|s| (*s as i32).abs() < 200), "fin sans craquement");
    }
}
