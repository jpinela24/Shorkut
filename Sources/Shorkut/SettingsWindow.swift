import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class SettingsWindow: NSWindow {
    init(store: ShortcutStore, appDelegate: AppDelegate) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        title = "Shorkut Settings"
        center()
        isReleasedWhenClosed = false

        let view = SettingsView(store: store, appDelegate: appDelegate)
        contentView = NSHostingView(rootView: view)
    }

    override var canBecomeKey: Bool { true }
}

struct SettingsView: View {
    @ObservedObject var store: ShortcutStore
    let appDelegate: AppDelegate
    @ObservedObject private var tabModel = SettingsTabModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tabModel.selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch tabModel.selectedTab {
                case .shortcuts:
                    ShortcutsTab(store: store, appDelegate: appDelegate)
                case .importFile:
                    ImportTab(store: store)
                case .runSettings:
                    RunSettingsTab(store: store)
                case .general:
                    GeneralTab(appDelegate: appDelegate, store: store)
                }
            }
            .padding(16)
        }
        .frame(width: 460, height: 480)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case importFile
    case runSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .importFile: return "Import"
        case .runSettings: return "Run Settings"
        }
    }
}

final class SettingsTabModel: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
}

// MARK: - General tab

struct GeneralTab: View {
    let appDelegate: AppDelegate
    @ObservedObject var store: ShortcutStore
    @ObservedObject private var loginItem = LoginItemManager.shared
    @ObservedObject private var notifications = NotificationManager.shared
    @ObservedObject private var updateChecker = UpdateChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Launch Shorkut at login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))

            Toggle("Notify when a shortcut runs", isOn: Binding(
                get: { notifications.isEnabled },
                set: { notifications.isEnabled = $0 }
            ))

            Picker("Tile width", selection: Binding(
                get: { store.tileWidthScale },
                set: { store.setTileWidthScale($0) }
            )) {
                Text("1 tile").tag(1)
                Text("2 tiles").tag(2)
                Text("3 tiles").tag(3)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Shortcuts run scripts and open apps with your full user permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Only add scripts and shortcut files you trust or wrote yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("Restart Shorkut") {
                    appDelegate.restartApp()
                }
                Button("Quit Shorkut") {
                    NSApplication.shared.terminate(nil)
                }
                Spacer()
                Button(updateChecker.isChecking ? "Checking…" : "Check for Updates") {
                    updateChecker.checkForUpdates()
                }
                .disabled(updateChecker.isChecking)
            }

            Text("Shorkut \(updateChecker.currentVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/jpinela24")!)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text("Made by jpinela24 on GitHub")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .onAppear { loginItem.refresh() }
    }
}

// MARK: - Shortcuts tab

final class ShortcutSearchModel: ObservableObject {
    @Published var query: String = ""
}

struct ShortcutsTab: View {
    @ObservedObject var store: ShortcutStore
    let appDelegate: AppDelegate
    @ObservedObject private var appsModel = AppsBrowserModel()
    @ObservedObject private var searchModel = ShortcutSearchModel()

