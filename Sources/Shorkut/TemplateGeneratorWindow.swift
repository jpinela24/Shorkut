import SwiftUI
import AppKit

final class TemplateGeneratorWindow: NSWindow {
    init(store: ShortcutStore, sectionId: UUID?) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "New Shortcut from Template"
        center()
        isReleasedWhenClosed = false

        let view = TemplateGeneratorView(store: store, sectionId: sectionId) { [weak self] in
            self?.close()
        }
        contentView = NSHostingView(rootView: view)
    }

    override var canBecomeKey: Bool { true }
}

final class TemplateFormModel: ObservableObject {
    @Published var template: ShortcutTemplate = .ssh {
        didSet {
            values = Dictionary(uniqueKeysWithValues: template.fields.map { ($0.key, $0.defaultValue) })
        }
    }
    @Published var label: String = ""
    @Published var values: [String: String] = [:]
    @Published var selectedSectionId: UUID?

    init() {
        values = Dictionary(uniqueKeysWithValues: template.fields.map { ($0.key, $0.defaultValue) })
    }
}

struct TemplateGeneratorView: View {
    @ObservedObject var store: ShortcutStore
    let sectionId: UUID?
    var onDone: () -> Void

    @ObservedObject private var model = TemplateFormModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Shortcut from Template")
                .font(.headline)

            Picker("Template", selection: $model.template) {
                ForEach(ShortcutTemplate.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.template.fields) { field in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(field.placeholder, text: binding(for: field.key))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text("Shortcut name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Restart Plex", text: $model.label)
                    .textFieldStyle(.roundedBorder)
            }

            if store.sections.count > 1 {
                Picker("Section", selection: Binding(
                    get: { model.selectedSectionId ?? sectionId ?? store.sections.first!.id },
                    set: { model.selectedSectionId = $0 }
                )) {
                    ForEach(store.sections) { section in
                        Text(section.name).tag(section.id)
                    }
                }
            }

            Spacer()

            ScrollView {
                Text(model.template.script(values: model.values))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 60)
            .background(Color.black.opacity(0.05))
            .cornerRadius(6)

            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                Button("Create") {
                    let targetSection = model.selectedSectionId ?? sectionId ?? store.sections.first?.id
                    let name = model.label.isEmpty ? model.template.displayName : model.label
                    if store.addGeneratedShortcut(label: name, scriptContent: model.template.script(values: model.values), sectionId: targetSection) {
                        onDone()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { model.values[key] ?? "" },
            set: { model.values[key] = $0 }
        )
    }
}
