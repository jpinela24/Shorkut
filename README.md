<p align="center">
  <img src="assets/logo.png" alt="Shorkut logo" width="160">
</p>

# Shorkut

A native macOS menu-bar app and desktop widget for one-click shortcuts — scripts, apps, and webpages, all in one place.

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)

## Features

- **Desktop tile widget** — a floating, resizable tile on your desktop showing your shortcuts, grouped into collapsible sections, with optional multi-column layout.
- **Menu bar app** — quick access to Settings, lock the tile's position, restart, or quit.
- **Three kinds of shortcuts**:
  - **Scripts** — any shell script, run through your preferred terminal app (Terminal, iTerm, Alacritty, or kitty — the terminals Shorkut can reliably execute a command in).
  - **Apps** — launch any installed app with one click.
  - **Webpages** — open a URL in your default or a specific browser.
- **Drag-and-drop everything** — drop a `.sh` script, an `.app`, or a `.shorkut` file straight onto the tile or Settings to add it. Drag shortcuts and whole sections to reorder them.
- **Customize** — pick a custom icon and color per shortcut, rename anything.
- **Export/import** — share shortcuts with friends as portable `.shorkut` files.
- **Template generator** — quickly build common shortcuts (SSH, curl, Docker, restart a service) from a form instead of writing a script by hand.
- **Launch at login**, run notifications, and other small conveniences that make it feel like a normal Mac app.

> **First launch on a new Mac:** Shorkut isn't notarized, so macOS will say it's from an unidentified developer. Right-click (or Control-click) the app → **Open** → **Open** again in the dialog — you only need to do this once.

## Building

Requires Xcode Command Line Tools (Swift 5.10+, macOS 13 SDK or later).

`build.sh` has explicit subcommands so a build can't silently overwrite your installed app or mislabel a version:

```bash
git clone https://github.com/jpinela24/Shorkut.git
cd Shorkut
./build.sh                 # (default "dev") native build, install to /Applications, launch
./build.sh build           # compile the .app into ./build only — never touches /Applications
./build.sh release         # distribution build; REQUIRES an exact version (see below)
./build.sh install         # copy ./build/Shorkut.app to /Applications
./build.sh launch          # open the installed app
./build.sh build --universal   # fat binary (Apple Silicon + Intel)
./make_dmg.sh              # packages the installed app into build/Shorkut.dmg
```

**Versioning.** A `release` build refuses to run unless it can resolve an exact version — either an exact `vX.Y.Z` git tag on `HEAD`, or `SHORKUT_VERSION=X.Y.Z`. It will not label an arbitrary post-tag commit with the latest tag's number. `dev`/`build` fall back to an unmistakable `0.0.0-dev+<sha>` string. `CFBundleVersion` is the monotonic commit count, and the generated `Info.plist` is `plutil`-linted before signing.

## Testing

```bash
swift test          # all ShorkutCore unit tests
swift build -c release   # production type-check/build of the full app target
```

CI (`.github/workflows/ci.yml`) runs `swift test`, the release build, and shell checks on every push/PR.

## Project layout

- `Sources/Shorkut/` — app source (SwiftUI + AppKit): windows, tile, store wiring.
- `Sources/ShorkutCore/` — Foundation-only, unit-tested business logic: terminal-launch planning, managed-script deletion, safe file import, `.shorkut` validation, persistence + migration, update-version checking. No AppKit, so it's testable in isolation.
- `Tests/ShorkutCoreTests/` — the test suite for the above.
- `assets/` — logo source files used to generate the app icon and menu bar glyph.
- `build.sh` — compiles, signs, and (for `dev`/`install`) installs the app.
- `make_dmg.sh` — packages a drag-to-Applications `.dmg`.
- `make-shorkut.sh` — CLI helper to package a bash script into a `.shorkut` file without using the app UI.

## Notes

- The app is ad-hoc signed (not notarized), so a fresh install on another Mac will need a right-click → Open the first time, or an approval in System Settings → Privacy & Security.

## Security model

Shorkut runs scripts you point it at, so the trust boundary matters. What it does and doesn't protect:

- **Scripts run with your full user permissions.** `.shorkut` files can bundle script source, app references, and webpage URLs. Imported/template-generated scripts run the moment you confirm them; Shorkut shows a one-time trust prompt before a newly-imported script's first run but does **not** sandbox or vet script *contents* beyond verifying it's plain text. Only import from sources you trust.
- **Command construction is injection-safe.** Script paths are single-quoted for the shell and escaped for AppleScript (Terminal/iTerm), or passed as an argv array (`open -n -a … --args`, for Alacritty/kitty) so a path with spaces, quotes, `$`, backticks, or `;` is never parsed as a command.
- **Deletion is confined to managed storage.** Removing a shortcut or section only deletes a regular file that resolves *inside* `~/Library/Application Support/Shorkut/Scripts`. Traversal (`..`), prefix-collision siblings, external paths, and symlinks pointing outside are refused — the record is dropped without deleting the target.
- **Imports fail closed.** A file whose size/type can't be read, or that isn't a plain regular file (folder, symlink, device), is rejected; the size limit is enforced *while* streaming, so an oversized or growing file can't slip through or exhaust memory. `.shorkut` files must declare the supported schema version and pass per-item length/kind validation before any state is changed.
- **Data is stored durably.** Sections/shortcuts/tiles live in an atomically-written `state.json` with a last-known-good `.bak`. On corruption Shorkut recovers from the backup, or preserves the unreadable file and tells you where it went — it never silently resets your data.
- **Update checks are validated.** The release check requires an HTTP 2xx response, parses versions strictly, ignores prereleases, and only opens an HTTPS `github.com` URL.

## Author

Made by [jpinela24](https://github.com/jpinela24).
