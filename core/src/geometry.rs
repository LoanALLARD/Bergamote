//! Géométrie du camembert : la part 0 est centrée en haut, puis sens horaire.

use std::f64::consts::PI;

/// Part sous le point `(x, y)`, exprimé par rapport au centre avec l'axe y vers le haut ;
/// `None` dans le trou central ou hors du disque.
pub fn slice_at(x: f64, y: f64, count: usize, inner_radius: f64, outer_radius: f64) -> Option<usize> {
    let distance = x.hypot(y);
    if count == 0 || distance < inner_radius || distance > outer_radius {
        return None;
    }
    let mut angle = x.atan2(y); // 0 en haut, positif vers la droite
    if angle < 0.0 {
        angle += 2.0 * PI;
    }
    let width = 2.0 * PI / count as f64;
    Some(((angle + width / 2.0) / width) as usize % count)
}

/// Angle du milieu de la part, en radians depuis le haut, sens horaire.
pub fn center_angle(index: usize, count: usize) -> f64 {
    index as f64 * 2.0 * PI / count.max(1) as f64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slice_geometry() {
        let hit = |x: f64, y: f64| slice_at(x, y, 4, 50.0, 150.0);
        assert_eq!(hit(0.0, 100.0), Some(0)); // en haut
        assert_eq!(hit(100.0, 0.0), Some(1)); // à droite
        assert_eq!(hit(0.0, -100.0), Some(2)); // en bas
        assert_eq!(hit(-100.0, 0.0), Some(3)); // à gauche
        assert_eq!(hit(10.0, 10.0), None); // trou central
        assert_eq!(hit(200.0, 0.0), None); // hors du disque
        assert_eq!(slice_at(-1.0, 100.0, 8, 50.0, 150.0), Some(0));
    }

    #[test]
    fn center_angles_round_trip() {
        for count in 1..=8 {
            for index in 0..count {
                let angle = center_angle(index, count);
                let (x, y) = (angle.sin() * 100.0, angle.cos() * 100.0);
                assert_eq!(slice_at(x, y, count, 50.0, 150.0), Some(index));
            }
        }
    }
}
