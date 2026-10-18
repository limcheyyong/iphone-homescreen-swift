#!/bin/bash
# Builds a universal (Apple silicon + Intel) app bundle and a DMG:  dist/Homescreen Organizer.app, dist/Homescreen-mac.dmg
# Works with just the Command Line Tools; full Xcode is not needed.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
NAME="Homescreen Organizer"
APP="dist/$NAME.app"

BUILD=(swift build -c release --arch arm64 --arch x86_64)
"${BUILD[@]}"
BIN="$("${BUILD[@]}" --show-bin-path)/Homescreen"

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Homescreen"
[ "$(lipo -archs "$APP/Contents/MacOS/Homescreen")" = "x86_64 arm64" ] || { echo "not a universal binary"; exit 1; }
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/bmc-button.png "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"  # English (default) and Traditional Chinese

# App icon: every size macOS asks for, from the 1024px master
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) Resources/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: required to run on Apple silicon. Without a paid Developer ID, macOS still asks users to confirm once.
codesign --force --sign - --timestamp=none "$APP"

# DMG with the usual drag-to-Applications layout
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov dist/Homescreen-mac.dmg >/dev/null

ls -lh dist/Homescreen-mac.dmg