    private func filteredShortcuts(for group: (section: Section, shortcuts: [ScriptShortcut])) -> [ScriptShortcut] {
        guard !searchModel.query.isEmpty else { return group.shortcuts }
        return group.shortcuts.filter { $0.label.localizedCaseInsensitiveContains(searchModel.query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search shortcuts…", text: Binding(
                    get: { searchModel.query },
                    set: { searchModel.query = $0 }
                ))
                .textFieldStyle(.plain)
                if !searchModel.query.isEmpty {
                    Button {
                        searchModel.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.groupedShortcuts, id: \.section.id) { group in
                        let visibleShortcuts = filteredShortcuts(for: group)
                        if searchModel.query.isEmpty || !visibleShortcuts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(group.section.name)
                                    .font(.subheadline.bold())
                                    .padding(.vertical, 2)
                                Spacer()
                                Button {
                                    store.promptToRenameSection(group.section)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                Button {
                                    store.exportSection(group.section)
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                Button {
                                    store.promptToDeleteSection(group.section)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                Menu {
                                    Button("Add Script…") {
                                        store.promptToAddShortcut(to: group.section.id)
                                    }
                                    Button("Add App…") {
                                        store.promptToAddApp(to: group.section.id)
                                    }
                                    Button("Add Webpage…") {
                                        store.promptToAddWebpage(to: group.section.id)
                                    }
                                    Button("New from Template…") {
                                        appDelegate.showTemplateGenerator(sectionId: group.section.id)
                                    }
                                } label: {
                                    Image(systemName: "plus.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .foregroundStyle(.secondary)
                            }

                            if visibleShortcuts.isEmpty {
                                Text("No shortcuts")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else {
                                ForEach(visibleShortcuts) { shortcut in
                                    HStack {
                                        ShortcutIcon(shortcut: shortcut)
                                            .frame(width: 16, height: 16)
                                        Button(shortcut.label) {
                                            store.run(shortcut)
                                        }
                                        .buttonStyle(.plain)
                                        Spacer()
                                        Button {
                                            appDelegate.showCustomizeShortcut(for: shortcut)
                                        } label: {
                                            Image(systemName: "pencil")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                        .help("Edit name & icon")
                                        if shortcut.kind == .script {
                                            Button {
                                                appDelegate.showScriptEditor(for: shortcut)
                                            } label: {
                                                Image(systemName: "doc.text")
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(.secondary)
                                        }
                                        Button {
                                            store.exportShortcut(shortcut)
                                        } label: {
                                            Image(systemName: "square.and.arrow.up")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                        Button {
                                            store.promptToRemoveShortcut(shortcut)
                                        } label: {
                                            Image(systemName: "minus.circle")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 4)
                                    .background(Color.primary.opacity(0.001)) // ensures full-row drag/drop hit-testing
                                    .onDrag {
                                        NSItemProvider(object: shortcut.id.uuidString as NSString)
                                    }
                                    .onDrop(of: [.text], isTargeted: nil) { providers in
                                        guard let provider = providers.first else { return false }
                                        provider.loadObject(ofClass: NSString.self) { object, _ in
                                            guard let idString = object as? String, let id = UUID(uuidString: idString) else { return }
                                            DispatchQueue.main.async {
                                                store.moveShortcut(id: id, toSection: group.section.id, beforeId: shortcut.id)
                                            }
                                        }
                                        return true
                                    }
                                }
                            }
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                        )
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            guard let provider = providers.first else { return false }
                            provider.loadObject(ofClass: NSString.self) { object, _ in
                                guard let idString = object as? String, let id = UUID(uuidString: idString) else { return }
                                DispatchQueue.main.async {
                                    store.moveShortcut(id: id, toSection: group.section.id)
                                }
                            }
                            return true
                        }
                        Divider()
                        }
                    }
                }
            }

            DisclosureGroup(isExpanded: Binding(
                get: { appsModel.isExpanded },
                set: { appsModel.isExpanded = $0 }
            )) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Search apps…", text: Binding(
                        get: { appsModel.searchText },
                        set: { appsModel.searchText = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    List(appsModel.filteredApps, id: \.self) { appURL in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text(appURL.deletingPathExtension().lastPathComponent)
                            Spacer()
                            Button("Add") {
                                store.addAppShortcut(appURL: appURL)
                            }
                        }
                    }
                    .frame(height: 140)
                }
                .padding(.top, 6)
            } label: {
                Text("Add an Installed App")
                    .font(.subheadline.bold())
            }

            HStack(spacing: 12) {
                Button {
                    store.promptToCreateSection()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .help("New Section…")

                Menu {
                    Button("Import Shortcuts…") {
                        store.promptToImportShortcuts()
                    }
                    Button("Export All as Backup…") {
                        store.exportAllShortcuts()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("More tools")

                Spacer()
            }
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

// MARK: - Apps browser (embedded in Shortcuts tab)

final class AppsBrowserModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var isExpanded: Bool = false

    static let allApps: [URL] = {
        let dirs = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var apps: [URL] = []
        for dir in dirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil) else { continue }
            apps.append(contentsOf: contents.filter { $0.pathExtension == "app" })
        }
        return apps.sorted { $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare($1.deletingPathExtension().lastPathComponent) == .orderedAscending }
    }()

    var filteredApps: [URL] {
        guard !searchText.isEmpty else { return AppsBrowserModel.allApps }
        return AppsBrowserModel.allApps.filter {
            $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - Import tab

struct ImportTab: View {
    @ObservedObject var store: ShortcutStore

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Drag in scripts, apps, or .shorkut files")
                .font(.headline)
            Text("Drop a .sh script, an app, or a .shorkut file shared by a friend anywhere below — or pick a .shorkut file manually.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Choose .shorkut File…") {
                store.promptToImportShortcuts()
            }
            Spacer()
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(.secondary.opacity(0.4))
                .padding(8)
        )
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        store.handleDroppedFile(at: url)
                    }
                }
            }
            return true
        }
    }
}

// MARK: - Run Settings tab

struct RunSettingsTab: View {
    @ObservedObject var store: ShortcutStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scripts run through your chosen terminal app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Run scripts in", selection: Binding(
                get: { store.preferredTerminal },
                set: { store.setPreferredTerminal($0) }
            )) {
                ForEach(TerminalApp.installed) { app in
                    Text(app.displayName).tag(app)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 240)

            Divider()

            Text("Webpage shortcuts open in your chosen browser.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Open links in", selection: Binding(
                get: { store.preferredBrowser },
                set: { store.setPreferredBrowser($0) }
            )) {
                Text("System Default").tag(BrowserApp?.none)
                ForEach(BrowserApp.installed) { app in
                    Text(app.displayName).tag(BrowserApp?.some(app))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 240)

            Spacer()
        }
        .padding(.top, 8)
    }
}
