#!/bin/zsh
# Builds a distributable Nova: universal (arm64 + x86_64) when possible,
# ad-hoc signed, packaged as a zip and a DMG with checksums.
#
# No Apple Developer ID is configured, so the build is not notarized:
# on other Macs, open it with right-click → Open the first time.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
OUT="build/release"
rm -rf "$OUT"
mkdir -p "$OUT"

if UNIVERSAL=1 scripts/build_app.sh release; then
  echo "Universal build OK"
else
  echo "Universal build failed; building for this Mac's architecture only"
  scripts/build_app.sh release
fi

APP="build/Nova.app"
codesign --verify --deep --strict "$APP"
echo "Signature verified"

ZIP="$OUT/Nova-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/Nova-$VERSION.dmg"
hdiutil create -quiet -volname "Nova $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

(cd "$OUT" && shasum -a 256 Nova-"$VERSION".* > SHA256SUMS.txt)
echo
echo "Release artifacts:"
ls -lh "$OUT"
cat "$OUT/SHA256SUMS.txt"
