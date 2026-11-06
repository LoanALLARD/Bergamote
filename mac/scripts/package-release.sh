#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) Bergamote.app and zips it for GitHub Releases.
#
#   scripts/package-release.sh            # build/Bergamote-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Packaging/Info.plist)
SWIFT_BUILD_FLAGS="--arch arm64 --arch x86_64" scripts/make-app.sh

ARCHIVE="build/Bergamote-$VERSION.zip"
rm -f "$ARCHIVE"
# ditto keeps the bundle's signature and extended attributes intact.
ditto -c -k --sequesterRsrc --keepParent build/Bergamote.app "$ARCHIVE"
echo "Architectures: $(lipo -archs build/Bergamote.app/Contents/MacOS/Bergamote)"
echo "SHA-256: $(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
echo "OK: $ARCHIVE"
