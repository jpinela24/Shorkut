import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

final class DesktopTileWindow: NSWindow, NSWindowDelegate {
    private static let originDefaultsKeyPrefix = "SSHWidgetTileOrigin"
    private static let firstLaunchAnimationKey = "ShorkutTileFirstLaunchAnimationShown"
    static let lockedDefaultsKey = "SSHWidgetTileLocked"
    /// The very first tile ever created keeps the original unsuffixed defaults
    /// key, so upgrading from a single-tile version doesn't lose its position.
    static let primaryTileId = "primary"
    static let baseWidth: CGFloat = 164
    static let tileSize = NSSize(width: baseWidth, height: 164)
    static let maxTileHeight: CGFloat = 600

    let id: String
    private var hostingView: NSHostingView<DesktopTileView>!
    private var cancellable: AnyCancellable?
    private var snapDebounceTimer: Timer?
    private let store: ShortcutStore

    static var isLocked: Bool {
        UserDefaults.standard.bool(forKey: lockedDefaultsKey)
    }

    private var currentWidth: CGFloat {
        DesktopTileWindow.baseWidth * CGFloat(max(1, min(3, store.tileWidthScale)))
    }

    init(store: ShortcutStore, id: String = DesktopTileWindow.primaryTileId) {
        self.store = store
        self.id = id
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

        let hosting = NSHostingView(rootView: DesktopTileView(store: store, tileId: id))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hostingView = hosting
        contentView = hosting

        delegate = self

        if let savedOrigin = DesktopTileWindow.savedOrigin(for: id) {
            setFrameOrigin(savedOrigin)
        } else if let screen = NSScreen.main {
            let x = screen.frame.minX + 24 + (id == DesktopTileWindow.primaryTileId ? 0 : CGFloat.random(in: 40...160))
            let y = screen.frame.maxY - size.height - 60 - (id == DesktopTileWindow.primaryTileId ? 0 : CGFloat.random(in: 40...160))
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
        DesktopTileWindow.saveOrigin(frame.origin, for: id)
        // Snap to the desktop-icon-style grid once dragging settles, rather than
        // on every move event (which would fight the user's hand mid-drag).
        snapDebounceTimer?.invalidate()
        snapDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.snapToGridIfNeeded()
        }
    }

    /// Finder lays desktop icons out from the top-right corner of the screen,
    /// so the snap grid is anchored there too instead of the screen's
    /// bottom-left origin — otherwise the grid lines tiles fall into don't
    /// line up with where real desktop icons sit.
    private func snapToGridIfNeeded() {
        guard !DesktopTileWindow.isLocked else { return }
        guard let screen = screen ?? NSScreen.main else { return }
        let cellWidth = DesktopIconGrid.cellWidth
        let cellHeight = DesktopIconGrid.cellHeight
        let anchor = NSPoint(x: screen.visibleFrame.maxX, y: screen.visibleFrame.maxY)

        let offsetX = anchor.x - frame.origin.x
        let offsetY = anchor.y - frame.origin.y
        let snappedOffsetX = (offsetX / cellWidth).rounded() * cellWidth
        let snappedOffsetY = (offsetY / cellHeight).rounded() * cellHeight

        let snappedX = anchor.x - snappedOffsetX
        let snappedY = anchor.y - snappedOffsetY
        guard abs(snappedX - frame.origin.x) > 0.5 || abs(snappedY - frame.origin.y) > 0.5 else { return }
        setFrameOrigin(NSPoint(x: snappedX, y: snappedY))
        DesktopTileWindow.saveOrigin(frame.origin, for: id)
    }

    /// Grows/shrinks the tile to fit its shortcut list and chosen width, keeping the
    /// top-left corner anchored so it always expands downward/rightward, never re-centering.
    /// When auto-resize is turned off, the tile stays pinned at its original size and
    /// any overflow scrolls inside it instead (see DesktopTileView's ScrollView).
    private func resizeToFitContent() {
        let newHeight: CGFloat
        if store.autoResizeTile {
            let fitting = hostingView.fittingSize
            newHeight = min(max(fitting.height, DesktopTileWindow.tileSize.height), DesktopTileWindow.maxTileHeight)
        } else {
            newHeight = DesktopTileWindow.tileSize.height
        }
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

    private static func defaultsKey(for id: String) -> String {
        id == primaryTileId ? originDefaultsKeyPrefix : "\(originDefaultsKeyPrefix)-\(id)"
    }

    private static func savedOrigin(for id: String) -> NSPoint? {
        guard let str = UserDefaults.standard.string(forKey: defaultsKey(for: id)) else { return nil }
        let parts = str.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return NSPoint(x: parts[0], y: parts[1])
    }

    private static func saveOrigin(_ point: NSPoint, for id: String) {
        UserDefaults.standard.set("\(point.x),\(point.y)", forKey: defaultsKey(for: id))
    }

    static func removeSavedOrigin(for id: String) {
        UserDefaults.standard.removeObject(forKey: defaultsKey(for: id))
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
    let tileId: String

    private var columnCount: Int { max(1, min(3, store.tileWidthScale)) }

    /// Sections this specific tile should show — everything, unless this tile
    /// has been made independent with its own section selection.
    private var visibleSections: [Section] {
        guard let allowed = store.tiles.first(where: { $0.id == tileId })?.sectionIds else {
            return store.sections
        }
        return store.sections.filter { allowed.contains($0.id) }
    }

    private var visibleShortcuts: [ScriptShortcut] {
        let sectionIds = Set(visibleSections.map { $0.id })
        return store.shortcuts.filter { sectionIds.contains($0.sectionId) }
    }

    private func shortcuts(for section: Section) -> [ScriptShortcut] {
        store.shortcuts.filter { $0.sectionId == section.id }
    }

    private func sectionsForColumn(_ col: Int) -> [Section] {
        visibleSections.enumerated().filter { $0.offset % columnCount == col }.map { $0.element }
    }

    var body: some View {
        // ScrollView + maxHeight is the standard SwiftUI "grow naturally, then
        // scroll once capped" pattern: below the cap it sizes exactly to its
        // content (no visible scrollbar, behaves like a plain stack); past the
        // cap it becomes scrollable instead of silently clipping unreachable rows.
        ScrollView(showsIndicators: false) {
            Group {
                if visibleShortcuts.isEmpty {
                    Text("Add shortcuts from the menu bar icon")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 130, alignment: .center)
                } else if columnCount == 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visibleSections) { section in
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
        }
        .frame(maxHeight: (store.autoResizeTile ? DesktopTileWindow.maxTileHeight : DesktopTileWindow.tileSize.height) - 28)
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
        .contextMenu {
            Button("Add Another Tile") { store.addTile() }
            Button("Remove This Tile") { store.removeTile(id: tileId) }
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
            .onDrop(of: [UTType.shorkutDragPayload], isTargeted: nil) { providers in
                loadShorkutDragPayload(from: providers) { raw in
                    guard raw.hasPrefix("section:"),
                          let id = UUID(uuidString: String(raw.dropFirst("section:".count))) else { return }
                    store.moveSection(id: id, beforeId: section.id)
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
        .onDrag {
            shorkutDragProvider("section:\(section.id.uuidString)")
        }
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
