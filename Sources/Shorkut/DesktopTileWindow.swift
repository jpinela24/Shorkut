import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

final class DesktopTileWindow: NSWindow, NSWindowDelegate {
    private static let originDefaultsKey = "SSHWidgetTileOrigin"
    private static let firstLaunchAnimationKey = "ShorkutTileFirstLaunchAnimationShown"
    static let lockedDefaultsKey = "SSHWidgetTileLocked"
    static let baseWidth: CGFloat = 164
    static let tileSize = NSSize(width: baseWidth, height: 164)
    static let maxTileHeight: CGFloat = 600

    private var hostingView: NSHostingView<DesktopTileView>!
    private var cancellable: AnyCancellable?
    private let store: ShortcutStore

    static var isLocked: Bool {
        UserDefaults.standard.bool(forKey: lockedDefaultsKey)
    }

    private var currentWidth: CGFloat {
        DesktopTileWindow.baseWidth * CGFloat(max(1, min(3, store.tileWidthScale)))
    }

    init(store: ShortcutStore) {
        self.store = store
        let size = NSSize(width: DesktopTileWindow.baseWidth * CGFloat(max(1, min(3, store.tileWidthScale))), height: DesktopTileWindow.tileSize.height)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = !DesktopTileWindow.isLocked
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Sit above Finder's desktop-icon layer (which otherwise eats all clicks/drag-selects)
        // but still below normal app windows, so it behaves like a real desktop widget.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

        let hosting = NSHostingView(rootView: DesktopTileView(store: store))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hostingView = hosting
        contentView = hosting

        delegate = self

        if let savedOrigin = DesktopTileWindow.savedOrigin() {
            setFrameOrigin(savedOrigin)
        } else if let screen = NSScreen.main {
            let x = screen.frame.minX + 24
            let y = screen.frame.maxY - size.height - 60
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.resizeToFitContent()
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.resizeToFitContent()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Plays a bouncy spring-in animation the very first time the tile ever appears.
    func playFirstLaunchAnimationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: DesktopTileWindow.firstLaunchAnimationKey),
              let layer = hostingView.layer else { return }
        UserDefaults.standard.set(true, forKey: DesktopTileWindow.firstLaunchAnimationKey)

        layer.transform = CATransform3DMakeScale(0.3, 0.3, 0.3)
        hostingView.alphaValue = 0

        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.3
        scale.toValue = 1.0
        scale.damping = 9
        scale.initialVelocity = 12
        scale.stiffness = 220
        scale.mass = 1.1
        scale.duration = scale.settlingDuration
        layer.add(scale, forKey: "bounceIn")
        layer.transform = CATransform3DIdentity

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            hostingView.animator().alphaValue = 1
        }
    }

    func windowDidMove(_ notification: Notification) {
        DesktopTileWindow.saveOrigin(frame.origin)
    }

    /// Grows/shrinks the tile to fit its shortcut list and chosen width, keeping the
    /// top-left corner anchored so it always expands downward/rightward, never re-centering.
    private func resizeToFitContent() {
        let fitting = hostingView.fittingSize
        let newHeight = min(max(fitting.height, DesktopTileWindow.tileSize.height), DesktopTileWindow.maxTileHeight)
        let newSize = NSSize(width: currentWidth, height: newHeight)

        guard abs(newSize.height - frame.height) > 0.5 || abs(newSize.width - frame.width) > 0.5 else { return }

        let topY = frame.origin.y + frame.size.height
        let newOrigin = NSPoint(x: frame.origin.x, y: topY - newSize.height)
        setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: false)
        hostingView.frame = NSRect(origin: .zero, size: newSize)
    }

    func setLocked(_ locked: Bool) {
        UserDefaults.standard.set(locked, forKey: DesktopTileWindow.lockedDefaultsKey)
        isMovableByWindowBackground = !locked
    }

    private static func savedOrigin() -> NSPoint? {
        guard let str = UserDefaults.standard.string(forKey: originDefaultsKey) else { return nil }
        let parts = str.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return NSPoint(x: parts[0], y: parts[1])
    }

    private static func saveOrigin(_ point: NSPoint) {
        UserDefaults.standard.set("\(point.x),\(point.y)", forKey: originDefaultsKey)
    }
}

