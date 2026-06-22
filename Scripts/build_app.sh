#!/usr/bin/env bash
#
# Build Moonly.app from the SwiftPM package.
#
# Must run on macOS with the Swift 6.1+ toolchain (Xcode CLT). SwiftPM produces
# a bare executable, so we hand-assemble the .app bundle around it: the menu-bar
# behaviour comes entirely from Info.plist (LSUIElement) and the bundled
# fetch_model.sh, which the cask's postflight uses to pre-download the model.
#
# LlamaKit links llama.cpp as a dynamic framework (llama.framework), so we embed
# it under Contents/Frameworks and add the matching rpath.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Moonly.app"

echo "==> swift build -c release"
swift build -c release --package-path "$ROOT"
BIN="$ROOT/.build/release/moonly"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/moonly"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Scripts/fetch_model.sh" "$APP/Contents/Resources/fetch_model.sh"
chmod +x "$APP/Contents/Resources/fetch_model.sh"
[ -f "$ROOT/Packaging/AppIcon.icns" ] && cp "$ROOT/Packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Embed the llama.cpp dynamic framework that LlamaKit links against, and point
# the executable at it via an rpath. The binary is built with an `@rpath/
# llama.framework/...` install name, so Contents/Frameworks + this rpath is all
# it needs to find the library at runtime.
FRAMEWORK="$ROOT/.build/release/llama.framework"
if [ -d "$FRAMEWORK" ]; then
    cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/llama.framework"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/moonly" 2>/dev/null || true
else
    echo "warning: llama.framework not found in .build/release — the app won't launch without it."
fi

# Sign with sandbox entitlements + hardened runtime.
# Replace `-` with a Developer ID identity for notarized distribution.
ENTITLEMENTS="$ROOT/Packaging/Moonly.entitlements"
echo "==> codesign (ad-hoc, sandboxed)"
codesign --force --deep --sign - \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    "$APP" || echo "warning: codesign failed (ok for local testing)"

echo "Built $APP"
