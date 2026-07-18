import XCTest
@testable import ShorkutCore

final class StateFileStoreTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("shorkut-state-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func store() -> StateFileStore<PersistentState> {
        StateFileStore(fileURL: dir.appendingPathComponent("state.json"))
    }

    private func sampleState(label: String = "Deploy") -> PersistentState {
        let section = ShortcutSection(name: "Work")
        let shortcut = ScriptShortcut(label: label, scriptPath: "/x/a.sh", sectionId: section.id, kind: .script)
        let tile = TileConfig(id: primaryTileID, name: "Tile 1", sectionIds: nil)
        return PersistentState(sections: [section], shortcuts: [shortcut], tiles: [tile])
    }

    // MARK: - Round trip

    func testRoundTrip() {
        let s = store()
        let state = sampleState()
        XCTAssertNoThrow(try s.save(state).get())
        guard case let .loaded(loaded) = s.load() else { return XCTFail("expected loaded") }
        XCTAssertEqual(loaded, state)
    }

    func testEmptyWhenNothingSaved() {
        guard case .empty = store().load() else { return XCTFail("expected empty") }
    }

    // MARK: - Backup recovery

    func testBackupRecoveryAfterMainCorrupted() throws {
        let s = store()
        let v1 = sampleState(label: "v1")
        try s.save(v1).get()
        let v2 = sampleState(label: "v2")
        try s.save(v2).get()   // backup now holds v1, main holds v2

        // Corrupt the main file.
        try Data("{ not json".utf8).write(to: s.fileURL)

        guard case let .recoveredFromBackup(recovered) = s.load() else {
            return XCTFail("expected recoveredFromBackup")
        }
        XCTAssertEqual(recovered, v1)
    }

    // MARK: - Corrupt with no backup

    func testCorruptWithNoBackupReported() throws {
        let s = store()
        try Data("garbage".utf8).write(to: s.fileURL)
        guard case .corrupt = s.load() else { return XCTFail("expected corrupt") }
    }

    func testQuarantinePreservesCorruptFile() throws {
        let s = store()
        try Data("garbage".utf8).write(to: s.fileURL)
        let moved = s.quarantineCorruptFile()
        XCTAssertNotNil(moved)
        XCTAssertFalse(fm.fileExists(atPath: s.fileURL.path), "main file moved aside")
        XCTAssertTrue(fm.fileExists(atPath: moved!.path), "corrupt data preserved for recovery")
    }

    // MARK: - Failed write

    func testFailedWriteReturnsFailure() {
        // Point the store at a path whose parent is a regular file, so directory
        // creation and the write must fail.
        let blocker = dir.appendingPathComponent("blocker")
        try? Data("x".utf8).write(to: blocker)
        let s = StateFileStore<PersistentState>(fileURL: blocker.appendingPathComponent("nested/state.json"))
        if case .success = s.save(sampleState()) {
            XCTFail("expected a write failure when the parent path is a file")
        }
    }
}
