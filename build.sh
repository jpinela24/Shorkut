#!/bin/bash
#
# Shorkut build script.
#
# Subcommands (first argument):
#   dev       (default) native build, install to /Applications, launch. For
#             day-to-day development. Version is a clearly-marked dev string.
#   build     compile the app bundle into ./build only — never touches
#             /Applications. Add --universal for a fat binary.
#   release   distribution build. REQUIRES an exact version (a `vX.Y.Z` git tag
#             on HEAD, or SHORKUT_VERSION=X.Y.Z). Universal, validated, NOT
#             auto-installed.
#   install   copy the already-built ./build/Shorkut.app to /Applications.
#   launch    open the installed app.
#
# Version resolution:
#   SHORKUT_VERSION env wins; otherwise an exact tag on HEAD (git describe
#   --exact-match). `release` fails if neither yields a valid X.Y.Z — it will
#   NOT label an arbitrary post-tag commit with the latest tag's number.
#   `dev`/`build` fall back to a "0.0.0-dev+<sha>" string that can never be
#   mistaken for a real release.
#
# CFBundleVersion is the total commit count (monotonically increasing).
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Shorkut"
INSTALL_DIR="/Applications"
APP="build/$APP_NAME.app"
LAUNCH_AGENT_LABEL="com.local.shorkut"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"
FRAMEWORKS=(-framework SwiftUI -framework AppKit -framework ServiceManagement -framework UserNotifications)

SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'

is_valid_semver() { [[ "$1" =~ $SEMVER_RE ]]; }

# Exact tag on HEAD (empty if HEAD isn't tagged), with leading v stripped.
exact_tag_version() {
    git describe --tags --exact-match 2>/dev/null | sed 's/^v//' || true
}

short_sha() { git rev-parse --short HEAD 2>/dev/null || echo "nogit"; }

# Monotonic build number from commit count; 1 if git is unavailable.
bundle_version() { git rev-list --count HEAD 2>/dev/null || echo 1; }

# Resolves the marketing version for a given mode ("release" is strict).
resolve_version() {
    local mode="$1" v="${SHORKUT_VERSION:-}"
    if [ -z "$v" ]; then v="$(exact_tag_version)"; fi

    if [ "$mode" = "release" ]; then
        if [ -z "$v" ]; then
            echo "ERROR: release build needs an exact version. Tag HEAD with vX.Y.Z or set SHORKUT_VERSION=X.Y.Z." >&2
            exit 1
        fi
        if ! is_valid_semver "$v"; then
            echo "ERROR: version '$v' is not a valid X.Y.Z semantic version." >&2
            exit 1
        fi
        echo "$v"
        return
    fi

    # dev/build: use the exact tag if present and valid, else an unmistakable dev string.
    if [ -n "$v" ] && is_valid_semver "$v"; then echo "$v"; else echo "0.0.0-dev+$(short_sha)"; fi
}

