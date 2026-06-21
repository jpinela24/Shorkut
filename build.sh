#!/bin/bash
set -e
cd "$(dirname "$0")"

APP_NAME="Shorkut"
INSTALL_DIR="/Applications"
APP="build/$APP_NAME.app"
LAUNCH_AGENT_LABEL="com.local.shorkut"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

FRAMEWORKS="-framework SwiftUI -framework AppKit -framework ServiceManagement -framework UserNotifications"

if [ "$1" = "--universal" ]; then
    echo "Compiling (arm64)..."
    swiftc -target arm64-apple-macosx13.0 Sources/Shorkut/*.swift -O -o "build/${APP_NAME}-arm64" $FRAMEWORKS
    echo "Compiling (x86_64)..."
    swiftc -target x86_64-apple-macosx13.0 Sources/Shorkut/*.swift -O -o "build/${APP_NAME}-x86_64" $FRAMEWORKS
    echo "Combining into universal binary..."
    lipo -create "build/${APP_NAME}-arm64" "build/${APP_NAME}-x86_64" -output "$APP/Contents/MacOS/$APP_NAME"
    rm -f "build/${APP_NAME}-arm64" "build/${APP_NAME}-x86_64"
else
    echo "Compiling (native arch only — use ./build.sh --universal for distribution)..."
    swiftc Sources/Shorkut/*.swift -O -o "$APP/Contents/MacOS/$APP_NAME" $FRAMEWORKS
fi

echo "Generating app icon..."
ICONSET="build/$APP_NAME.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
if [ -f "assets/logo.png" ]; then
    LOGO_SOURCE="assets/logo.png"
else
    LOGO_SOURCE="$HOME/Desktop/ShorKut/shorkut icon logo.png"
fi
if [ -f "$LOGO_SOURCE" ]; then
    for size in 16 32 64 128 256 512 1024; do
        sips -z "$size" "$size" "$LOGO_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        if [ "$size" -le 512 ]; then
            doubled=$((size * 2))
            sips -z "$doubled" "$doubled" "$LOGO_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
        fi
    done
else
    swiftc make_icon.swift -O -o build/make_icon -framework AppKit
    ./build/make_icon "$ICONSET"
fi
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

if [ -f "$LOGO_SOURCE" ]; then
    cp "$LOGO_SOURCE" "$APP/Contents/Resources/Logo.png"

    echo "Generating menu bar icon from logo silhouette..."
    swiftc make_template_icon.swift -O -o build/make_template_icon -framework AppKit
    if [ -f "assets/logo_glyph_crop.png" ]; then
        GLYPH_SOURCE="assets/logo_glyph_crop.png"
    else
        GLYPH_SOURCE="logo_glyph_crop.png"
    fi
    if [ -f "$GLYPH_SOURCE" ]; then
        ./build/make_template_icon "$GLYPH_SOURCE" "$APP/Contents/Resources/MenuBarIcon.png" 64
    else
        ./build/make_template_icon "$LOGO_SOURCE" "$APP/Contents/Resources/MenuBarIcon.png" 64
    fi
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$LAUNCH_AGENT_LABEL</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.local.shorkut.shorkut-file</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.json</string>
            </array>
            <key>UTTypeDescription</key>
            <string>Shorkut Shortcuts</string>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>shorkut</string>
                </array>
            </dict>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Shorkut Shortcuts</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.local.shorkut.shorkut-file</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "Signing..."
codesign --force --deep -s - "$APP"

echo "Installing to $INSTALL_DIR..."
if pgrep -x "$APP_NAME" >/dev/null; then
    killall "$APP_NAME" || true
    sleep 0.5
fi
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP" "$INSTALL_DIR/"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
rm -rf "$APP"

# Login-at-startup is now managed in-app via SMAppService (see Settings > General).
# Remove any legacy LaunchAgent from earlier builds so it doesn't double-launch the app.
if [ -f "$LAUNCH_AGENT_PLIST" ]; then
    launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
    rm -f "$LAUNCH_AGENT_PLIST"
fi

echo "Done. Launching..."
open "$INSTALLED_APP"
