import Foundation
import AppKit
#if canImport(ShorkutCore)
import ShorkutCore
#endif

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
        // NB: the timestamp is recorded *after* the request completes (see below),
        // not here — otherwise a failed check still counts as "checked today" and
        // suppresses retries for 24h.
        checkForUpdates(silent: true)
    }

    /// `silent` suppresses the "you're up to date" / error alerts, used for
    /// the automatic launch-time check so it doesn't nag when nothing's new.
    func checkForUpdates(silent: Bool = false) {
        guard !isChecking else { return }
        isChecking = true

        var request = URLRequest(url: Self.releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false

                // A completed request (success or definitive failure) updates the
                // auto-check throttle timestamp; a transport error leaves it so the
                // next launch can retry sooner.
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let transportOK = error == nil && UpdateCheck.isSuccessful(status: status)
                if transportOK {
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastAutoCheckDefaultsKey)
                }

                guard transportOK,
                      let data,
                      let release = try? JSONDecoder().decode(Release.self, from: data) else {
                    if !silent {
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = "Couldn't check for updates"
                        alert.informativeText = error == nil
                            ? "GitHub returned an unexpected response (HTTP \(status)). Try again later."
                            : "Couldn't reach GitHub. Check your internet connection and try again."
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                    return
                }

                let current = self.currentVersion
                if UpdateCheck.isNewer(release.tag_name, than: current) {
                    self.promptToUpdate(to: SemVer.parse(release.tag_name).map { "\($0.major).\($0.minor).\($0.patch)" } ?? release.tag_name,
                                        url: release.html_url)
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
        // Only ever hand an HTTPS github.com URL to the browser; a tampered
        // html_url falls back to the known-good releases page.
        let destination = UpdateCheck.approvedReleaseURL(url) ?? Self.releasesPageURL

        let alert = NSAlert()
        alert.messageText = "Shorkut \(version) is available"
        alert.informativeText = "You're running \(currentVersion). Download the new version from GitHub?"
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(destination)
    }
}
