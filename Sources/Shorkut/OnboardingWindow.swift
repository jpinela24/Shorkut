import SwiftUI
import AppKit

final class OnboardingWindow: NSWindow {
    private static let shownDefaultsKey = "ShorkutOnboardingShown"

    static var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: shownDefaultsKey)
    }

    init(appDelegate: AppDelegate) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "Welcome to Shorkut"
        center()
        isReleasedWhenClosed = false
        level = .floating

        UserDefaults.standard.set(true, forKey: OnboardingWindow.shownDefaultsKey)

        let view = OnboardingView(
            onFinish: { [weak self] in self?.close() },
            onOpenSettings: { [weak self, weak appDelegate] in
                appDelegate?.showSettings()
                self?.close()
            }
        )
        contentView = NSHostingView(rootView: view)
    }

    override var canBecomeKey: Bool { true }
}

private struct OnboardingPage {
    let symbol: String
    let title: String
    let body: String
}

private let onboardingPages = [
    OnboardingPage(
        symbol: "bolt.fill",
        title: "Welcome to Shorkut",
        body: "All your shortcuts — scripts, apps, webpages — in one place. Live on your desktop and in your menu bar."
    ),
    OnboardingPage(
        symbol: "plus.circle.fill",
        title: "Add anything",
        body: "Add a script, an app, or a webpage from Settings. Or just drag a .sh file, an app, or a .shorkut file straight onto the tile."
    ),
    OnboardingPage(
        symbol: "square.grid.2x2.fill",
        title: "Organize your way",
        body: "Group shortcuts into sections, drag to reorder them, give each one a custom icon and color, even assign a hotkey."
    ),
    OnboardingPage(
        symbol: "checkmark.circle.fill",
        title: "You're set",
        body: "Open Settings any time from the menu bar icon to add your first shortcut."
    )
]

final class OnboardingModel: ObservableObject {
    @Published var pageIndex: Int = 0
}

struct OnboardingView: View {
    var onFinish: () -> Void
    var onOpenSettings: () -> Void

    @ObservedObject private var model = OnboardingModel()

    private var page: OnboardingPage { onboardingPages[model.pageIndex] }
    private var isLastPage: Bool { model.pageIndex == onboardingPages.count - 1 }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: page.symbol)
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text(page.title)
                .font(.title2.bold())

            Text(page.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<onboardingPages.count, id: \.self) { index in
                    Circle()
                        .fill(index == model.pageIndex ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            HStack {
                if model.pageIndex > 0 {
                    Button("Back") { model.pageIndex -= 1 }
                } else {
                    Button("Skip") { onFinish() }
                }
                Spacer()
                if isLastPage {
                    Button("Open Settings") { onOpenSettings() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Next") { model.pageIndex += 1 }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(width: 420, height: 380)
    }
}
