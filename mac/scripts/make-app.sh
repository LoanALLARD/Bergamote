#!/usr/bin/env bash
# Assemble build/Bergamote.app à partir du build SwiftPM : sandbox active, aucun droit réseau.
#
#   scripts/make-app.sh                      # signature ad hoc (usage local)
#   SIGN_IDENTITY="Developer ID Application: …" scripts/make-app.sh   # pour notariser ensuite
#   SWIFT_BUILD_FLAGS="--arch arm64 --arch x86_64" scripts/make-app.sh   # binaire universel
set -euo pipefail
cd "$(dirname "$0")/.."

# Le cœur Rust partagé : recompilé s'il manque ou si ses sources ont changé.
FRAMEWORK="Frameworks/BergamoteCoreFFI.xcframework"
if [[ ! -d "$FRAMEWORK" || -n "$(find ../core/src ../core/include ../core/Cargo.toml -newer "$FRAMEWORK" -print -quit)" ]]; then
  scripts/build-core.sh
fi

CONFIG="${CONFIG:-release}"
read -r -a EXTRA_FLAGS <<< "${SWIFT_BUILD_FLAGS:-}"
swift build -c "$CONFIG" --product Bergamote ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"})"

APP="build/Bergamote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Bergamote" "$APP/Contents/MacOS/"
cp Packaging/Info.plist "$APP/Contents/"

codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime \
  --entitlements Packaging/Bergamote.entitlements "$APP"
echo "OK : $APP"
