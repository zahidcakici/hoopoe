#!/bin/bash
# Builds dist/Hoopoe.app from the Swift package. Run scripts/package.sh afterwards for a DMG and zip.
#
#   VERSION=1.2.3        version written to Info.plist (default 0.0.0)
#   BUILD_NUMBER=42      build number (default 1)
#   UNIVERSAL=1          build for arm64 + x86_64 (needs full Xcode)
#   SIGN_IDENTITY="..."  codesign identity (default "-", ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
IDENTITY="${SIGN_IDENTITY:--}"
APP="dist/Hoopoe.app"

arch_flags=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    arch_flags=(--arch arm64 --arch x86_64)
fi

swift build -c release ${arch_flags[@]+"${arch_flags[@]}"}
bin_dir="$(swift build -c release ${arch_flags[@]+"${arch_flags[@]}"} --show-bin-path)"

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$bin_dir/Hoopoe" "$APP/Contents/MacOS/Hoopoe"
strip -x "$APP/Contents/MacOS/Hoopoe"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

sign() {
    if [[ "$IDENTITY" == "-" ]]; then
        codesign --force --sign - "$1"
    else
        # Hardened runtime and a secure timestamp are required for notarization.
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$1"
    fi
}
sign "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
