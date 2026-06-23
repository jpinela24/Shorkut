import SwiftUI
import AppKit

final class CustomizeShortcutWindow: NSWindow {
    init(store: ShortcutStore, shortcut: ScriptShortcut) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "Customize “\(shortcut.label)”"
        center()
        isReleasedWhenClosed = false

        let view = CustomizeShortcutView(store: store, shortcut: shortcut) { [weak self] in
            self?.close()
        }
        contentView = NSHostingView(rootView: view)
    }

    override var canBecomeKey: Bool { true }
}

private let iconChoices = [
    "star.fill", "bolt.fill", "flag.fill", "gearshape.fill", "heart.fill",
    "folder.fill", "terminal.fill", "link", "gamecontroller.fill", "cloud.fill",
    "house.fill", "server.rack", "wifi", "lock.fill", "globe",
    "desktopcomputer", "printer.fill", "tv.fill", "music.note", "camera.fill"
]

final class CustomizeShortcutModel: ObservableObject {
    @Published var name: String = ""
    @Published var selectedIcon: String?
    @Published var selectedColor: Color = .green
}

struct CustomizeShortcutView: View {
    @ObservedObject var store: ShortcutStore
    let shortcut: ScriptShortcut
    var onDone: () -> Void

    @ObservedObject private var model = CustomizeShortcutModel()

    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField("Shortcut name", text: $model.name)
                .textFieldStyle(.roundedBorder)

            Text("Icon")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(iconChoices, id: \.self) { icon in
                    Button {
                        model.selectedIcon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundStyle(model.selectedIcon == icon ? model.selectedColor : .secondary)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(model.selectedIcon == icon ? model.selectedColor.opacity(0.15) : Color.primary.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            ColorPicker("Color", selection: $model.selectedColor, supportsOpacity: false)

            Spacer()

            HStack {
                Button("Reset Icon") {
                    store.setCustomization(for: shortcut.id, label: model.name, icon: nil, colorHex: nil)
                    onDone()
                }
                Spacer()
                Button("Cancel") { onDone() }
                Button("Save") {
                    store.setCustomization(for: shortcut.id, label: model.name, icon: model.selectedIcon, colorHex: model.selectedColor.toHex())
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 280, height: 360)
        .onAppear {
            model.name = shortcut.label
            model.selectedIcon = shortcut.customIcon
            model.selectedColor = shortcut.customColorHex.flatMap(Color.init(hex:)) ?? .green
        }
    }
}