compile() {
    local universal="$1"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    if [ "$universal" = "universal" ]; then
        echo "Compiling (arm64)..."
        swiftc -target arm64-apple-macosx13.0 Sources/Shorkut/*.swift Sources/ShorkutCore/*.swift -O -o "build/${APP_NAME}-arm64" "${FRAMEWORKS[@]}"
        echo "Compiling (x86_64)..."
        swiftc -target x86_64-apple-macosx13.0 Sources/Shorkut/*.swift Sources/ShorkutCore/*.swift -O -o "build/${APP_NAME}-x86_64" "${FRAMEWORKS[@]}"
        echo "Combining into universal binary..."
        lipo -create "build/${APP_NAME}-arm64" "build/${APP_NAME}-x86_64" -output "$APP/Contents/MacOS/$APP_NAME"
        rm -f "build/${APP_NAME}-arm64" "build/${APP_NAME}-x86_64"
    else
        echo "Compiling (native arch only — use 'release' or --universal for distribution)..."
        swiftc Sources/Shorkut/*.swift Sources/ShorkutCore/*.swift -O -o "$APP/Contents/MacOS/$APP_NAME" "${FRAMEWORKS[@]}"
    fi
}

make_icons() {
    echo "Generating app icon..."
    local ICONSET="build/$APP_NAME.iconset"
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    local LOGO_SOURCE="assets/logo.png"
    [ -f "$LOGO_SOURCE" ] || LOGO_SOURCE="$HOME/Desktop/ShorKut/shorkut icon logo.png"
    if [ -f "$LOGO_SOURCE" ]; then
        for size in 16 32 64 128 256 512 1024; do
            sips -z "$size" "$size" "$LOGO_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
            if [ "$size" -le 512 ]; then
                local doubled=$((size * 2))
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
        local GLYPH_SOURCE="assets/logo_glyph_crop.png"
        [ -f "$GLYPH_SOURCE" ] || GLYPH_SOURCE="logo_glyph_crop.png"
        [ -f "$GLYPH_SOURCE" ] || GLYPH_SOURCE="$LOGO_SOURCE"
        ./build/make_template_icon "$GLYPH_SOURCE" "$APP/Contents/Resources/MenuBarIcon.png" 64
    fi
}

write_plist() {
    local version="$1" build_num="$2"
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
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$build_num</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Shorkut runs your shortcut scripts by asking your chosen terminal app (Terminal or iTerm) to run them.</string>
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

    echo "Validating Info.plist..."
    plutil -lint "$APP/Contents/Info.plist" >/dev/null
    # Sanity-check the two version keys actually round-trip.
    local got_short got_build
    got_short="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
    got_build="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"
    [ "$got_short" = "$version" ] || { echo "ERROR: plist version mismatch ($got_short != $version)" >&2; exit 1; }
    [ "$got_build" = "$build_num" ] || { echo "ERROR: plist build mismatch ($got_build != $build_num)" >&2; exit 1; }
}

sign() {
    echo "Signing..."
    codesign --force --deep -s - "$APP"
}

install_app() {
    [ -d "$APP" ] || { echo "ERROR: $APP not found. Run '$0 build' first." >&2; exit 1; }
    echo "Installing to $INSTALL_DIR..."
    if pgrep -x "$APP_NAME" >/dev/null; then killall "$APP_NAME" || true; sleep 0.5; fi
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    cp -R "$APP" "$INSTALL_DIR/"
    # Remove any legacy LaunchAgent from earlier builds (login item is now SMAppService).
    if [ -f "$LAUNCH_AGENT_PLIST" ]; then
        launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
        rm -f "$LAUNCH_AGENT_PLIST"
    fi
}

launch_app() {
    echo "Launching..."
    open "$INSTALL_DIR/$APP_NAME.app"
}

build_bundle() {
    local mode="$1" universal="$2"
    local version build_num
    version="$(resolve_version "$mode")"
    build_num="$(bundle_version)"
    echo "Building $APP_NAME $version (build $build_num)"
    compile "$universal"
    make_icons
    write_plist "$version" "$build_num"
    sign
}

# ---- dispatch ----
CMD="${1:-dev}"
UNIVERSAL="native"
for arg in "$@"; do [ "$arg" = "--universal" ] && UNIVERSAL="universal"; done

case "$CMD" in
    dev|--universal)
        build_bundle dev "$UNIVERSAL"
        install_app
        launch_app
        echo "Done."
        ;;
    build)
        build_bundle build "$UNIVERSAL"
        echo "Done. Bundle at $APP (not installed)."
        ;;
    release)
        build_bundle release universal
        echo "Done. Release bundle at $APP (not installed). Use '$0 install' to install locally."
        ;;
    install)
        install_app
        ;;
    launch)
        launch_app
        ;;
    *)
        echo "Usage: $0 [dev|build|release|install|launch] [--universal]" >&2
        exit 1
        ;;
esac
