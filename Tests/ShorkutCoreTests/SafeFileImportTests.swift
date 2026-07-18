import XCTest
@testable import ShorkutCore

final class SafeFileImportTests: XCTestCase {

    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("shorkut-import-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func write(_ name: String, bytes: Int) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    // MARK: - validateRegularFile

    func testValidatesRegularFileWithinLimit() throws {
        let f = try write("a.sh", bytes: 100)
        XCTAssertEqual(SafeFileImport.validateRegularFile(at: f.path, maxBytes: 1000), .success(100))
    }

    func testRejectsOversizedFile() throws {
        let f = try write("big.sh", bytes: 2000)
        XCTAssertEqual(SafeFileImport.validateRegularFile(at: f.path, maxBytes: 1000), .failure(.tooLarge(limit: 1000)))
    }

    func testRejectsUnreadableMetadataForMissingFile() {
        let missing = dir.appendingPathComponent("nope.sh").path
        XCTAssertEqual(SafeFileImport.validateRegularFile(at: missing, maxBytes: 1000), .failure(.metadataUnreadable))
    }

    func testRejectsDirectory() throws {
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        XCTAssertEqual(SafeFileImport.validateRegularFile(at: sub.path, maxBytes: 1000), .failure(.notRegularFile))
    }

    func testRejectsSymlink() throws {
        let real = try write("real.sh", bytes: 10)
        let link = dir.appendingPathComponent("link.sh")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertEqual(SafeFileImport.validateRegularFile(at: link.path, maxBytes: 1000), .failure(.notRegularFile))
    }

    // MARK: - boundedRead

    func testBoundedReadReturnsContents() throws {
        let f = try write("r.sh", bytes: 500)
        guard case let .success(data) = SafeFileImport.boundedRead(at: f, maxBytes: 1000) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(data.count, 500)
    }

    func testBoundedReadEnforcesLimitDuringRead() throws {
        let f = try write("r.sh", bytes: 5000)
        XCTAssertEqual(SafeFileImport.boundedRead(at: f, maxBytes: 1000), .failure(.tooLarge(limit: 1000)))
    }

    func testBoundedReadRejectsSymlink() throws {
        let real = try write("real.sh", bytes: 10)
        let link = dir.appendingPathComponent("l.sh")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertEqual(SafeFileImport.boundedRead(at: link, maxBytes: 1000), .failure(.notRegularFile))
    }

    // MARK: - streamCopy

    func testStreamCopyCopiesWithinLimit() throws {
        let src = try write("src.sh", bytes: 300)
        let dst = dir.appendingPathComponent("dst.sh")
        XCTAssertEqual(SafeFileImport.streamCopy(from: src, to: dst, maxBytes: 1000), .success(300))
        XCTAssertEqual((try? Data(contentsOf: dst))?.count, 300)
    }

    func testStreamCopyRejectsOversizedAndLeavesNoPartialFile() throws {
        let src = try write("src.sh", bytes: 5000)
        let dst = dir.appendingPathComponent("dst.sh")
        XCTAssertEqual(SafeFileImport.streamCopy(from: src, to: dst, maxBytes: 1000), .failure(.tooLarge(limit: 1000)))
        XCTAssertFalse(fm.fileExists(atPath: dst.path), "partial destination must be cleaned up")
    }

    func testStreamCopyRejectsSymlinkSource() throws {
        let real = try write("real.sh", bytes: 10)
        let link = dir.appendingPathComponent("l.sh")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
        let dst = dir.appendingPathComponent("dst.sh")
        XCTAssertEqual(SafeFileImport.streamCopy(from: link, to: dst, maxBytes: 1000), .failure(.notRegularFile))
        XCTAssertFalse(fm.fileExists(atPath: dst.path))
    }

    func testStreamCopyRejectsMissingSource() {
        let missing = dir.appendingPathComponent("missing.sh")
        let dst = dir.appendingPathComponent("dst.sh")
        XCTAssertEqual(SafeFileImport.streamCopy(from: missing, to: dst, maxBytes: 1000), .failure(.metadataUnreadable))
    }
}
