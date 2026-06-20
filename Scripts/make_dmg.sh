#!/usr/bin/env bash
#
# Package dist/Moonly.app into a distributable dist/Moonly.dmg and print its
# sha256 (paste into Casks/moonly.rb). Run build_app.sh first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Moonly.app"
DMG="$ROOT/dist/Moonly.dmg"

[ -d "$APP" ] || { echo "Build first: Scripts/build_app.sh"; exit 1; }

rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Moonly" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "Created $DMG"
echo "version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
echo "sha256:  $(shasum -a 256 "$DMG" | awk '{print $1}')"
