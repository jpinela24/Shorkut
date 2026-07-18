import SwiftUI
import AppKit
import Combine
// Flat build.sh compile has no module boundary; SPM (swift test) needs the import.
#if canImport(ShorkutCore)
import ShorkutCore
#endif

private let menuBarIcon: NSImage = {
    if let path = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
       let image = NSImage(contentsOfFile: path) {
        image.size = NSSize(width: 15, height: 15)
        image.isTemplate = true
        return image
    }
    return NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) ?? NSImage()
}()

final class WidgetState: ObservableObject {
    @Published var isLocked: Bool = DesktopTileWindow.isLocked
}

@main
struct ShorkutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = WidgetState()
    @StateObject private var store = ShortcutStore.shared

    var body: some Scene {
        MenuBarExtra {
            Button("Settings…") {
                appDelegate.showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Toggle("Lock tile position", isOn: Binding(
                get: { state.isLocked },
                set: { newValue in
                    state.isLocked = newValue
                    appDelegate.tileWindows.forEach { $0.setLocked(newValue) }
                }
            ))

            Button("Add Another Tile") {
                ShortcutStore.shared.addTile()
            }

            Divider()

            Button("Restart Shorkut") {
                appDelegate.restartApp()
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(nsImage: menuBarIcon)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var tileWindows: [DesktopTileWindow] = []
    private var tilesCancellable: AnyCancellable?
    var templateWindow: TemplateGeneratorWindow?
    var settingsWindow: SettingsWindow?
    var scriptEditorWindow: ScriptEditorWindow?
    var customizeWindow: CustomizeShortcutWindow?
    var onboardingWindow: OnboardingWindow?

    func showCustomizeShortcut(for shortcut: ScriptShortcut) {
        let window = CustomizeShortcutWindow(store: ShortcutStore.shared, shortcut: shortcut)
        customizeWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showTemplateGenerator(sectionId: UUID?) {
        let window = TemplateGeneratorWindow(store: ShortcutStore.shared, sectionId: sectionId)
        templateWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showScriptEditor(for shortcut: ScriptShortcut) {
        let window = ScriptEditorWindow(store: ShortcutStore.shared, shortcut: shortcut)
        scriptEditorWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
        } else {
            let window = SettingsWindow(store: ShortcutStore.shared, appDelegate: self)
            settingsWindow = window
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Keeps actual NSWindow instances in sync with `store.tiles` — the array
    /// is the single source of truth (configurable from Settings > Tiles or the
    /// tile's own right-click menu); this just reacts to it.
    private func syncTileWindows(to tiles: [TileConfig]) {
        let desiredIds = Set(tiles.map { $0.id })
        let removed = tileWindows.filter { !desiredIds.contains($0.id) }
        removed.forEach { window in
            window.close()
            DesktopTileWindow.removeSavedOrigin(for: window.id)
        }
        tileWindows.removeAll { !desiredIds.contains($0.id) }

        let existingIds = Set(tileWindows.map { $0.id })
        for tile in tiles where !existingIds.contains(tile.id) {
            let window = DesktopTileWindow(store: ShortcutStore.shared, id: tile.id)
            window.orderFrontRegardless()
            tileWindows.append(window)
        }
    }

    /// Re-lays out every tile in a cascade near the top-left of the main screen,
    /// clearing any stale/off-screen saved positions. Surfaced in Settings > Tiles.
    func resetTilePositions() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        for (index, window) in tileWindows.enumerated() {
            let step = CGFloat(index) * 44
            let x = vf.minX + 24 + step
            let y = vf.maxY - window.frame.height - 24 - step
            window.reposition(to: DesktopTileWindow.onScreenOrigin(for: NSPoint(x: x, y: y), size: window.frame.size, on: screen))
        }
    }

    /// `launcher` is injectable so the relaunch handshake can be driven in tests
    /// without actually spawning a process. It must call its completion with the
    /// launched app (or nil) and any error — exactly like NSWorkspace.
    func restartApp(
        launcher: ((@escaping (NSRunningApplication?, Error?) -> Void) -> Void)? = nil
    ) {
        let launch = launcher ?? { completion in
            let appURL = Bundle.main.bundleURL
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            config.environment = ["SHORKUT_RESTART": "1"]
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: completion)
        }

        launch { app, error in
            DispatchQueue.main.async {
                switch AppRestart.outcome(launchedAppExists: app != nil, error: error) {
                case .relaunchedTerminateSelf:
                    NSApplication.shared.terminate(nil)
                case .failedKeepRunning:
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Couldn't restart Shorkut"
                    alert.informativeText = (error?.localizedDescription).map { "\($0)\n\n" } ?? ""
                    alert.informativeText += "The current Shorkut is still running. Quit and reopen it manually if needed."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["SHORKUT_RESTART"] != "1",
           let bundleId = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let other = others.first {
                other.activate()
                NSApplication.shared.terminate(nil)
                return
            }
        }

        DesktopIconGrid.refreshFromFinderIfNeeded()

        let store = ShortcutStore.shared
        store.adoptFinderGridIfNotCustomized()
        syncTileWindows(to: store.tiles)
        tileWindows.first?.playFirstLaunchAnimationIfNeeded()
        tilesCancellable = store.$tiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tiles in
                self?.syncTileWindows(to: tiles)
            }

        // Rescue tiles onto a visible screen whenever the display layout changes
        // (monitor plugged/unplugged, resolution or arrangement change).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tileWindows.forEach { $0.ensureOnScreen() }
        }

        NotificationManager.shared.requestAuthorization()
        UpdateChecker.shared.checkForUpdatesIfDue()

        if !OnboardingWindow.hasBeenShown {
            let onboarding = OnboardingWindow(appDelegate: self)
            onboardingWindow = onboarding
            onboarding.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            ShortcutStore.shared.importShortcuts(from: url)
        }
    }
}