extension Color {
    init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

/// Caches per-path app icons so SwiftUI re-renders don't repeatedly hit
/// NSWorkspace (icon lookup/rendering isn't free, and rows re-render often).
final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(forFile path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}

struct ShortcutIcon: View {
    let shortcut: ScriptShortcut

    var body: some View {
        if let customIcon = shortcut.customIcon {
            Image(systemName: customIcon)
                .resizable()
                .scaledToFit()
                .foregroundStyle(shortcut.customColorHex.flatMap(Color.init(hex:)) ?? defaultColor)
        } else {
            switch shortcut.kind {
            case .app where FileManager.default.fileExists(atPath: shortcut.scriptPath):
                Image(nsImage: AppIconCache.shared.icon(forFile: shortcut.scriptPath))
                    .resizable()
                    .scaledToFit()
            case .webpage:
                Image(systemName: "link.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(shortcut.customColorHex.flatMap(Color.init(hex:)) ?? .blue)
            default:
                Image(systemName: "chevron.right.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(shortcut.customColorHex.flatMap(Color.init(hex:)) ?? .green)
            }
        }
    }

    private var defaultColor: Color {
        shortcut.kind == .webpage ? .blue : .green
    }
}

struct DesktopTileView: View {
    @ObservedObject var store: ShortcutStore

    private var columnCount: Int { max(1, min(3, store.tileWidthScale)) }

    private func shortcuts(for section: Section) -> [ScriptShortcut] {
        store.shortcuts.filter { $0.sectionId == section.id }
    }

    private func sectionsForColumn(_ col: Int) -> [Section] {
        store.sections.enumerated().filter { $0.offset % columnCount == col }.map { $0.element }
    }

    var body: some View {
        Group {
            if store.shortcuts.isEmpty {
                Text("Add shortcuts from the menu bar icon")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 130, alignment: .center)
            } else if columnCount == 1 {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.sections) { section in
                        sectionBlock(section)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<columnCount, id: \.self) { col in
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(sectionsForColumn(col)) { section in
                                sectionBlock(section)
                            }
                        }
                        .frame(width: DesktopTileWindow.baseWidth - 28, alignment: .topLeading)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: DesktopTileWindow.baseWidth * CGFloat(columnCount), alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.92))
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(.dark)
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

    @ViewBuilder
    private func sectionBlock(_ section: Section) -> some View {
        let sectionShortcuts = shortcuts(for: section)
        if !sectionShortcuts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader(section)
                if !store.collapsedSectionIds.contains(section.id) {
                    ForEach(sectionShortcuts) { shortcut in
                        shortcutRow(shortcut)
                    }
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.001)))
            .onDrag {
                NSItemProvider(object: "section:\(section.id.uuidString)" as NSString)
            }
            .onDrop(of: [.text], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let raw = object as? String, raw.hasPrefix("section:"),
                          let id = UUID(uuidString: String(raw.dropFirst("section:".count))) else { return }
                    DispatchQueue.main.async {
                        store.moveSection(id: id, beforeId: section.id)
                    }
                }
                return true
            }
        }
    }

    private func sectionHeader(_ section: Section) -> some View {
        let isCollapsed = store.collapsedSectionIds.contains(section.id)
        return Button {
            store.toggleSectionCollapsed(section.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                Text(section.name.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename Section…") {
                store.promptToRenameSection(section)
            }
        }
    }

    private func shortcutRow(_ shortcut: ScriptShortcut) -> some View {
        Button {
            store.run(shortcut)
        } label: {
            HStack(spacing: 6) {
                ShortcutIcon(shortcut: shortcut)
                    .frame(width: 13, height: 13)
                Text(shortcut.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…") {
                store.promptToRenameShortcut(shortcut)
            }
            Button("Remove “\(shortcut.label)”", role: .destructive) {
                store.promptToRemoveShortcut(shortcut)
            }
        }
    }
}
