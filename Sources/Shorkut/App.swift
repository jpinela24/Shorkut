import SwiftUI
import AppKit

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
                    appDelegate.tileWindow?.setLocked(newValue)
                }
            ))

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
    var tileWindow: DesktopTileWindow?
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

    func restartApp() {
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.environment = ["SHORKUT_RESTART": "1"]
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
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

        let window = DesktopTileWindow(store: ShortcutStore.shared)
        window.orderFrontRegardless()
        window.playFirstLaunchAnimationIfNeeded()
        tileWindow = window

        HotKeyManager.shared.startIfEnabled()
        NotificationManager.shared.requestAuthorization()

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
