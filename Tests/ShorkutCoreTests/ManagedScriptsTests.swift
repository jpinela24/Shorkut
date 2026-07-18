import XCTest
@testable import ShorkutCore

final class ManagedScriptsTests: XCTestCase {

    private var root: URL!
    private var managed: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("shorkut-managed-\(UUID().uuidString)")
        managed = root.appendingPathComponent("Scripts", isDirectory: true)
        try fm.createDirectory(at: managed, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    @discardableResult
    private func makeFile(_ url: URL, contents: String = "#!/bin/sh\necho hi\n") throws -> URL {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Pure containment

    func testIsContainedRejectsPrefixCollisionSibling() {
        XCTAssertFalse(ManagedScripts.isContained("/x/Scripts-evil/a.sh", in: "/x/Scripts"))
        XCTAssertTrue(ManagedScripts.isContained("/x/Scripts/a.sh", in: "/x/Scripts"))
    }

    func testIsContainedRejectsTheDirectoryItself() {
        XCTAssertFalse(ManagedScripts.isContained("/x/Scripts", in: "/x/Scripts"))
    }

    // MARK: - Happy path

    func testDeletesRegularFileInsideManagedDirectory() throws {
        let file = try makeFile(managed.appendingPathComponent("hello.sh"))
        XCTAssertEqual(ManagedScripts.deleteIfManaged(path: file.path, directory: managed), .deleted)
        XCTAssertFalse(fm.fileExists(atPath: file.path))
    }

    // MARK: - Traversal

    func testTraversalOutOfManagedDirectoryIsSkipped() throws {
        let outside = try makeFile(root.appendingPathComponent("victim.sh"))
        let traversal = managed.appendingPathComponent("../victim.sh").path
        XCTAssertEqual(
            ManagedScripts.deleteIfManaged(path: traversal, directory: managed),
            .skippedOutsideManagedDirectory
        )
        XCTAssertTrue(fm.fileExists(atPath: outside.path), "victim outside managed dir must survive")
    }

    // MARK: - External absolute path

    func testExternalAbsolutePathIsSkipped() throws {
        let outside = try makeFile(root.appendingPathComponent("elsewhere.sh"))
        XCTAssertEqual(
            ManagedScripts.deleteIfManaged(path: outside.path, directory: managed),
            .skippedOutsideManagedDirectory
        )
        XCTAssertTrue(fm.fileExists(atPath: outside.path))
    }

    // MARK: - Symlink final component pointing outside

    func testSymlinkInsideManagedDirPointingOutsideIsNotFollowed() throws {
        let victim = try makeFile(root.appendingPathComponent("secret.sh"))
        let link = managed.appendingPathComponent("link.sh")
        try fm.createSymbolicLink(at: link, withDestinationURL: victim)

        let result = ManagedScripts.deleteIfManaged(path: link.path, directory: managed)
        XCTAssertEqual(result, .skippedNotRegularFile, "a symlink is not a regular file")
        XCTAssertTrue(fm.fileExists(atPath: victim.path), "symlink target must never be deleted")
        // The symlink itself is left in place because we refuse to act on it.
    }

    // MARK: - Symlinked parent directory escaping

    func testSymlinkedParentEscapingManagedDirIsSkipped() throws {
        // managed/sub -> /root/real  ; deleting managed/sub/x.sh must resolve to
        // /root/real/x.sh, which is OUTSIDE managed, and be skipped.
        let realDir = root.appendingPathComponent("real", isDirectory: true)
        try fm.createDirectory(at: realDir, withIntermediateDirectories: true)
        let victim = try makeFile(realDir.appendingPathComponent("x.sh"))
        let linkedSub = managed.appendingPathComponent("sub")
        try fm.createSymbolicLink(at: linkedSub, withDestinationURL: realDir)

        let attempt = linkedSub.appendingPathComponent("x.sh").path
        XCTAssertEqual(
            ManagedScripts.deleteIfManaged(path: attempt, directory: managed),
            .skippedOutsideManagedDirectory
        )
        XCTAssertTrue(fm.fileExists(atPath: victim.path))
    }

    // MARK: - Non-regular targets

    func testDirectoryTargetIsSkipped() throws {
        let dir = managed.appendingPathComponent("adir", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertEqual(ManagedScripts.deleteIfManaged(path: dir.path, directory: managed), .skippedNotRegularFile)
        XCTAssertTrue(fm.fileExists(atPath: dir.path))
    }

    func testMissingFileIsSkipped() {
        let missing = managed.appendingPathComponent("nope.sh").path
        XCTAssertEqual(ManagedScripts.deleteIfManaged(path: missing, directory: managed), .skippedNotRegularFile)
    }

    func testEmptyPathIsSkipped() {
        XCTAssertEqual(ManagedScripts.deleteIfManaged(path: "", directory: managed), .skippedOutsideManagedDirectory)
    }
}
