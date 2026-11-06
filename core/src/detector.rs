//! Machine à états du geste : « glisser des fichiers, puis taper une touche de modification ».
//! Une touche déjà maintenue quand le glisser commence ouvre aussi le camembert.
//!
//! Elle ne reçoit que des échantillons (bouton de la souris, génération du glisser, touches
//! enfoncées). Chaque application fournit ces échantillons à sa façon : sur Mac, la génération est
//! le compteur du presse-papiers de glisser-déposer ; sur Windows, un compteur incrémenté quand la
//! souris s'éloigne du point d'appui au-delà du seuil de glisser du système.

use std::collections::HashMap;

/// Touches de modification, en bits : identiques pour toutes les plateformes.
pub type Modifiers = u32;
pub const SHIFT: Modifiers = 1 << 0;
pub const CONTROL: Modifiers = 1 << 1;
/// Option sur Mac, Alt sur Windows.
pub const OPTION: Modifiers = 1 << 2;
/// Commande sur Mac, touche Windows sur Windows.
pub const COMMAND: Modifiers = 1 << 3;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum WheelKind {
    Conversion,
    Tools,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Decision {
    None,
    Show(WheelKind),
    Hide,
}

#[derive(Clone, Copy, Debug)]
pub struct Sample {
    pub is_mouse_down: bool,
    /// Change quand un glisser-déposer démarre.
    pub drag_generation: i64,
    pub modifiers: Modifiers,
}

#[derive(Debug)]
pub struct Detector {
    bindings: HashMap<Modifiers, WheelKind>,
    visible: Option<WheelKind>,
    was_mouse_down: bool,
    idle_generation: Option<i64>,
    generation_at_press: i64,
    is_dragging: bool,
    previous_modifiers: Modifiers,
}

impl Default for Detector {
    /// Raccourcis par défaut du Mac : ⇧ pour convertir, ⌘ pour les outils.
    fn default() -> Self {
        let mut detector = Self::empty();
        detector.set_binding(SHIFT, WheelKind::Conversion);
        detector.set_binding(COMMAND, WheelKind::Tools);
        detector
    }
}

impl Detector {
    pub fn empty() -> Self {
        Self {
            bindings: HashMap::new(),
            visible: None,
            was_mouse_down: false,
            idle_generation: None,
            generation_at_press: 0,
            is_dragging: false,
            previous_modifiers: 0,
        }
    }

    pub fn set_binding(&mut self, modifiers: Modifiers, kind: WheelKind) {
        self.bindings.insert(modifiers, kind);
    }

    pub fn clear_bindings(&mut self) {
        self.bindings.clear();
    }

    pub fn visible(&self) -> Option<WheelKind> {
        self.visible
    }

    /// À appeler quand le camembert se ferme de lui-même (dépôt effectué, Échap).
    pub fn dismiss(&mut self) {
        self.visible = None;
    }

    pub fn update(&mut self, sample: Sample) -> Decision {
        let decision = self.decide(sample);
        self.previous_modifiers = sample.modifiers;
        self.was_mouse_down = sample.is_mouse_down;
        decision
    }

    fn decide(&mut self, sample: Sample) -> Decision {
        if !sample.is_mouse_down {
            self.idle_generation = Some(sample.drag_generation);
            self.is_dragging = false;
            if self.visible.take().is_some() {
                return Decision::Hide;
            }
            return Decision::None;
        }
        if !self.was_mouse_down {
            // Référence prise bouton relâché : si l'échantillon d'appui arrive après le début du
            // glisser (surveillance en retard), le changement reste détecté.
            self.generation_at_press = self.idle_generation.unwrap_or(sample.drag_generation);
            self.is_dragging = false;
        }
        let drag_just_started = !self.is_dragging && sample.drag_generation != self.generation_at_press;
        if drag_just_started {
            self.is_dragging = true;
        }
        // Deux façons d'ouvrir : taper la combinaison pendant le glisser (elle devient exactement
        // l'ensemble des touches enfoncées), ou la maintenir déjà quand le glisser commence.
        if !self.is_dragging || (sample.modifiers == self.previous_modifiers && !drag_just_started) {
            return Decision::None;
        }
        match self.bindings.get(&sample.modifiers) {
            Some(&kind) if Some(kind) != self.visible => {
                self.visible = Some(kind);
                Decision::Show(kind)
            }
            _ => Decision::None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(is_mouse_down: bool, drag_generation: i64, modifiers: Modifiers) -> Sample {
        Sample { is_mouse_down, drag_generation, modifiers }
    }

    #[test]
    fn tapping_shift_while_dragging_opens_conversion_wheel() {
        let mut detector = Detector::default();
        assert_eq!(detector.update(sample(false, 10, 0)), Decision::None);
        assert_eq!(detector.update(sample(true, 10, 0)), Decision::None);
        // Pas encore de glisser : une touche seule ne fait rien.
        assert_eq!(detector.update(sample(true, 10, SHIFT)), Decision::None);
        assert_eq!(detector.update(sample(true, 10, 0)), Decision::None);
        assert_eq!(detector.update(sample(true, 11, 0)), Decision::None);
        assert_eq!(detector.update(sample(true, 11, SHIFT)), Decision::Show(WheelKind::Conversion));
        assert_eq!(detector.update(sample(true, 11, SHIFT)), Decision::None);
        assert_eq!(detector.update(sample(true, 11, COMMAND)), Decision::Show(WheelKind::Tools));
        assert_eq!(detector.update(sample(false, 11, COMMAND)), Decision::Hide);
        assert_eq!(detector.visible(), None);
    }

    #[test]
    fn late_mouse_down_sample_still_sees_the_drag() {
        let mut detector = Detector::default();
        detector.update(sample(false, 4, 0));
        detector.update(sample(true, 5, 0));
        assert_eq!(detector.update(sample(true, 5, SHIFT)), Decision::Show(WheelKind::Conversion));
    }

    /// Appui prolongé, relevé dans les journaux d'un essai réel : ⇧ maintenu avant le clic, puis le
    /// glisser démarre sans que la touche change.
    #[test]
    fn modifier_held_when_the_drag_starts_opens_the_wheel() {
        let mut detector = Detector::default();
        detector.update(sample(false, 1257, SHIFT));
        assert_eq!(detector.update(sample(true, 1257, SHIFT)), Decision::None);
        assert_eq!(detector.update(sample(true, 1260, SHIFT)), Decision::Show(WheelKind::Conversion));
        assert_eq!(detector.update(sample(true, 1260, SHIFT)), Decision::None);
        detector.dismiss();
        assert_eq!(detector.update(sample(true, 1260, SHIFT)), Decision::None);
        detector.update(sample(true, 1260, 0));
        assert_eq!(detector.update(sample(true, 1260, SHIFT)), Decision::Show(WheelKind::Conversion));
    }

    #[test]
    fn custom_bindings_and_unbound_combinations() {
        let mut detector = Detector::empty();
        detector.set_binding(CONTROL, WheelKind::Conversion);
        detector.set_binding(CONTROL | OPTION, WheelKind::Tools);
        detector.update(sample(false, 0, 0));
        detector.update(sample(true, 1, 0));
        assert_eq!(detector.update(sample(true, 1, SHIFT)), Decision::None);
        assert_eq!(detector.update(sample(true, 1, CONTROL | OPTION)), Decision::Show(WheelKind::Tools));
    }

    #[test]
    fn held_unbound_modifier_does_nothing() {
        let mut detector = Detector::default();
        detector.update(sample(false, 1, OPTION));
        detector.update(sample(true, 1, OPTION));
        assert_eq!(detector.update(sample(true, 2, OPTION)), Decision::None);
    }
}
