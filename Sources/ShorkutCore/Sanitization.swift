import Foundation

/// Pure, UI-free helpers for turning untrusted strings (shortcut labels, URLs,
/// imported filenames) into safe on-disk filenames and validated web URLs.
/// Kept dependency-free (Foundation only) so they're unit-testable without
/// pulling in AppKit.
public enum Sanitization {
    /// Maximum size accepted for a single imported `.shorkut` bundle.
    public static let maxImportFileSize = 5 * 1024 * 1024
    /// Maximum size accepted for a single script's content, whether imported
    /// or generated from a template.
    public static let maxScriptContentSize = 1 * 1024 * 1024

    /// Produces a filesystem-safe base name (no extension) from an arbitrary
    /// label: keeps only alphanumerics, spaces, dots, dashes, and underscores,
    /// collapses whitespace runs, strips leading dots (so it can't resolve to
    /// "." or ".." or become an unexpectedly hidden file), and falls back to
    /// `fallback` if nothing usable remains.
    public static func safeFilenameBase(from label: String, fallback: String = "Shortcut") -> String {
        let collapsedWhitespace = label.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )

        var allowed = CharacterSet.alphanumerics
        allowed.formUnion(CharacterSet(charactersIn: " ._-"))

        let scalars = collapsedWhitespace.unicodeScalars.filter { allowed.contains($0) }
        var result = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)

        while result.hasPrefix(".") {
            result.removeFirst()
        }

        return result.isEmpty ? fallback : String(result.prefix(80))
    }

    /// Builds a destination URL for an imported/generated script inside
    /// `directory`. Guarantees the final, standardized path still resolves
    /// inside `directory` — a defense-in-depth check in case a future
    /// sanitizer gap ever let `..` or an absolute path slip through.
    public static func scriptDestinationURL(
        forLabel label: String,
        extension ext: String = "sh",
        in directory: URL,
        suffix: String = String(UUID().uuidString.prefix(6))
    ) -> URL? {
        let base = safeFilenameBase(from: label)
        let filename = "\(base)-\(suffix).\(ext)"
        let directory = directory.standardizedFileURL
        let destination = directory.appendingPathComponent(filename).standardizedFileURL
        guard destination.path.hasPrefix(directory.path + "/") else { return nil }
        return destination
    }

    /// Normalizes a user-entered web address: adds `https://` if no scheme
    /// was given, then only accepts `http`/`https` with a non-empty host —
    /// anything else (`javascript:`, `file:`, a custom scheme, a bare scheme
    /// with no host) is rejected outright rather than silently passed through
    /// to `NSWorkspace.open`.
    public static func normalizedWebpageURL(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Only treat it as scheme-less (and prepend https://) if there's no
        // scheme at all — otherwise something like "myapp://x" or "file:///x"
        // would get "https://" tacked on front and re-parse as a (bogus)
        // https URL instead of being rejected for using the wrong scheme.
        let hasScheme = trimmed.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*:", options: .regularExpression) != nil
        let candidate = hasScheme ? trimmed : "https://" + trimmed

        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return candidate
    }
}
