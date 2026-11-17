#!/usr/bin/env bash
# Test de bout en bout de l'app Linux sous un serveur X virtuel : démarrage, geste (glisser puis
# Maj), affichage du camembert, dépôt sur une part, fichier produit. À lancer dans le conteneur
# de développement ou sur un runner Ubuntu :
#
#   linux/scripts/docker.sh scripts/smoke-test.sh
#
# Les captures d'écran et les journaux vont dans linux/dist/smoke/.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="$PWD/dist/smoke"
WORK="$(mktemp -d)"
rm -rf "$OUT" && mkdir -p "$OUT"

cargo build --quiet --bin bergamote --example drag_source || exit 1
BIN="${CARGO_TARGET_DIR:-target}/debug"

export DISPLAY=:99 XDG_CONFIG_HOME="$WORK/config" XDG_CACHE_HOME="$WORK/cache" LANG="${BERGAMOTE_TEST_LANG:-fr_FR.UTF-8}" BERGAMOTE_DEBUG=1 GDK_BACKEND=x11
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
sleep 1
openbox >/dev/null 2>&1 &
# Un compositeur : sans lui, pas de fenêtre transparente.
picom --backend xrender >/dev/null 2>&1 &
sleep 1

convert -size 400x300 gradient:blue-yellow "$WORK/photo.png"

dbus-run-session -- bash -s <<INNER
"$BIN/bergamote" --background 2> "$OUT/bergamote.log" &
"$BIN/examples/drag_source" "$WORK/photo.png" 2> "$OUT/drag_source.log" &
sleep 3
window=\$(xdotool search --name "Source de glisser" | head -n 1)
xdotool windowmove "\$window" 60 60
sleep 0.5

# Appui dans la source, puis glisser pas à pas vers le milieu de l'écran.
xdotool mousemove 200 180 mousedown 1
for step in \$(seq 1 20); do xdotool mousemove \$((200 + step * 22)) \$((180 + step * 11)); sleep 0.03; done
sleep 0.4
import -window root "$OUT/1-dragging.png"

# Taper Maj : le camembert de conversion s'ouvre sous le curseur (640, 400).
xdotool keydown shift; sleep 0.15; xdotool keyup shift
sleep 0.3
xdotool mousemove 642 401; sleep 0.2; xdotool mousemove 640 400
sleep 0.8
import -window root "$OUT/2-wheel.png"

# Vers la première part (en haut), puis lâcher.
for step in \$(seq 1 11); do xdotool mousemove 640 \$((400 - step * 10)); sleep 0.03; done
sleep 0.4
import -window root "$OUT/3-slice.png"
xdotool mouseup 1
sleep 0.6
import -window root "$OUT/4-result.png"
sleep 2
xdotool mousemove 900 600 # le camembert est refermé
sleep 0.3
import -window root "$OUT/5-after.png"

# Relancer l'app pendant qu'elle tourne ouvre ses réglages.
"$BIN/bergamote" 2>> "$OUT/bergamote.log"
sleep 1.5
xdotool search --name "Réglages de Bergamote" > "$OUT/settings-window.txt" || true
import -window root "$OUT/6-settings.png"

# Passer la langue à « English » : la fenêtre se reconstruit en anglais.
# (La fenêtre de réglages est centrée par le gestionnaire de fenêtres : la liste des langues est là.)
xdotool mousemove 770 550 click 1
sleep 0.6
xdotool key Down Down Return
sleep 1.2
xdotool search --name "Bergamote Settings" > "$OUT/settings-english.txt" || true
import -window root "$OUT/7-settings-english.png"
INNER

status=0
check() { if grep -q "$1" "$OUT/bergamote.log"; then echo "ok    $2"; else echo "ÉCHEC $2"; status=1; fi; }
check "démarrée" "l'app démarre"
check "geste : Conversion" "le geste est détecté"
check "parts : convert_images:jpeg" "le camembert reçoit le fichier glissé"
check "action : convert_images:jpeg" "le dépôt lance la conversion"
check "résultat : 1 fichier créé" "la conversion aboutit"
if [ -s "$OUT/settings-window.txt" ]; then echo "ok    relancer l'app ouvre les réglages"; else echo "ÉCHEC pas de fenêtre de réglages"; status=1; fi
if [ -s "$OUT/settings-english.txt" ]; then echo "ok    changer de langue s'applique tout de suite"; else echo "ÉCHEC la fenêtre n'est pas passée en anglais"; status=1; fi
if [ -s "$WORK/photo.jpeg" ]; then echo "ok    photo.jpeg est créé à côté de l'original"; else echo "ÉCHEC photo.jpeg absent"; status=1; fi
[ "$status" -eq 0 ] || { echo "--- journal ---"; cat "$OUT/bergamote.log" "$OUT/drag_source.log"; }
pkill -f "$BIN/bergamote" 2>/dev/null; pkill Xvfb 2>/dev/null
exit "$status"
