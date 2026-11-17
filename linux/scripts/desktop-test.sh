#!/usr/bin/env bash
# L'app Linux dans une vraie session de bureau (XFCE : gestionnaire de session, gestionnaire de
# fenêtres avec compositeur, tableau de bord, gestionnaire de fichiers Thunar), sur un serveur X
# virtuel :
#   - le réglage « lancer à l'ouverture de session » étant actif, ouvrir la session lance l'app ;
#   - glisser un fichier depuis Thunar, taper Maj, le déposer sur une part le convertit.
#
#   linux/scripts/docker.sh scripts/desktop-test.sh
#
# Les captures d'écran et les journaux vont dans linux/dist/desktop/.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="$PWD/dist/desktop"
WORK="$(mktemp -d)"
rm -rf "$OUT" && mkdir -p "$OUT" "$WORK/files"

cargo build --quiet --bin bergamote || exit 1
BIN="${CARGO_TARGET_DIR:-target}/debug"

# Un utilisateur tout neuf : son dossier personnel, sa langue.
export HOME="$WORK" DISPLAY=:98 LANG=fr_FR.UTF-8 BERGAMOTE_DEBUG=1 GDK_BACKEND=x11
unset XDG_CONFIG_HOME XDG_CACHE_HOME
convert -size 400x300 gradient:blue-yellow "$WORK/files/photo.png"

# Le réglage, tel que la fenêtre de réglages l'enregistre.
"$BIN/bergamote" --autostart on > "$OUT/autostart-entry.txt"

Xvfb :98 -screen 0 1280x800x24 >/dev/null 2>&1 &
sleep 1

dbus-run-session -- bash -s <<INNER
# Ouverture de session : c'est XFCE, et non ce script, qui lance les programmes de démarrage.
xfce4-session > "$OUT/session.log" 2>&1 &
for attempt in \$(seq 1 40); do pgrep -f "bergamote --background" >/dev/null && break; sleep 1; done
pgrep -af "bergamote --background" > "$OUT/autostarted.txt"
sleep 12
import -window root "$OUT/1-session.png"
gdbus call --session --dest org.kde.StatusNotifierWatcher --object-path /StatusNotifierWatcher \
  --method org.freedesktop.DBus.Properties.Get org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems > "$OUT/tray-items.txt" 2>&1

# Le gestionnaire de fichiers du bureau, ouvert sur le dossier du fichier à convertir.
thunar "$WORK/files" >/dev/null 2>&1 &
sleep 6
import -window root "$OUT/2-file-manager.png"

# Glisser l'icône du fichier vers une zone libre du bureau, puis taper Maj.
xdotool mousemove 219 200 mousedown 1
for step in \$(seq 1 20); do xdotool mousemove \$((219 + step * 29)) \$((200 + step * 12)); sleep 0.03; done
sleep 0.4
xdotool keydown shift; sleep 0.15; xdotool keyup shift
sleep 0.3
xdotool mousemove 801 441; sleep 0.2; xdotool mousemove 799 440
sleep 0.8
import -window root "$OUT/3-wheel.png"

# Vers la première part (en haut), puis lâcher.
for step in \$(seq 1 11); do xdotool mousemove 799 \$((440 - step * 10)); sleep 0.03; done
sleep 0.4
import -window root "$OUT/4-slice.png"
xdotool mouseup 1
sleep 3
import -window root "$OUT/5-result.png"
INNER

status=0
ok() { echo "ok    $1"; }
fail() { echo "ÉCHEC $1"; status=1; }
logged() { grep -aq "$1" "$OUT/session.log"; }
if [ -s "$OUT/autostarted.txt" ]; then ok "ouvrir la session XFCE lance Bergamote (entrée de démarrage automatique)"; else fail "Bergamote n'a pas été lancée à l'ouverture de session"; fi
if logged "bergamote: démarrée"; then ok "l'app démarre dans la session"; else fail "l'app n'a pas démarré"; fi
if logged "geste : Conversion"; then ok "le geste (glisser depuis Thunar, puis Maj) est détecté"; else fail "geste non détecté"; fi
if logged "parts : convert_images:jpeg"; then ok "le camembert reçoit le fichier glissé depuis Thunar"; else fail "le camembert n'a pas reçu le fichier"; fi
if logged "action : convert_images:jpeg"; then ok "le dépôt lance la conversion"; else fail "le dépôt n'a rien lancé"; fi
if [ -s "$WORK/files/photo.jpeg" ]; then ok "photo.jpeg est créé à côté de l'original"; else fail "photo.jpeg absent"; fi
if grep -q "StatusNotifierItem" "$OUT/tray-items.txt"; then ok "l'icône est enregistrée dans la zone de notification du tableau de bord"; else echo "note  ce tableau de bord n'offre pas de zone de notification StatusNotifierItem : $(head -c 160 "$OUT/tray-items.txt")"; fi
[ "$status" -eq 0 ] || { echo "--- journal de la session ---"; grep -a "bergamote" "$OUT/session.log"; }
pkill -f "$BIN/bergamote" 2>/dev/null; pkill xfce4-session 2>/dev/null; pkill Xvfb 2>/dev/null
exit "$status"
