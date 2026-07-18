import Foundation

/// Pure validation for `.shorkut` import files: schema version, item-count and
/// field-length limits, per-item field validation, and the capped "skipped"
/// summary text. Kept free of AppKit/filesystem so it can be exhaustively
/// unit-tested; the app layer adds the environment-dependent checks (is the app
/// installed, write the script file) after an item passes here.
public enum ImportValidation {
    public static let supportedVersion = 1
    public static let maxItems = 500
    public static let maxLabelLength = 200
    public static let maxSectionNameLength = 100
    public static let maxURLLength = 2048
    public static let maxBundleIdentifierLength = 256
    public static let maxSkippedNamesShown = 10

    public enum SchemaError: Error, Equatable {
        /// No `version` field present (or it decoded to nil).
        case missingVersion
        /// Present but not the supported version (0, negative, or a future version).
        case unsupportedVersion(Int)
        case tooManyItems(count: Int, limit: Int)

        public var message: String {
            switch self {
            case .missingVersion:
                return "This file doesn't declare a Shorkut format version, so it can't be trusted."
            case .unsupportedVersion(let v):
                return "This file is Shorkut format version \(v), which this app doesn't support (expected \(supportedVersion))."
            case .tooManyItems(let count, let limit):
                return "This file contains \(count) shortcuts, more than the \(limit) Shorkut will import at once."
            }
        }
    }

    public enum Rejection: Error, Equatable {
        case emptyLabel
        case labelTooLong
        case sectionNameTooLong
        case unknownKind
        case scriptMissing
        case scriptTooLarge
        case bundleIdentifierMissing
        case bundleIdentifierTooLong
        case urlMissing
        case urlInvalid
        case urlTooLong
        case duplicateInFile
    }

    /// The raw fields decoded from one item, before validation.
    public struct RawItem: Equatable {
        public let label: String
        public let kind: String
        public let sectionName: String
        public let scriptContent: String?
        public let bundleIdentifier: String?

        public init(label: String, kind: String, sectionName: String, scriptContent: String?, bundleIdentifier: String?) {
            self.label = label
            self.kind = kind
            self.sectionName = sectionName
            self.scriptContent = scriptContent
            self.bundleIdentifier = bundleIdentifier
        }
    }

    /// A fully-validated, normalized item ready for the app layer to commit.
    public struct NormalizedItem: Equatable {
        public let label: String
        public let kind: String
        public let sectionName: String
        public let scriptContent: String?  // .script
        public let url: String?            // .webpage (normalized)
        public let bundleIdentifier: String? // .app
    }

    /// Validates the top-level schema. `version` is optional so a *missing*
    /// field (nil) is distinguished from a present-but-wrong one.
    /// Returns nil if the schema is acceptable, else the reason it's rejected.
    public static func validateSchema(version: Int?, itemCount: Int) -> SchemaError? {
        guard let version else { return .missingVersion }
        guard version == supportedVersion else { return .unsupportedVersion(version) }
        guard itemCount <= maxItems else { return .tooManyItems(count: itemCount, limit: maxItems) }
        return nil
    }

    /// Validates and normalizes a single item's fields (everything that doesn't
    /// require the filesystem or NSWorkspace). Section is NOT created here.
    public static func validateItem(_ item: RawItem) -> Result<NormalizedItem, Rejection> {
        let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return .failure(Rejection.emptyLabel) }
        guard label.count <= maxLabelLength else { return .failure(Rejection.labelTooLong) }
        guard item.sectionName.count <= maxSectionNameLength else { return .failure(Rejection.sectionNameTooLong) }

        switch item.kind {
        case "script":
            guard let content = item.scriptContent, !content.isEmpty else { return .failure(Rejection.scriptMissing) }
            guard content.utf8.count <= Sanitization.maxScriptContentSize else { return .failure(Rejection.scriptTooLarge) }
            return .success(NormalizedItem(label: label, kind: item.kind, sectionName: item.sectionName,
                                           scriptContent: content, url: nil, bundleIdentifier: nil))

        case "app":
            guard let bundle = item.bundleIdentifier, !bundle.isEmpty else { return .failure(Rejection.bundleIdentifierMissing) }
            guard bundle.count <= maxBundleIdentifierLength else { return .failure(Rejection.bundleIdentifierTooLong) }
            return .success(NormalizedItem(label: label, kind: item.kind, sectionName: item.sectionName,
                                           scriptContent: nil, url: nil, bundleIdentifier: bundle))

        case "webpage":
            guard let raw = item.scriptContent, !raw.isEmpty else { return .failure(Rejection.urlMissing) }
            guard raw.count <= maxURLLength else { return .failure(Rejection.urlTooLong) }
            guard let normalized = Sanitization.normalizedWebpageURL(raw) else { return .failure(Rejection.urlInvalid) }
            return .success(NormalizedItem(label: label, kind: item.kind, sectionName: item.sectionName,
                                           scriptContent: nil, url: normalized, bundleIdentifier: nil))

        default:
            return .failure(Rejection.unknownKind)
        }
    }

    /// Identity used for in-file duplicate detection. Two items that would
    /// produce the same shortcut are considered duplicates.
    public static func duplicateKey(_ item: NormalizedItem) -> String {
        [item.kind, item.sectionName, item.label,
         item.scriptContent ?? "", item.url ?? "", item.bundleIdentifier ?? ""].joined(separator: "\u{1f}")
    }

    /// Capped, human-readable list of skipped names: shows up to
    /// `maxSkippedNamesShown` then "and N more".
    public static func skippedSummary(_ names: [String], max: Int = maxSkippedNamesShown) -> String {
        guard !names.isEmpty else { return "" }
        let shown = Array(names.prefix(max))
        var text = shown.joined(separator: ", ")
        let remaining = names.count - shown.count
        if remaining > 0 { text += " and \(remaining) more" }
        return text
    }
}
