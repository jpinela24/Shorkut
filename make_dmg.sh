#!/bin/bash
# Packages Shorkut.app into a drag-to-Applications .dmg for distribution.
set -e
cd "$(dirname "$0")"

APP_NAME="Shorkut"
SOURCE_APP="/Applications/$APP_NAME.app"
DMG_STAGING="build/dmg-staging"
DMG_OUT="build/$APP_NAME.dmg"

if [ ! -d "$SOURCE_APP" ]; then
    echo "error: $SOURCE_APP not found. Run ./build.sh --universal first." >&2
    exit 1
fi

echo "Verifying universal binary..."
if ! lipo -info "$SOURCE_APP/Contents/MacOS/$APP_NAME" 2>/dev/null | grep -q "x86_64" ; then
    echo "warning: $SOURCE_APP is not a universal binary. Run ./build.sh --universal before packaging." >&2
fi

rm -rf "$DMG_STAGING" "$DMG_OUT"
mkdir -p "$DMG_STAGING"

echo "Staging app + Applications shortcut..."
cp -R "$SOURCE_APP" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

echo "Building $DMG_OUT..."
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_OUT" >/dev/null

rm -rf "$DMG_STAGING"

echo "Done: $DMG_OUT"
open -R "$DMG_OUT"
