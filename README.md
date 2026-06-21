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
  - **Scripts** — any shell script, run through your preferred terminal app (Terminal, iTerm, Warp, Alacritty, kitty, Hyper).
  - **Apps** — launch any installed app with one click.
  - **Webpages** — open a URL in your default or a specific browser.
- **Drag-and-drop everything** — drop a `.sh` script, an `.app`, or a `.shorkut` file straight onto the tile or Settings to add it. Drag shortcuts and whole sections to reorder them.
- **Customize** — pick a custom icon and color per shortcut, assign a global hotkey, rename anything.
- **Export/import** — share shortcuts with friends as portable `.shorkut` files.
- **Template generator** — quickly build common shortcuts (SSH, curl, Docker, restart a service) from a form instead of writing a script by hand.
- **Launch at login**, run notifications, and other small conveniences that make it feel like a normal Mac app.

## Building

Requires Xcode Command Line Tools (Swift 5.10+, macOS 13 SDK or later).

```bash
git clone https://github.com/jpinela24/Shorkut.git
cd Shorkut
./build.sh              # fast dev build, native arch only, installs to /Applications
./build.sh --universal  # universal binary (Apple Silicon + Intel) for distribution
./make_dmg.sh           # packages the installed app into build/Shorkut.dmg
```

## Project layout

- `Sources/Shorkut/` — all app source (SwiftUI + AppKit).
- `assets/` — logo source files used to generate the app icon and menu bar glyph.
- `build.sh` — compiles, signs, and installs the app.
- `make_dmg.sh` — packages a drag-to-Applications `.dmg`.
- `make-shorkut.sh` — CLI helper to package a bash script into a `.shorkut` file without using the app UI.

## Notes

- The app is ad-hoc signed (not notarized), so a fresh install on another Mac will need a right-click → Open the first time, or an approval in System Settings → Privacy & Security.
- Global hotkeys require granting Input Monitoring permission for true system-wide dispatch.

## Author

Made by [jpinela24](https://github.com/jpinela24).
