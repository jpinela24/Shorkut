import XCTest
@testable import ShorkutCore

final class StateMigrationTests: XCTestCase {
    private let encoder = JSONEncoder()

    func testMigratesSectionsShortcutsAndTiles() throws {
        let section = ShortcutSection(name: "Homelab")
        let shortcut = ScriptShortcut(label: "SSH", scriptPath: "/x/ssh.sh", sectionId: section.id, kind: .script)
        let tile = TileConfig(id: "t1", name: "Tile 1", sectionIds: nil)

        let state = StateMigration.migrate(
            sectionsJSON: try encoder.encode([section]),
            shortcutsJSON: try encoder.encode([shortcut]),
            tilesJSON: try encoder.encode([tile]),
            legacyTileIDs: nil
        )
        XCTAssertEqual(state.sections, [section])
        XCTAssertEqual(state.shortcuts, [shortcut])
        XCTAssertEqual(state.tiles, [tile])
    }

    func testMigratesLegacyTileIDsWhenNoTileConfig() {
        let state = StateMigration.migrate(
            sectionsJSON: nil, shortcutsJSON: nil, tilesJSON: nil,
            legacyTileIDs: ["primary", "abc"]
        )
        XCTAssertEqual(state.tiles.map { $0.id }, ["primary", "abc"])
        XCTAssertEqual(state.tiles.map { $0.name }, ["Tile 1", "Tile 2"])
    }

    func testDefaultsWhenEverythingEmpty() {
        let state = StateMigration.migrate(sectionsJSON: nil, shortcutsJSON: nil, tilesJSON: nil, legacyTileIDs: nil)
        XCTAssertEqual(state.sections.map { $0.name }, ["General"])
        XCTAssertEqual(state.tiles.map { $0.id }, [primaryTileID])
        XCTAssertTrue(state.shortcuts.isEmpty)
    }

    func testIgnoresCorruptLegacyBlobsAndFallsBackToDefaults() {
        let garbage = Data("not json".utf8)
        let state = StateMigration.migrate(
            sectionsJSON: garbage, shortcutsJSON: garbage, tilesJSON: garbage, legacyTileIDs: nil
        )
        XCTAssertEqual(state.sections.map { $0.name }, ["General"])
        XCTAssertTrue(state.shortcuts.isEmpty)
        XCTAssertEqual(state.tiles.map { $0.id }, [primaryTileID])
    }

    // Migration is idempotent at the store level: once a state file exists the
    // app loads it directly. Here we assert migrate() is a pure function of its
    // inputs (same inputs → identical output).
    func testMigrateIsDeterministic() throws {
        let section = ShortcutSection(name: "A")
        let s1 = StateMigration.migrate(sectionsJSON: try encoder.encode([section]), shortcutsJSON: nil, tilesJSON: nil, legacyTileIDs: nil)
        let s2 = StateMigration.migrate(sectionsJSON: try encoder.encode([section]), shortcutsJSON: nil, tilesJSON: nil, legacyTileIDs: nil)
        XCTAssertEqual(s1, s2)
    }
}
