import Foundation

/// Foundation-only data model shared by the app and the persistence layer.
/// Kept in ShorkutCore (no AppKit) so persistence and migration are unit-testable.

/// The id of the very first tile, which keeps the original unsuffixed defaults
/// key so upgrading from a single-tile version doesn't lose its position.
public let primaryTileID = "primary"

public struct ShortcutSection: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public enum ShortcutKind: String, Codable {
    case script
    case app
    case webpage
}

public struct ScriptShortcut: Identifiable, Codable {
    public let id: UUID
    public var label: String
    public var scriptPath: String
    public var sectionId: UUID
    public var kind: ShortcutKind
    public var customIcon: String?
    public var customColorHex: String?
    /// True for scripts whose content arrived via a .shorkut import (not chosen
    /// directly by the user via a file picker). Gates a one-time trust prompt.
    public var needsTrustConfirmation: Bool

    public init(id: UUID = UUID(), label: String, scriptPath: String, sectionId: UUID, kind: ShortcutKind = .script, customIcon: String? = nil, customColorHex: String? = nil, needsTrustConfirmation: Bool = false) {
        self.id = id
        self.label = label
        self.scriptPath = scriptPath
        self.sectionId = sectionId
        self.kind = kind
        self.customIcon = customIcon
        self.customColorHex = customColorHex
        self.needsTrustConfirmation = needsTrustConfirmation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        scriptPath = try container.decode(String.self, forKey: .scriptPath)
        sectionId = try container.decode(UUID.self, forKey: .sectionId)
        kind = try container.decodeIfPresent(ShortcutKind.self, forKey: .kind) ?? .script
        customIcon = try container.decodeIfPresent(String.self, forKey: .customIcon)
        customColorHex = try container.decodeIfPresent(String.self, forKey: .customColorHex)
        needsTrustConfirmation = try container.decodeIfPresent(Bool.self, forKey: .needsTrustConfirmation) ?? false
    }
}

/// Per-tile configuration: which desktop tile windows exist and what each shows.
/// `sectionIds == nil` means "mirror everything" (the default); a non-nil set
/// makes the tile independent, showing only those sections.
public struct TileConfig: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var sectionIds: Set<UUID>?

    public init(id: String, name: String, sectionIds: Set<UUID>? = nil) {
        self.id = id
        self.name = name
        self.sectionIds = sectionIds
    }
}

/// The full user-authored state that moves out of UserDefaults into an
/// atomically-written state file.
public struct PersistentState: Codable, Equatable {
    public var sections: [ShortcutSection]
    public var shortcuts: [ScriptShortcut]
    public var tiles: [TileConfig]

    public init(sections: [ShortcutSection], shortcuts: [ScriptShortcut], tiles: [TileConfig]) {
        self.sections = sections
        self.shortcuts = shortcuts
        self.tiles = tiles
    }
}

extension ScriptShortcut: Equatable {
    public static func == (lhs: ScriptShortcut, rhs: ScriptShortcut) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.scriptPath == rhs.scriptPath &&
        lhs.sectionId == rhs.sectionId && lhs.kind == rhs.kind &&
        lhs.customIcon == rhs.customIcon && lhs.customColorHex == rhs.customColorHex &&
        lhs.needsTrustConfirmation == rhs.needsTrustConfirmation
    }
}
