#!/usr/bin/env bash
# Compile le cœur Rust (core/) en bibliothèque statique universelle (Apple silicon + Intel) et
# l'emballe en mac/Frameworks/BergamoteCoreFFI.xcframework, que le package Swift utilise.
#
#   mac/scripts/build-core.sh
#
# Prérequis : rustup avec les cibles aarch64-apple-darwin et x86_64-apple-darwin.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE="$ROOT/core"
OUT="$ROOT/mac/Frameworks/BergamoteCoreFFI.xcframework"
WORK="$CORE/target/xcframework"

# Même version minimale que l'app : pas d'avertissement de l'éditeur de liens.
export MACOSX_DEPLOYMENT_TARGET=14.0
cargo build --manifest-path "$CORE/Cargo.toml" --release \
  --target aarch64-apple-darwin --target x86_64-apple-darwin

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/include"
lipo -create \
  "$CORE/target/aarch64-apple-darwin/release/libbergamote_core.a" \
  "$CORE/target/x86_64-apple-darwin/release/libbergamote_core.a" \
  -output "$WORK/libbergamote_core.a"
cp "$CORE/include/bergamote_core.h" "$CORE/include/module.modulemap" "$WORK/include/"
xcodebuild -create-xcframework -library "$WORK/libbergamote_core.a" -headers "$WORK/include" -output "$OUT" >/dev/null
echo "OK : $OUT ($(lipo -archs "$WORK/libbergamote_core.a"))"
