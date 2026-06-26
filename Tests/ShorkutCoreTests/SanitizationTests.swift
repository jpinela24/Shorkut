import XCTest
@testable import ShorkutCore

final class SanitizationTests: XCTestCase {

    // MARK: - safeFilenameBase

    func testPathTraversalIsStripped() {
        let result = Sanitization.safeFilenameBase(from: "../../evil")
        XCTAssertFalse(result.contains(".."))
        XCTAssertFalse(result.contains("/"))
    }

    func testPathSeparatorIsStripped() {
        let result = Sanitization.safeFilenameBase(from: "a/b")
        XCTAssertFalse(result.contains("/"))
        XCTAssertFalse(result.isEmpty)
    }

    func testEmptyLabelFallsBack() {
        XCTAssertEqual(Sanitization.safeFilenameBase(from: "", fallback: "Shortcut"), "Shortcut")
    }

    func testOnlyTraversalCharactersFallsBack() {
        // Once slashes and dots are stripped, "../.." resolves to nothing,
        // so it must fall back rather than producing an empty filename.
        XCTAssertEqual(Sanitization.safeFilenameBase(from: "../..", fallback: "Shortcut"), "Shortcut")
    }

    func testUnicodeAndControlCharactersAreStripped() {
        let result = Sanitization.safeFilenameBase(from: "My\u{0007}Script\u{202E}名前")
        XCTAssertFalse(result.contains("\u{0007}"))
        XCTAssertFalse(result.contains("\u{202E}"))
        XCTAssertTrue(result.contains("My"))
        XCTAssertTrue(result.contains("Script"))
    }

    func testLeadingDotsAreStripped() {
        let result = Sanitization.safeFilenameBase(from: "...hidden", fallback: "Shortcut")
        XCTAssertFalse(result.hasPrefix("."))
    }

    func testNormalLabelIsPreserved() {
        XCTAssertEqual(Sanitization.safeFilenameBase(from: "Restart Service"), "Restart Service")
    }

    func testWhitespaceRunsAreCollapsed() {
        XCTAssertEqual(Sanitization.safeFilenameBase(from: "Too   Many    Spaces"), "Too Many Spaces")
    }

    // MARK: - scriptDestinationURL

    func testScriptDestinationStaysInsideDirectory() {
        let directory = URL(fileURLWithPath: "/tmp/ShorkutTestScripts")
        let destination = Sanitization.scriptDestinationURL(forLabel: "../../evil", in: directory, suffix: "abc123")
        XCTAssertNotNil(destination)
        XCTAssertTrue(destination!.path.hasPrefix(directory.standardizedFileURL.path + "/"))
    }

    func testScriptDestinationUsesGivenExtension() {
        let directory = URL(fileURLWithPath: "/tmp/ShorkutTestScripts")
        let destination = Sanitization.scriptDestinationURL(forLabel: "Backup", extension: "py", in: directory, suffix: "abc123")
        XCTAssertEqual(destination?.pathExtension, "py")
    }

    // MARK: - normalizedWebpageURL

    func testPlainDomainGetsHTTPSScheme() {
        XCTAssertEqual(Sanitization.normalizedWebpageURL("example.com"), "https://example.com")
    }

    func testExistingHTTPSURLIsPreserved() {
        XCTAssertEqual(Sanitization.normalizedWebpageURL("https://example.com"), "https://example.com")
    }

    func testExistingHTTPURLIsPreserved() {
        XCTAssertEqual(Sanitization.normalizedWebpageURL("http://example.com"), "http://example.com")
    }

    func testJavascriptSchemeIsRejected() {
        XCTAssertNil(Sanitization.normalizedWebpageURL("javascript:alert(1)"))
    }

    func testFileSchemeIsRejected() {
        XCTAssertNil(Sanitization.normalizedWebpageURL("file:///etc/passwd"))
    }

    func testCustomSchemeIsRejected() {
        XCTAssertNil(Sanitization.normalizedWebpageURL("myapp://do-something"))
    }

    func testEmptyStringIsRejected() {
        XCTAssertNil(Sanitization.normalizedWebpageURL(""))
    }

    func testWhitespaceOnlyIsRejected() {
        XCTAssertNil(Sanitization.normalizedWebpageURL("   "))
    }

    func testSchemeWithNoHostIsRejected() {
        XCTAssertNil(Sanitization.normalizedWebpageURL("https://"))
    }
}
