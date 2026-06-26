import Foundation
import AppKit
import UniformTypeIdentifiers
// build.sh compiles Sources/Shorkut and Sources/ShorkutCore together into one
// flat binary (no module boundary), so Sanitization is already in scope there.
// Under `swift build`/`swift test`, ShorkutCore is its own SPM module and
// needs an explicit import — canImport keeps both paths compiling.
#if canImport(ShorkutCore)
import ShorkutCore
#endif

extension UTType {
    static var shorkut: UTType {
        UTType(exportedAs: "com.local.shorkut.shorkut-file", conformingTo: .json)
    }

    /// Internal-only drag payload for reordering shortcuts/sections. Deliberately
    /// NOT plain text — Finder doesn't recognize this type, so dragging a
    /// shortcut/section out of the app and releasing on the Desktop is simply
    /// ignored instead of materializing a stray text-clipping/.inetloc file.
    static var shorkutDragPayload: UTType {
        UTType(exportedAs: "com.local.shorkut.drag-payload", conformingTo: .data)
    }
}

/// Builds a drag NSItemProvider that only Shorkut's own onDrop targets understand.
func shorkutDragProvider(_ payload: String) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: UTType.shorkutDragPayload.identifier, visibility: .all) { completion in
        completion(Data(payload.utf8), nil)
        return nil
    }
    return provider
}

/// Per-tile configuration: which desktop tile windows exist and what each shows.
/// `sectionIds == nil` means "mirror everything" (the default); a non-nil set
/// makes the tile independent, showing only those sections.
struct TileConfig: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var sectionIds: Set<UUID>?
}

/// Reads a drag payload produced by `shorkutDragProvider`, if present.
func loadShorkutDragPayload(from providers: [NSItemProvider], completion: @escaping (String) -> Void) {
    guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.shorkutDragPayload.identifier) }) else { return }
    provider.loadDataRepresentation(forTypeIdentifier: UTType.shorkutDragPayload.identifier) { data, _ in
        guard let data, let string = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { completion(string) }
    }
}

struct Section: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

enum ShortcutKind: String, Codable {
    case script
    case app
    case webpage
}

struct ScriptShortcut: Identifiable, Codable {
    let id: UUID
    var label: String
    var scriptPath: String
    var sectionId: UUID
    var kind: ShortcutKind
    var customIcon: String?
    var customColorHex: String?
    /// True for scripts whose content arrived via a .shorkut import (not chosen
    /// directly by the user via a file picker). Gates a one-time trust prompt.
    var needsTrustConfirmation: Bool = false

    init(id: UUID = UUID(), label: String, scriptPath: String, sectionId: UUID, kind: ShortcutKind = .script, customIcon: String? = nil, customColorHex: String? = nil, needsTrustConfirmation: Bool = false) {
        self.id = id
        self.label = label
        self.scriptPath = scriptPath
        self.sectionId = sectionId
        self.kind = kind
        self.customIcon = customIcon
        self.customColorHex = customColorHex
        self.needsTrustConfirmation = needsTrustConfirmation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        scriptPath = try container.decode(String.self, forKey: .scriptPath)
        sectionId = try container.decode(UUID.self, forKey: .sectionId)
        kind = try container.decodeIfPresent(ShortcutKind.self, forKey: .kind) ?? .script
        customIcon = try container.decodeIfPresent(String.self, forKey: .customIcon)
        customColorHex = try container.decodeIfPresent(String.self, forKey: .customColorHex)
        needsTrustConfirmation = try container.decodeIfPresent(Bool.self, forKey: .needsTrustConfirmation) ?? false
    }
}

/// Portable representation of a shortcut for sharing via .shorkut files.
/// Scripts carry their full content (not just a path) so they work on another machine.
struct ShorkutExport: Codable {
    struct Item: Codable {
        var label: String
        var kind: ShortcutKind
        var sectionName: String
        var scriptContent: String?      // for .script
        var bundleIdentifier: String?   // for .app
    }

    var version: Int = 1
    var items: [Item]
}

enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal = "com.apple.Terminal"
    case iterm = "com.googlecode.iterm2"
    case warp = "dev.warp.Warp-Stable"
    case alacritty = "org.alacritty"
    case kitty = "net.kovidgoyal.kitty"
    case hyper = "co.zeit.hyper"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm: return "iTerm"
        case .warp: return "Warp"
        case .alacritty: return "Alacritty"
        case .kitty: return "kitty"
        case .hyper: return "Hyper"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) != nil
    }

    static var installed: [TerminalApp] {
        allCases.filter { $0.isInstalled }
    }
}

