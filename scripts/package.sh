#!/bin/bash
# Packages dist/Hoopoe.app into dist/Hoopoe-<version>.zip (used by the in-app updater)
# and dist/Hoopoe-<version>.dmg (for first-time installs).
#
#   SIGN_IDENTITY="..."  also sign the DMG (default "-", unsigned DMG)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Hoopoe.app"
IDENTITY="${SIGN_IDENTITY:--}"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"

zip="dist/Hoopoe-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$APP" "$zip"
echo "Built $zip"

staging="$(mktemp -d)"
cp -R "$APP" "$staging/"
ln -s /Applications "$staging/Applications"
dmg="dist/Hoopoe-$version.dmg"
hdiutil create -volname "Hoopoe" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$staging"
if [[ "$IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$dmg"
fi
echo "Built $dmg"
