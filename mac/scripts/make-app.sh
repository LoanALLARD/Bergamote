#!/usr/bin/env bash
# Assemble build/Bergamote.app à partir du build SwiftPM : sandbox active, aucun droit réseau.
#
#   scripts/make-app.sh                      # signature ad hoc (usage local)
#   SIGN_IDENTITY="Developer ID Application: …" scripts/make-app.sh   # pour notariser ensuite
#   ARCHS="arm64 x86_64" scripts/make-app.sh   # binaire universel
set -euo pipefail
cd "$(dirname "$0")/.."

# Le cœur Rust partagé : recompilé s'il manque ou si ses sources ont changé.
FRAMEWORK="Frameworks/BergamoteCoreFFI.xcframework"
if [[ ! -d "$FRAMEWORK" || -n "$(find ../core/src ../core/include ../core/Cargo.toml -newer "$FRAMEWORK" -print -quit)" ]]; then
  scripts/build-core.sh
fi

CONFIG="${CONFIG:-release}"
# ARCHS="arm64 x86_64" : binaire universel. Chaque architecture est compilée séparément puis
# assemblée par lipo (la compilation multi-architecture de SwiftPM ne lie pas toujours le cœur).
ARCHS="${ARCHS:-$(uname -m)}"
BINARIES=()
for ARCH in $ARCHS; do
  swift build -c "$CONFIG" --product Bergamote --arch "$ARCH"
  BINARIES+=("$(swift build -c "$CONFIG" --show-bin-path --arch "$ARCH")/Bergamote")
done

APP="build/Bergamote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Bergamote"
cp Packaging/Info.plist "$APP/Contents/"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/"   # généré par brand/make-icons.swift

codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime \
  --entitlements Packaging/Bergamote.entitlements "$APP"
echo "OK : $APP"
