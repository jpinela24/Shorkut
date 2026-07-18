import Foundation

/// A strictly-parsed semantic version. Unlike the old `split(".").compactMap(Int.init)`
/// approach — which silently dropped non-numeric components (so "1.x.0" compared
/// as "1.0") — parsing fails outright on any malformed component.
public struct SemVer: Equatable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// nil = a normal release; non-nil = a prerelease (e.g. "beta.1").
    public let prerelease: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Parses `MAJOR.MINOR.PATCH` with an optional leading `v` and optional
    /// `-prerelease` suffix. All three core components must be present and be
    /// non-negative integers, or parsing returns nil.
    public static func parse(_ raw: String) -> SemVer? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }

        var prerelease: String? = nil
        if let dash = text.firstIndex(of: "-") {
            let pre = String(text[text.index(after: dash)...])
            guard !pre.isEmpty else { return nil }
            prerelease = pre
            text = String(text[..<dash])
        }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let major = intComponent(parts[0]),
              let minor = intComponent(parts[1]),
              let patch = intComponent(parts[2]) else { return nil }
        return SemVer(major: major, minor: minor, patch: patch, prerelease: prerelease)
    }

    /// Strict non-negative integer: rejects "", "1a", "-1", "+2".
    private static func intComponent(_ s: Substring) -> Int? {
        guard !s.isEmpty, s.allSatisfy({ $0.isNumber }), let v = Int(s) else { return nil }
        return v
    }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _?):  return false   // a release outranks a same-core prerelease
        case (_?, nil):  return true
        case let (l?, r?): return l < r
        }
    }
}

/// Pure helpers for the GitHub update check — separated from AppKit so the
/// version/URL/HTTP-status logic is unit-testable.
public enum UpdateCheck {
    /// Hosts we're willing to hand to the browser for a release page.
    public static let approvedReleaseHosts: Set<String> = ["github.com", "www.github.com"]

    /// True only for a 2xx HTTP status.
    public static func isSuccessful(status code: Int) -> Bool {
        (200..<300).contains(code)
    }

    /// A newer version is offered only when `candidateTag` parses, is NOT a
    /// prerelease (we never auto-offer prereleases), and strictly exceeds the
    /// current version. Malformed tags never trigger a prompt.
    public static func isNewer(_ candidateTag: String, than currentTag: String) -> Bool {
        guard let candidate = SemVer.parse(candidateTag),
              let current = SemVer.parse(currentTag),
              candidate.prerelease == nil else { return false }
        return current < candidate
    }

    /// Returns the URL only if it's HTTPS and points at an approved GitHub host,
    /// so a tampered `html_url` in the API response can't redirect the user
    /// somewhere hostile.
    public static func approvedReleaseURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              approvedReleaseHosts.contains(host) else { return nil }
        return url
    }
}
