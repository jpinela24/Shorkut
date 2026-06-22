import AppKit

/// Watches keyDown events (observation only, no Accessibility permission needed)
/// to dispatch shortcuts assigned a hotkey, and to support recording a new one.
final class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()

    private static let enabledDefaultsKey = "ShorkutHotkeysEnabled"

    @Published var recordingShortcutId: UUID?
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: HotKeyManager.enabledDefaultsKey)
            if isEnabled {
                startDispatching()
            } else {
                stopDispatching()
            }
        }
    }

    private var dispatchGlobalMonitor: Any?
    private var dispatchLocalMonitor: Any?
    private var recorderLocalMonitor: Any?

    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    private init() {
        // Off by default: watching every keystroke system-wide isn't worth the
        // resource/privacy cost unless the user actually wants hotkeys.
        isEnabled = UserDefaults.standard.bool(forKey: HotKeyManager.enabledDefaultsKey)
    }

    /// Call once at launch to honor the persisted toggle. Does nothing if disabled.
    func startIfEnabled() {
        if isEnabled {
            startDispatching()
        }
    }

    private func startDispatching() {
        guard dispatchGlobalMonitor == nil else { return }
        dispatchGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleDispatchEvent(event)
        }
        dispatchLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleDispatchEvent(event)
            return event
        }
    }

    private func stopDispatching() {
        if let monitor = dispatchGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            dispatchGlobalMonitor = nil
        }
        if let monitor = dispatchLocalMonitor {
            NSEvent.removeMonitor(monitor)
            dispatchLocalMonitor = nil
        }
    }

    private func handleDispatchEvent(_ event: NSEvent) {
        guard recordingShortcutId == nil else { return }
        let modifiers = event.modifierFlags.intersection(HotKeyManager.relevantModifiers).rawValue
        guard modifiers != 0 else { return }
        let keyCode = event.keyCode

        if let match = ShortcutStore.shared.shortcuts.first(where: { $0.hotKeyCode == keyCode && $0.hotKeyModifiers == modifiers }) {
            ShortcutStore.shared.run(match)
        }
    }

    func startRecording(for shortcutId: UUID) {
        recordingShortcutId = shortcutId
        recorderLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.captureRecordedKey(event)
            return nil
        }
    }

    func cancelRecording() {
        recordingShortcutId = nil
        if let monitor = recorderLocalMonitor {
            NSEvent.removeMonitor(monitor)
            recorderLocalMonitor = nil
        }
    }

    private func captureRecordedKey(_ event: NSEvent) {
        guard let shortcutId = recordingShortcutId else { return }
        let modifiers = event.modifierFlags.intersection(HotKeyManager.relevantModifiers).rawValue

        guard modifiers != 0, event.keyCode != 53 else { // 53 = Escape, used to cancel
            cancelRecording()
            return
        }

        ShortcutStore.shared.setHotKey(for: shortcutId, keyCode: event.keyCode, modifiers: modifiers)
        cancelRecording()
    }

    /// Human-readable form like "⌃⌥R" for display in Settings.
    static func displayString(keyCode: UInt16, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += keyName(for: keyCode)
        return result
    }

    private static func keyName(for keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 32: "U", 34: "I", 31: "O",
            35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            36: "↩", 49: "Space", 51: "⌫", 48: "⇥", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}
