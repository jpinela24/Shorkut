import Foundation
import AppKit

/// Checks GitHub Releases for a newer tagged version than the one currently
/// running. Shorkut isn't notarized/auto-updating, so this just points the
/// user at the release page — they still download and re-install manually.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    private static let releasesAPIURL = URL(string: "https://api.github.com/repos/jpinela24/Shorkut/releases/latest")!
    private static let releasesPageURL = URL(string: "https://github.com/jpinela24/Shorkut/releases/latest")!
    private static let lastAutoCheckDefaultsKey = "ShorkutLastAutoUpdateCheck"
    private static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    @Published var isChecking = false

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Launch-time check — throttled to once per day so restarting the app
    /// repeatedly (e.g. while testing a build) doesn't burn through GitHub's
    /// unauthenticated API rate limit (60 requests/hour per IP).
    func checkForUpdatesIfDue() {
        let last = UserDefaults.standard.double(forKey: Self.lastAutoCheckDefaultsKey)
        guard Date().timeIntervalSince1970 - last >= Self.autoCheckInterval else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastAutoCheckDefaultsKey)
        checkForUpdates(silent: true)
    }

    /// `silent` suppresses the "you're up to date" / error alerts, used for
    /// the automatic launch-time check so it doesn't nag when nothing's new.
    func checkForUpdates(silent: Bool = false) {
        guard !isChecking else { return }
        isChecking = true

        var request = URLRequest(url: Self.releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                guard let data, error == nil,
                      let release = try? JSONDecoder().decode(Release.self, from: data) else {
                    if !silent {
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = "Couldn't check for updates"
                        alert.informativeText = "Couldn't reach GitHub. Check your internet connection and try again."
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                    return
                }

                let latestVersion = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                let current = self?.currentVersion ?? "1.0.0"

                if Self.isNewer(latestVersion, than: current) {
                    self?.promptToUpdate(to: latestVersion, url: release.html_url)
                } else if !silent {
                    let alert = NSAlert()
                    alert.messageText = "You're up to date"
                    alert.informativeText = "Shorkut \(current) is the latest version."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }.resume()
    }

    private func promptToUpdate(to version: String, url: String) {
        let alert = NSAlert()
        alert.messageText = "Shorkut \(version) is available"
        alert.informativeText = "You're running \(currentVersion). Download the new version from GitHub?"
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(URL(string: url) ?? Self.releasesPageURL)
    }

    /// Compares dotted version strings numerically (e.g. "1.10.0" > "1.9.0"),
    /// padding missing components with 0 so "1.1" vs "1.1.0" compares equal.
    private static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").compactMap { Int($0) }
        let b = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
