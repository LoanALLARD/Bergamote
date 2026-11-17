//! Pictogrammes des parts, tracés au trait : le même dessin quel que soit le thème d'icônes du
//! bureau. Chaque icône tient dans un carré de 18 unités centré sur l'origine.

use std::f64::consts::PI;

use gtk::cairo::{Context, LineCap, LineJoin};

/// Dessine l'icône `name` (nom abstrait du cœur) centrée en (x, y), dans la couleur courante.
pub fn draw(context: &Context, name: &str, x: f64, y: f64) {
    context.save().ok();
    context.translate(x, y);
    context.set_line_width(1.5);
    context.set_line_cap(LineCap::Round);
    context.set_line_join(LineJoin::Round);
    context.new_path();
    match name {
        "photo" => {
            rounded_rectangle(context, -8.0, -6.5, 16.0, 13.0, 2.0);
            polyline(context, &[(-7.0, 4.5), (-2.5, 0.0), (1.0, 3.0), (3.5, 1.0), (7.0, 4.5)]);
            stroke(context);
            context.arc(-3.5, -2.5, 1.4, 0.0, 2.0 * PI);
            let _ = context.fill();
        }
        "pages" => {
            rounded_rectangle(context, -7.5, -4.5, 11.0, 12.5, 1.5);
            polyline(context, &[(-3.5, -8.0), (7.5, -8.0), (7.5, 4.5)]);
            stroke(context);
        }
        "document" | "word" => {
            page(context);
            if name == "word" {
                polyline(context, &[(-3.5, 0.0), (-2.0, 5.0), (0.0, 1.5), (2.0, 5.0), (3.5, 0.0)]);
            } else {
                lines(context, &[(-3.0, 3.0, 0.5), (-3.0, 3.0, 4.0)]);
            }
            stroke(context);
        }
        "text" => {
            lines(context, &[(-7.0, 7.0, -6.0), (-7.0, 3.5, -2.0), (-7.0, 7.0, 2.0), (-7.0, 0.5, 6.0)]);
            stroke(context);
        }
        "rich_text" => {
            polyline(context, &[(-5.0, 5.0), (0.0, -8.0), (5.0, 5.0)]);
            lines(context, &[(-3.0, 3.0, 0.5), (-7.0, 7.0, 8.2)]);
            stroke(context);
        }
        "compress" => {
            for sign in [-1.0, 1.0] {
                polyline(context, &[(sign * 8.0, sign * 8.0), (sign * 2.5, sign * 2.5)]);
                polyline(context, &[(sign * 7.0, sign * 2.5), (sign * 2.5, sign * 2.5), (sign * 2.5, sign * 7.0)]);
            }
            stroke(context);
        }
        "anonymize" => {
            context.move_to(-8.0, 0.0);
            context.curve_to(-4.0, -6.5, 4.0, -6.5, 8.0, 0.0);
            context.curve_to(4.0, 6.5, -4.0, 6.5, -8.0, 0.0);
            context.close_path();
            context.new_sub_path();
            context.arc(0.0, 0.0, 2.2, 0.0, 2.0 * PI);
            polyline(context, &[(-7.0, 7.5), (7.0, -7.5)]);
            stroke(context);
        }
        "searchable" => {
            context.arc(-1.5, -1.5, 5.2, 0.0, 2.0 * PI);
            polyline(context, &[(2.4, 2.4), (7.5, 7.5)]);
            stroke(context);
        }
        "merge" => {
            rounded_rectangle(context, -8.0, -8.0, 10.5, 10.5, 1.5);
            rounded_rectangle(context, -2.5, -2.5, 10.5, 10.5, 1.5);
            stroke(context);
        }
        // "extract" et tout nom inconnu : du texte qui sort du document.
        _ => {
            lines(context, &[(-7.0, 7.0, -7.0), (-7.0, 7.0, -3.0)]);
            polyline(context, &[(0.0, 0.5), (0.0, 8.0)]);
            polyline(context, &[(-3.2, 4.8), (0.0, 8.0), (3.2, 4.8)]);
            stroke(context);
        }
    }
    context.restore().ok();
}

fn stroke(context: &Context) {
    let _ = context.stroke();
}

fn polyline(context: &Context, points: &[(f64, f64)]) {
    for (index, (x, y)) in points.iter().enumerate() {
        if index == 0 {
            context.move_to(*x, *y);
        } else {
            context.line_to(*x, *y);
        }
    }
}

/// Traits horizontaux : (x de début, x de fin, y).
fn lines(context: &Context, segments: &[(f64, f64, f64)]) {
    for (start, end, y) in segments {
        context.move_to(*start, *y);
        context.line_to(*end, *y);
    }
}

/// Feuille au coin replié.
fn page(context: &Context) {
    polyline(context, &[(-6.0, -8.0), (2.0, -8.0), (6.0, -4.0), (6.0, 8.0), (-6.0, 8.0)]);
    context.close_path();
    polyline(context, &[(2.0, -8.0), (2.0, -4.0), (6.0, -4.0)]);
}

fn rounded_rectangle(context: &Context, x: f64, y: f64, width: f64, height: f64, radius: f64) {
    context.new_sub_path();
    context.arc(x + width - radius, y + radius, radius, -PI / 2.0, 0.0);
    context.arc(x + width - radius, y + height - radius, radius, 0.0, PI / 2.0);
    context.arc(x + radius, y + height - radius, radius, PI / 2.0, PI);
    context.arc(x + radius, y + radius, radius, PI, 1.5 * PI);
    context.close_path();
}
