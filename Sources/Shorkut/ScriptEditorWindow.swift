import SwiftUI
import AppKit
#if canImport(ShorkutCore)
import ShorkutCore
#endif

final class ScriptEditorWindow: NSWindow {
    init(store: ShortcutStore, shortcut: ScriptShortcut) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        title = "Edit “\(shortcut.label)”"
        center()
        isReleasedWhenClosed = false

        let view = ScriptEditorView(store: store, shortcut: shortcut) { [weak self] in
            self?.close()
        }
        contentView = NSHostingView(rootView: view)
    }

    override var canBecomeKey: Bool { true }
}

final class ScriptEditorModel: ObservableObject {
    @Published var text: String = ""
    @Published var hasUnsavedChanges: Bool = false
}

struct ScriptEditorView: View {
    @ObservedObject var store: ShortcutStore
    let shortcut: ScriptShortcut
    var onDone: () -> Void

    @ObservedObject private var model = ScriptEditorModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(shortcut.scriptPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)

            ScriptTextEditor(text: Binding(
                get: { model.text },
                set: {
                    model.text = $0
                    model.hasUnsavedChanges = true
                }
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if model.hasUnsavedChanges {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Cancel") { onDone() }
                Button("Save") {
                    if store.writeScriptContent(model.text, for: shortcut) {
                        model.hasUnsavedChanges = false
                        onDone()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 280)
        .onAppear {
            model.text = store.readScriptContent(shortcut) ?? ""
        }
    }
}

/// Thin wrapper around NSTextView for a monospaced, multi-line code editor —
/// SwiftUI's TextEditor doesn't support a custom font reliably across macOS versions.
struct ScriptTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.delegate = context.coordinator
        textView.string = text
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
