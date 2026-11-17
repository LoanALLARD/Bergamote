#!/usr/bin/env bash
# Compile l'app Linux et l'emballe pour la distribution :
#
#   dist/bergamote_<version>_<arch>.deb            Debian, Ubuntu, Mint…
#   dist/bergamote-<version>-linux-<arch>.tar.gz   toute distribution (install.sh, sans droits root)
#
#   linux/scripts/package.sh          # sur une machine Linux avec GTK 4 (libgtk-4-dev)
#   linux/scripts/docker.sh scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

cargo build --release --bin bergamote
BINARY="${CARGO_TARGET_DIR:-target}/release/bergamote"
VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -n 1)"
MACHINE="$(uname -m)"
DEB_ARCH="$(dpkg --print-architecture 2>/dev/null || echo "$MACHINE")"
DESKTOP=io.github.loanallard.Bergamote.desktop
OUT="$PWD/dist"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

# Archive pour toute distribution.
NAME="bergamote-$VERSION-linux-$MACHINE"
mkdir -p "$WORK/$NAME"
install -m 755 "$BINARY" "$WORK/$NAME/bergamote"
install -m 644 "data/$DESKTOP" data/bergamote.svg "$WORK/$NAME/"
cat > "$WORK/$NAME/install.sh" <<'INSTALL'
#!/usr/bin/env sh
# Installs Bergamote for the current user (no root needed). Requires GTK 4.
set -eu
cd "$(dirname "$0")"
PREFIX="${PREFIX:-$HOME/.local}"
install -Dm755 bergamote "$PREFIX/bin/bergamote"
install -Dm644 bergamote.svg "$PREFIX/share/icons/hicolor/scalable/apps/bergamote.svg"
install -Dm644 io.github.loanallard.Bergamote.desktop "$PREFIX/share/applications/io.github.loanallard.Bergamote.desktop"
sed -i "s|^Exec=bergamote|Exec=$PREFIX/bin/bergamote|" "$PREFIX/share/applications/io.github.loanallard.Bergamote.desktop"
echo "Bergamote is installed in $PREFIX/bin. Start it from your applications menu, or run: $PREFIX/bin/bergamote"
INSTALL
chmod 755 "$WORK/$NAME/install.sh"
tar -C "$WORK" -czf "$OUT/$NAME.tar.gz" "$NAME"
echo "OK : $OUT/$NAME.tar.gz"

# Paquet Debian.
if command -v dpkg-deb >/dev/null 2>&1; then
  ROOT="$WORK/deb"
  install -Dm755 "$BINARY" "$ROOT/usr/bin/bergamote"
  install -Dm644 "data/$DESKTOP" "$ROOT/usr/share/applications/$DESKTOP"
  install -Dm644 data/bergamote.svg "$ROOT/usr/share/icons/hicolor/scalable/apps/bergamote.svg"
  # Dépendances d'après les bibliothèques réellement liées, sinon le minimum connu.
  DEPENDS="libgtk-4-1 (>= 4.6), libc6"
  if command -v dpkg-shlibdeps >/dev/null 2>&1; then
    mkdir -p "$WORK/shlibs/debian" && echo "Source: bergamote" > "$WORK/shlibs/debian/control"
    FOUND="$(cd "$WORK/shlibs" && dpkg-shlibdeps -O "$ROOT/usr/bin/bergamote" 2>/dev/null | sed -n 's/^shlibs:Depends=//p' || true)"
    [ -n "$FOUND" ] && DEPENDS="$FOUND"
  fi
  mkdir -p "$ROOT/DEBIAN"
  cat > "$ROOT/DEBIAN/control" <<CONTROL
Package: bergamote
Version: $VERSION
Architecture: $DEB_ARCH
Maintainer: Loan Allard <LoanALLARD@users.noreply.github.com>
Section: utils
Priority: optional
Depends: $DEPENDS
Recommends: tesseract-ocr, tesseract-ocr-fra, adwaita-icon-theme
Homepage: https://loanallard.github.io/Bergamote/
Description: Radial file converter
 Drag files, tap a modifier key and drop them on a slice of the wheel that
 opens under the cursor: convert, compress, anonymize, merge or extract text.
 The result is written next to the original. Everything happens on this
 computer.
CONTROL
  dpkg-deb --build --root-owner-group "$ROOT" "$OUT/bergamote_${VERSION}_${DEB_ARCH}.deb" >/dev/null
  echo "OK : $OUT/bergamote_${VERSION}_${DEB_ARCH}.deb"
fi
