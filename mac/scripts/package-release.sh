#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) Bergamote.app and packages it for GitHub Releases:
# a disk image to install from (drag the app onto Applications) and a plain zip.
#
#   scripts/package-release.sh            # build/Bergamote-<version>.dmg and .zip
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Packaging/Info.plist)
ARCHS="arm64 x86_64" scripts/make-app.sh

ARCHIVE="build/Bergamote-$VERSION.zip"
rm -f "$ARCHIVE"
# ditto keeps the bundle's signature and extended attributes intact.
ditto -c -k --sequesterRsrc --keepParent build/Bergamote.app "$ARCHIVE"

# Disk image: the app next to a shortcut to Applications.
IMAGE="build/Bergamote-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto build/Bergamote.app "$STAGE/Bergamote.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$IMAGE"
hdiutil create -volname "Bergamote" -srcfolder "$STAGE" -format UDZO -ov "$IMAGE" >/dev/null

echo "Architectures: $(lipo -archs build/Bergamote.app/Contents/MacOS/Bergamote)"
echo "SHA-256: $(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
echo "OK: $ARCHIVE"
echo "OK: $IMAGE"