enum BrowserApp: String, CaseIterable, Identifiable {
    case safari = "com.apple.Safari"
    case chrome = "com.google.Chrome"
    case firefox = "org.mozilla.firefox"
    case edge = "com.microsoft.edgemac"
    case brave = "com.brave.Browser"
    case arc = "company.thebrowser.Browser"
    case opera = "com.operasoftware.Opera"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .firefox: return "Firefox"
        case .edge: return "Edge"
        case .brave: return "Brave"
        case .arc: return "Arc"
        case .opera: return "Opera"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) != nil
    }

    static var installed: [BrowserApp] {
        allCases.filter { $0.isInstalled }
    }
}

final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()
    static let generalSectionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Published var sections: [Section] = [Section(id: generalSectionID, name: "General")]
    @Published var shortcuts: [ScriptShortcut] = []
    @Published var preferredTerminal: TerminalApp
    @Published var preferredBrowser: BrowserApp?
    @Published var collapsedSectionIds: Set<UUID> = []
    @Published var tileWidthScale: Int = 1
    @Published var autoResizeTile: Bool = true
    @Published var tiles: [TileConfig] = [TileConfig(id: DesktopTileWindow.primaryTileId, name: "Tile 1", sectionIds: nil)]

    private static let sectionsDefaultsKey = "ShorkutSections"
    private static let shortcutsDefaultsKey = "ShorkutScriptShortcuts"
    private static let preferredTerminalDefaultsKey = "ShorkutPreferredTerminal"
    private static let preferredBrowserDefaultsKey = "ShorkutPreferredBrowser"
    private static let collapsedSectionsDefaultsKey = "ShorkutCollapsedSections"
    private static let tileWidthScaleDefaultsKey = "ShorkutTileWidthScale"
    private static let autoResizeTileDefaultsKey = "ShorkutAutoResizeTile"
    private static let tilesDefaultsKey = "ShorkutTiles"
    /// Legacy key from before per-tile config existed — just a flat list of tile
    /// ids with no per-tile settings. Migrated into `tiles` on first load.
    private static let legacyTileIdsDefaultsKey = "ShorkutTileIds"

    private static var scriptsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shorkut/Scripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: ShortcutStore.preferredTerminalDefaultsKey),
           let app = TerminalApp(rawValue: saved), app.isInstalled {
            preferredTerminal = app
        } else {
            preferredTerminal = TerminalApp.installed.first ?? .terminal
        }
        if let saved = UserDefaults.standard.string(forKey: ShortcutStore.preferredBrowserDefaultsKey),
           let browser = BrowserApp(rawValue: saved), browser.isInstalled {
            preferredBrowser = browser
        } else {
            preferredBrowser = nil
        }
        let savedScale = UserDefaults.standard.integer(forKey: ShortcutStore.tileWidthScaleDefaultsKey)
        tileWidthScale = (1...3).contains(savedScale) ? savedScale : 1
        if UserDefaults.standard.object(forKey: ShortcutStore.autoResizeTileDefaultsKey) != nil {
            autoResizeTile = UserDefaults.standard.bool(forKey: ShortcutStore.autoResizeTileDefaultsKey)
        }
        load()
    }

    func setPreferredTerminal(_ app: TerminalApp) {
        preferredTerminal = app
        UserDefaults.standard.set(app.rawValue, forKey: ShortcutStore.preferredTerminalDefaultsKey)
    }

    func setTileWidthScale(_ scale: Int) {
        tileWidthScale = scale
        UserDefaults.standard.set(scale, forKey: ShortcutStore.tileWidthScaleDefaultsKey)
    }

    func setAutoResizeTile(_ enabled: Bool) {
        autoResizeTile = enabled
        UserDefaults.standard.set(enabled, forKey: ShortcutStore.autoResizeTileDefaultsKey)
    }

    func setPreferredBrowser(_ app: BrowserApp?) {
        preferredBrowser = app
        if let app {
            UserDefaults.standard.set(app.rawValue, forKey: ShortcutStore.preferredBrowserDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ShortcutStore.preferredBrowserDefaultsKey)
        }
    }

    func toggleSectionCollapsed(_ sectionId: UUID) {
        if collapsedSectionIds.contains(sectionId) {
            collapsedSectionIds.remove(sectionId)
        } else {
            collapsedSectionIds.insert(sectionId)
        }
        UserDefaults.standard.set(collapsedSectionIds.map { $0.uuidString }, forKey: ShortcutStore.collapsedSectionsDefaultsKey)
    }

    var groupedShortcuts: [(section: Section, shortcuts: [ScriptShortcut])] {
        sections.map { section in
            (section, shortcuts.filter { $0.sectionId == section.id })
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: ShortcutStore.sectionsDefaultsKey),
           let decoded = try? JSONDecoder().decode([Section].self, from: data),
           !decoded.isEmpty {
            sections = decoded
        }
        if let data = UserDefaults.standard.data(forKey: ShortcutStore.shortcutsDefaultsKey),
           let decoded = try? JSONDecoder().decode([ScriptShortcut].self, from: data) {
            shortcuts = decoded
        }
        if let strings = UserDefaults.standard.stringArray(forKey: ShortcutStore.collapsedSectionsDefaultsKey) {
            collapsedSectionIds = Set(strings.compactMap { UUID(uuidString: $0) })
        }
        if let data = UserDefaults.standard.data(forKey: ShortcutStore.tilesDefaultsKey),
           let decoded = try? JSONDecoder().decode([TileConfig].self, from: data),
           !decoded.isEmpty {
            tiles = decoded
        } else if let legacyIds = UserDefaults.standard.stringArray(forKey: ShortcutStore.legacyTileIdsDefaultsKey),
                  !legacyIds.isEmpty {
            // Migrate from the pre-TileConfig flat id list (no per-tile settings existed yet).
            tiles = legacyIds.enumerated().map { index, id in
                TileConfig(id: id, name: "Tile \(index + 1)", sectionIds: nil)
            }
            saveTiles()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sections) {
            UserDefaults.standard.set(data, forKey: ShortcutStore.sectionsDefaultsKey)
        }
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: ShortcutStore.shortcutsDefaultsKey)
        }
    }

    private func saveTiles() {
        if let data = try? JSONEncoder().encode(tiles) {
            UserDefaults.standard.set(data, forKey: ShortcutStore.tilesDefaultsKey)
        }
    }

    // MARK: - Tiles

    func visibleShortcutCount(for tile: TileConfig) -> Int {
        let allowedSectionIds = tile.sectionIds ?? Set(sections.map { $0.id })
        return shortcuts.filter { allowedSectionIds.contains($0.sectionId) }.count
    }

    /// Guards against spamming empty tiles across the screen — every existing
    /// tile needs at least one visible shortcut before another can be added.
    var canAddTile: Bool {
        tiles.allSatisfy { visibleShortcutCount(for: $0) >= 1 }
    }

    func addTile() {
        guard canAddTile else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Add some shortcuts first"
            alert.informativeText = "Every existing tile needs at least one shortcut before you can add another tile."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        let number = tiles.count + 1
        tiles.append(TileConfig(id: UUID().uuidString, name: "Tile \(number)", sectionIds: nil))
        saveTiles()
    }

    func removeTile(id: String) {
        tiles.removeAll { $0.id == id }
        saveTiles()
    }

    func renameTile(id: String, name: String) {
        guard let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tiles[index].name = trimmed
        saveTiles()
    }

    func promptToRenameTile(_ tile: TileConfig) {
        guard let newName = ShortcutStore.promptForText(
            title: "Rename Tile",
            message: "New name for “\(tile.name)”:",
            defaultValue: tile.name
        ), !newName.isEmpty else { return }
        renameTile(id: tile.id, name: newName)
    }

    /// `nil` makes the tile mirror everything again; a non-nil set (even empty)
    /// makes it independent, showing only those sections.
    func setTileSections(id: String, sectionIds: Set<UUID>?) {
        guard let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        tiles[index].sectionIds = sectionIds
        saveTiles()
    }

    // MARK: - Sections

    func promptToCreateSection() {
        guard let name = ShortcutStore.promptForText(
            title: "New Section",
            message: "Name this section (e.g. \"Homelab\", \"Work Servers\"):",
            defaultValue: ""
        ), !name.isEmpty else { return }

        sections.append(Section(name: name))
        save()
    }

    func promptToRenameSection(_ section: Section) {
        guard let newName = ShortcutStore.promptForText(
            title: "Rename Section",
            message: "New name for “\(section.name)”:",
            defaultValue: section.name
        ), !newName.isEmpty else { return }

        guard let index = sections.firstIndex(where: { $0.id == section.id }) else { return }
        sections[index].name = newName
        save()
    }

    func promptToRenameShortcut(_ shortcut: ScriptShortcut) {
        guard let newName = ShortcutStore.promptForText(
            title: "Rename Shortcut",
            message: "New name for “\(shortcut.label)”:",
            defaultValue: shortcut.label
        ), !newName.isEmpty else { return }

        guard let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        shortcuts[index].label = newName
        save()
    }

    func setCustomization(for shortcutId: UUID, label: String, icon: String?, colorHex: String?) {
        guard let index = shortcuts.firstIndex(where: { $0.id == shortcutId }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            shortcuts[index].label = trimmed
        }
        shortcuts[index].customIcon = icon
        shortcuts[index].customColorHex = colorHex
        save()
    }

    /// Reorders sections, optionally inserting before another section so drag-and-drop
    /// can rearrange the tile's column layout.
    func moveSection(id: UUID, beforeId: UUID?) {
        guard id != beforeId, let fromIndex = sections.firstIndex(where: { $0.id == id }) else { return }
        let section = sections.remove(at: fromIndex)
        if let beforeId, let toIndex = sections.firstIndex(where: { $0.id == beforeId }) {
            sections.insert(section, at: toIndex)
        } else {
            sections.append(section)
        }
        save()
    }

    /// Returns the first existing section's id, creating a fresh "General"
    /// section on the fly if Shorkut currently has none — so add/import flows
    /// always have somewhere to put a new shortcut even after deleting all sections.
    @discardableResult
    private func ensureDefaultSection() -> UUID {
        if let first = sections.first { return first.id }
        let section = Section(name: "General")
        sections.append(section)
        save()
        return section.id
    }

    func promptToDeleteSection(_ section: Section) {
        let count = shortcuts.filter { $0.sectionId == section.id }.count
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(section.name)”?"
        alert.informativeText = count > 0
            ? "This will also delete \(count) shortcut\(count == 1 ? "" : "s") inside it. This can't be undone."
            : "This can't be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for shortcut in shortcuts where shortcut.sectionId == section.id {
            if shortcut.kind == .script {
                try? FileManager.default.removeItem(atPath: shortcut.scriptPath)
            }
        }
        shortcuts.removeAll { $0.sectionId == section.id }
        sections.removeAll { $0.id == section.id }
        save()
    }

    private static func promptForText(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Shortcuts

    func promptToAddShortcut(to sectionId: UUID? = nil) {
        let targetSection: UUID
        if let sectionId {
            targetSection = sectionId
        } else if sections.isEmpty {
            targetSection = ensureDefaultSection()
        } else if sections.count == 1 {
            targetSection = sections[0].id
        } else if let chosen = ShortcutStore.promptForSection(sections) {
            targetSection = chosen
        } else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose a script"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Add Shortcut"

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        importScriptFile(at: sourceURL, sectionId: targetSection)
    }

    /// Copies a script file into Shorkut's managed scripts folder and adds it as a shortcut.
    /// Shared by the "Add Script…" file picker and drag-and-drop onto the tile.
    func importScriptFile(at sourceURL: URL, sectionId: UUID? = nil) {
        let targetSection: UUID
        if let sectionId {
            targetSection = sectionId
        } else if sections.isEmpty {
            targetSection = ensureDefaultSection()
        } else {
            targetSection = sections[0].id
        }

        let originalBaseName = sourceURL.deletingPathExtension().lastPathComponent
        let safeBaseName = Sanitization.safeFilenameBase(from: originalBaseName)
        let ext = sourceURL.pathExtension.isEmpty ? "sh" : sourceURL.pathExtension
        let destFilename = "\(safeBaseName).\(ext)"
        let destURL = ShortcutStore.scriptsDirectory.appendingPathComponent(destFilename).standardizedFileURL
        guard destURL.path.hasPrefix(ShortcutStore.scriptsDirectory.standardizedFileURL.path + "/") else {
            ShortcutStore.showAlert(title: "Couldn't import script", message: "That filename isn't valid.")
            return
        }

        if let fileSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int), fileSize > Sanitization.maxScriptContentSize {
            ShortcutStore.showAlert(
                title: "Script too large",
                message: "“\(sourceURL.lastPathComponent)” is larger than \(Sanitization.maxScriptContentSize / 1024 / 1024) MB, which is larger than any real shortcut script should be."
            )
            return
        }

        if FileManager.default.fileExists(atPath: destURL.path) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "“\(destFilename)” already exists"
            alert.informativeText = "A script with this name is already managed by Shorkut" +
                (shortcuts.contains(where: { $0.scriptPath == destURL.path }) ? " by an existing shortcut." : ".") +
                " Replacing it will overwrite its contents."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)
        } catch {
            ShortcutStore.showAlert(title: "Couldn't import script", message: error.localizedDescription)
            return
        }

        if let issue = ShortcutStore.plainTextIssue(at: destURL) {
            try? FileManager.default.removeItem(at: destURL)
            ShortcutStore.showAlert(title: "Not a plain-text script", message: issue)
            return
        }

        let label = sourceURL.deletingPathExtension().lastPathComponent
        let shortcut = ScriptShortcut(label: label, scriptPath: destURL.path, sectionId: targetSection)
        shortcuts.append(shortcut)
        save()
    }

    func promptToAddApp(to sectionId: UUID? = nil) {
        let targetSection: UUID
        if let sectionId {
            targetSection = sectionId
        } else if sections.isEmpty {
            targetSection = ensureDefaultSection()
        } else if sections.count == 1 {
            targetSection = sections[0].id
        } else if let chosen = ShortcutStore.promptForSection(sections) {
            targetSection = chosen
        } else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add Shortcut"

        guard panel.runModal() == .OK, let appURL = panel.url else { return }
        addAppShortcut(appURL: appURL, sectionId: targetSection)
    }

    func addAppShortcut(appURL: URL, sectionId: UUID? = nil) {
        let targetSection: UUID
        if let sectionId {
            targetSection = sectionId
        } else if sections.isEmpty {
            targetSection = ensureDefaultSection()
        } else if sections.count == 1 {
            targetSection = sections[0].id
        } else if let chosen = ShortcutStore.promptForSection(sections) {
            targetSection = chosen
        } else {
            return
        }

        let label = appURL.deletingPathExtension().lastPathComponent
        let shortcut = ScriptShortcut(label: label, scriptPath: appURL.path, sectionId: targetSection, kind: .app)
        shortcuts.append(shortcut)
        save()
    }

    func promptToAddWebpage(to sectionId: UUID? = nil) {
        let targetSection: UUID
        if let sectionId {
            targetSection = sectionId
        } else if sections.isEmpty {
            targetSection = ensureDefaultSection()
        } else if sections.count == 1 {
            targetSection = sections[0].id
        } else if let chosen = ShortcutStore.promptForSection(sections) {
            targetSection = chosen
        } else {
            return
        }

        guard let (label, urlString) = ShortcutStore.promptForWebpage() else { return }

        guard let normalized = Sanitization.normalizedWebpageURL(urlString) else {
            ShortcutStore.showAlert(
                title: "Invalid URL",
                message: "“\(urlString)” doesn't look like a valid http:// or https:// web address."
            )
            return
        }

        let resolvedLabel = label.isEmpty ? (URL(string: normalized)?.host ?? normalized) : label
        let shortcut = ScriptShortcut(label: resolvedLabel, scriptPath: normalized, sectionId: targetSection, kind: .webpage)
        shortcuts.append(shortcut)
        save()
    }

    private static func promptForWebpage() -> (label: String, url: String)? {
        let alert = NSAlert()
        alert.messageText = "Add a Webpage Shortcut"
        alert.informativeText = "Enter a name and the page URL:"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let labelField = NSTextField(frame: NSRect(x: 0, y: 28, width: 260, height: 24))
        labelField.placeholderString = "Name (optional)"
        let urlField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        urlField.placeholderString = "https://example.com"

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        container.addSubview(labelField)
        container.addSubview(urlField)
        alert.accessoryView = container
        alert.window.initialFirstResponder = urlField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let url = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        return (labelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), url)
    }

    private static func promptForSection(_ sections: [Section]) -> UUID? {
        let alert = NSAlert()
        alert.messageText = "Add to which section?"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        for section in sections {
            popup.addItem(withTitle: section.name)
        }
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let index = popup.indexOfSelectedItem
        guard index >= 0, index < sections.count else { return nil }
        return sections[index].id
    }

    /// Returns a description of the problem if the file isn't a plain-text script, or nil if it looks fine.
    private static func plainTextIssue(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return "Couldn't read the file to verify it."
        }
        if data.starts(with: Data("{\\rtf".utf8)) {
            return "\(url.lastPathComponent) is an RTF (rich text) file, not a plain-text script. " +
                "If you made it in TextEdit, use Format → Make Plain Text (⇧⌘T) before saving, then upload it again."
        }
        if data.contains(0) {
            return "\(url.lastPathComponent) doesn't look like a plain-text script (it contains binary data)."
        }
        return nil
    }

    func promptToRemoveShortcut(_ shortcut: ScriptShortcut) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove “\(shortcut.label)”?"
        alert.informativeText = shortcut.kind == .script
            ? "This will also delete its script file. This can't be undone."
            : "This can't be undone."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        removeShortcut(shortcut)
    }

    func removeShortcut(_ shortcut: ScriptShortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
        if shortcut.kind == .script {
            try? FileManager.default.removeItem(atPath: shortcut.scriptPath)
        }
        save()
    }

    /// Moves a shortcut into `sectionId`, optionally inserting it immediately before
    /// `beforeId` so drag-and-drop can reorder within a section as well as across sections.
    func moveShortcut(id: UUID, toSection sectionId: UUID, beforeId: UUID? = nil) {
        guard id != beforeId, let fromIndex = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        var item = shortcuts.remove(at: fromIndex)
        item.sectionId = sectionId

        if let beforeId, let toIndex = shortcuts.firstIndex(where: { $0.id == beforeId }) {
            shortcuts.insert(item, at: toIndex)
        } else {
            shortcuts.append(item)
        }
        save()
    }

    func readScriptContent(_ shortcut: ScriptShortcut) -> String? {
        guard shortcut.kind == .script else { return nil }
        return try? String(contentsOfFile: shortcut.scriptPath, encoding: .utf8)
    }

    func writeScriptContent(_ content: String, for shortcut: ScriptShortcut) -> Bool {
        guard shortcut.kind == .script else { return false }
        do {
            try content.write(toFile: shortcut.scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shortcut.scriptPath)
            return true
        } catch {
            ShortcutStore.showAlert(title: "Couldn't save script", message: error.localizedDescription)
            return false
        }
    }

    // MARK: - Generated shortcuts

    @discardableResult
    func addGeneratedShortcut(label: String, scriptContent: String, sectionId: UUID?) -> Bool {
        guard scriptContent.utf8.count <= Sanitization.maxScriptContentSize else {
            ShortcutStore.showAlert(
                title: "Script too large",
                message: "The generated script is larger than \(Sanitization.maxScriptContentSize / 1024 / 1024) MB."
            )
            return false
        }
        let targetSection = sectionId ?? ensureDefaultSection()
        guard let destURL = Sanitization.scriptDestinationURL(forLabel: label, in: ShortcutStore.scriptsDirectory) else {
            ShortcutStore.showAlert(title: "Couldn't create shortcut", message: "That name produced an invalid file path.")
            return false
        }
        do {
            try scriptContent.write(to: destURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)
        } catch {
            ShortcutStore.showAlert(title: "Couldn't create shortcut", message: error.localizedDescription)
            return false
        }
        shortcuts.append(ScriptShortcut(label: label, scriptPath: destURL.path, sectionId: targetSection, kind: .script))
        save()
        return true
    }

    // MARK: - Export / Import

    private func exportItem(for shortcut: ScriptShortcut) -> ShorkutExport.Item? {
        let sectionName = sections.first(where: { $0.id == shortcut.sectionId })?.name ?? "General"
        switch shortcut.kind {
        case .script:
            guard let content = try? String(contentsOfFile: shortcut.scriptPath, encoding: .utf8) else {
                ShortcutStore.showAlert(title: "Couldn't export “\(shortcut.label)”", message: "Failed to read the script file.")
                return nil
            }
            return ShorkutExport.Item(label: shortcut.label, kind: .script, sectionName: sectionName, scriptContent: content, bundleIdentifier: nil)
        case .app:
            let bundleId = Bundle(path: shortcut.scriptPath)?.bundleIdentifier
            return ShorkutExport.Item(label: shortcut.label, kind: .app, sectionName: sectionName, scriptContent: nil, bundleIdentifier: bundleId)
        case .webpage:
            return ShorkutExport.Item(label: shortcut.label, kind: .webpage, sectionName: sectionName, scriptContent: shortcut.scriptPath, bundleIdentifier: nil)
        }
    }

    func exportShortcut(_ shortcut: ScriptShortcut) {
        guard let item = exportItem(for: shortcut) else { return }
        promptToSaveExport(ShorkutExport(items: [item]), suggestedName: shortcut.label)
    }

    func exportSection(_ section: Section) {
        let items = shortcuts
            .filter { $0.sectionId == section.id }
            .compactMap { exportItem(for: $0) }
        guard !items.isEmpty else {
            ShortcutStore.showAlert(title: "Nothing to export", message: "“\(section.name)” has no shortcuts yet.")
            return
        }
        promptToSaveExport(ShorkutExport(items: items), suggestedName: section.name)
    }

    /// Bundles every shortcut across every section into a single .shorkut file —
    /// a one-click full backup, as opposed to exporting section by section.
    func exportAllShortcuts() {
        let items = shortcuts.compactMap { exportItem(for: $0) }
        guard !items.isEmpty else {
            ShortcutStore.showAlert(title: "Nothing to export", message: "You don't have any shortcuts yet.")
            return
        }
        promptToSaveExport(ShorkutExport(items: items), suggestedName: "Shorkut Backup")
    }

    private func promptToSaveExport(_ export: ShorkutExport, suggestedName: String) {
        guard let data = try? JSONEncoder().encode(export) else { return }

        let panel = NSSavePanel()
        panel.title = "Export Shortcuts"
        panel.nameFieldStringValue = "\(suggestedName).shorkut"
        panel.allowedContentTypes = [.shorkut]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            ShortcutStore.showAlert(title: "Couldn't save file", message: error.localizedDescription)
        }
    }

    func promptToImportShortcuts() {
        let panel = NSOpenPanel()
        panel.title = "Import Shortcuts"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.shorkut]
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importShortcuts(from: url)
    }

    /// Routes a file dropped onto the tile to the right import path based on its type.
    func handleDroppedFile(at url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "shorkut" {
            importShortcuts(from: url)
        } else if ext == "app" {
            addAppShortcut(appURL: url)
        } else {
            importScriptFile(at: url)
        }
    }

    func importShortcuts(from url: URL) {
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
           fileSize > Sanitization.maxImportFileSize {
            ShortcutStore.showAlert(
                title: "File too large",
                message: "“\(url.lastPathComponent)” is larger than \(Sanitization.maxImportFileSize / 1024 / 1024) MB, which is larger than a Shorkut backup should be."
            )
            return
        }

        guard let data = try? Data(contentsOf: url),
              let export = try? JSONDecoder().decode(ShorkutExport.self, from: data) else {
            ShortcutStore.showAlert(title: "Couldn't import", message: "“\(url.lastPathComponent)” isn't a valid Shorkut file.")
            return
        }

        var skipped: [String] = []
        var imported = 0
        var importedScripts = 0

        for item in export.items {
            let sectionId: UUID
            if let existing = sections.first(where: { $0.name == item.sectionName }) {
                sectionId = existing.id
            } else {
                let newSection = Section(name: item.sectionName)
                sections.append(newSection)
                sectionId = newSection.id
            }

            switch item.kind {
            case .script:
                guard let content = item.scriptContent else { skipped.append(item.label); continue }
                guard content.utf8.count <= Sanitization.maxScriptContentSize else { skipped.append(item.label); continue }
                guard let destURL = Sanitization.scriptDestinationURL(forLabel: item.label, in: ShortcutStore.scriptsDirectory) else {
                    skipped.append(item.label)
                    continue
                }
                do {
                    try content.write(to: destURL, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)
                } catch {
                    skipped.append(item.label)
                    continue
                }
                shortcuts.append(ScriptShortcut(label: item.label, scriptPath: destURL.path, sectionId: sectionId, kind: .script, needsTrustConfirmation: true))
                imported += 1
                importedScripts += 1
            case .app:
                guard let bundleId = item.bundleIdentifier,
                      let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
                    skipped.append(item.label)
                    continue
                }
                shortcuts.append(ScriptShortcut(label: item.label, scriptPath: appURL.path, sectionId: sectionId, kind: .app))
                imported += 1
            case .webpage:
                guard let rawURL = item.scriptContent, let normalized = Sanitization.normalizedWebpageURL(rawURL) else {
                    skipped.append(item.label)
                    continue
                }
                shortcuts.append(ScriptShortcut(label: item.label, scriptPath: normalized, sectionId: sectionId, kind: .webpage))
                imported += 1
            }
        }

        save()

        var summary = imported == 1 ? "Imported 1 shortcut." : "Imported \(imported) shortcuts."
        if importedScripts > 0 {
            summary += " Scripts require confirmation before they first run."
        }
        if !skipped.isEmpty {
            summary += "\n\nCouldn't import: \(skipped.joined(separator: ", ")). For apps, the app may not be installed on this Mac."
        }
        ShortcutStore.showAlert(
            title: skipped.isEmpty ? "Import complete" : "Some shortcuts were skipped",
            message: summary
        )
    }

    func run(_ shortcut: ScriptShortcut) {
        if shortcut.kind == .webpage {
            guard let url = URL(string: shortcut.scriptPath) else {
                ShortcutStore.showAlert(title: "Invalid URL", message: "“\(shortcut.label)” has an invalid web address.")
                return
            }

            if let browser = preferredBrowser, browser.isInstalled,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.rawValue) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
                    DispatchQueue.main.async {
                        if error != nil {
                            NotificationManager.shared.notify(title: shortcut.label, body: "Failed to open the page.")
                        } else {
                            NotificationManager.shared.notify(title: shortcut.label, body: "Opened in \(browser.displayName).")
                        }
                    }
                }
                return
            }

            let success = NSWorkspace.shared.open(url)
            if success {
                NotificationManager.shared.notify(title: shortcut.label, body: "Opened in your browser.")
            } else {
                NotificationManager.shared.notify(title: shortcut.label, body: "Failed to open the page.")
            }
            return
        }

        guard FileManager.default.fileExists(atPath: shortcut.scriptPath) else {
            let kindWord = shortcut.kind == .app ? "App" : "Script"
            ShortcutStore.showAlert(
                title: "\(kindWord) not found",
                message: "“\(shortcut.label)” points to \(shortcut.scriptPath), which no longer exists. " +
                    "Remove this shortcut and add it again."
            )
            return
        }

        if shortcut.kind == .app {
            let success = NSWorkspace.shared.open(URL(fileURLWithPath: shortcut.scriptPath))
            if !success {
                NotificationManager.shared.notify(title: shortcut.label, body: "Failed to launch the app.")
            }
            return
        }

        if shortcut.needsTrustConfirmation {
            guard confirmTrust(for: shortcut) else { return }
            if let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
                shortcuts[index].needsTrustConfirmation = false
                save()
            }
        }

        let terminal = preferredTerminal.isInstalled ? preferredTerminal : .terminal
        // Single-quote the path for the shell (safe against $, `, ;, etc.), then escape
        // the result for embedding inside the AppleScript string literal below.
        let escapedPath = ShortcutStore.appleScriptEscaped(ShortcutStore.shellQuoted(shortcut.scriptPath))
        let script: String

        // If the terminal app isn't running yet, `activate` launches it, which opens its
        // own default blank window/tab. On that cold-launch path we reuse that existing
        // tab directly instead of creating a new one — otherwise we'd end up with an
        // extra blank tab/window racing the app's own startup. When the app was already
        // running, we still add a new tab so we don't hijack whatever the user was doing.
        let wasAlreadyRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: terminal.rawValue).isEmpty

        switch terminal {
        case .iterm:
            if wasAlreadyRunning {
                script = """
                tell application "iTerm"
                    activate
                    if (count of windows) = 0 then
                        create window with default profile
                    else
                        tell current window to create tab with default profile
                    end if
                    tell current session of current window
                        write text "\(escapedPath)"
                    end tell
                end tell
                """
            } else {
                script = """
                tell application "iTerm"
                    activate
                    delay 0.6
                    tell current session of current window
                        write text "\(escapedPath)"
                    end tell
                end tell
                """
            }
        case .terminal:
            if wasAlreadyRunning {
                script = """
                tell application "Terminal"
                    activate
                    do script "\(escapedPath)"
                end tell
                """
            } else {
                script = """
                tell application "Terminal"
                    activate
                    delay 0.6
                    do script "\(escapedPath)" in front window
                end tell
                """
            }
        case .warp, .alacritty, .kitty, .hyper:
            // These don't expose a reliable AppleScript "run command" verb;
            // just launch the app pointed at the script's folder.
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.rawValue) else {
                ShortcutStore.showAlert(
                    title: "\(terminal.displayName) not found",
                    message: "\(terminal.displayName) is no longer installed. Pick a different terminal in the menu bar."
                )
                return
            }
            let folderURL = URL(fileURLWithPath: shortcut.scriptPath).deletingLastPathComponent()
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([folderURL], withApplicationAt: appURL, configuration: config, completionHandler: nil)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.terminationHandler = { proc in
                guard proc.terminationStatus != 0 else { return }
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    ShortcutStore.showAlert(
                        title: "Couldn't run “\(shortcut.label)”",
                        message: (message?.isEmpty == false ? message! : "Failed to launch \(terminal.displayName).")
                    )
                }
            }
        } catch {
            ShortcutStore.showAlert(
                title: "Couldn't run “\(shortcut.label)”",
                message: error.localizedDescription
            )
        }
    }

    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    /// Wraps a path in single quotes for safe use as a single shell argument —
    /// neutralizes $, `, ;, and other shell metacharacters, not just quote chars.
    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes a string for embedding inside an AppleScript double-quoted literal.
    private static func appleScriptEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// First-run trust prompt for scripts that arrived via a .shorkut import rather
    /// than a file the user explicitly picked themselves. Returns true to proceed.
    private func confirmTrust(for shortcut: ScriptShortcut) -> Bool {
        let preview = (try? String(contentsOfFile: shortcut.scriptPath, encoding: .utf8))
            .map { String($0.prefix(400)) } ?? "(couldn't read script contents)"

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Run imported script “\(shortcut.label)”?"
        alert.informativeText = "This script came from a .shorkut file someone shared with you and hasn't been run before. " +
            "Review its contents before running:\n\n\(preview)\(preview.count >= 400 ? "…" : "")"
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
