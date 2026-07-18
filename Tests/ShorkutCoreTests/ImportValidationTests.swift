import XCTest
@testable import ShorkutCore

final class ImportValidationTests: XCTestCase {

    // MARK: - Schema version

    func testMissingVersionIsRejected() {
        XCTAssertEqual(ImportValidation.validateSchema(version: nil, itemCount: 1), .missingVersion)
    }

    func testZeroNegativeAndFutureVersionsRejected() {
        XCTAssertEqual(ImportValidation.validateSchema(version: 0, itemCount: 1), .unsupportedVersion(0))
        XCTAssertEqual(ImportValidation.validateSchema(version: -3, itemCount: 1), .unsupportedVersion(-3))
        XCTAssertEqual(ImportValidation.validateSchema(version: 2, itemCount: 1), .unsupportedVersion(2))
    }

    func testSupportedVersionAccepted() {
        XCTAssertNil(ImportValidation.validateSchema(version: 1, itemCount: 10))
    }

    func testTooManyItemsRejected() {
        let n = ImportValidation.maxItems + 1
        XCTAssertEqual(
            ImportValidation.validateSchema(version: 1, itemCount: n),
            .tooManyItems(count: n, limit: ImportValidation.maxItems)
        )
    }

    func testItemCountAtLimitAccepted() {
        XCTAssertNil(ImportValidation.validateSchema(version: 1, itemCount: ImportValidation.maxItems))
    }

    // MARK: - Field validation

    private func raw(_ label: String, _ kind: String, section: String = "General", script: String? = nil, bundle: String? = nil) -> ImportValidation.RawItem {
        .init(label: label, kind: kind, sectionName: section, scriptContent: script, bundleIdentifier: bundle)
    }

    func testEmptyLabelRejected() {
        XCTAssertEqual(ImportValidation.validateItem(raw("   ", "app", bundle: "com.x")), .failure(.emptyLabel))
    }

    func testLabelTooLongRejected() {
        let long = String(repeating: "a", count: ImportValidation.maxLabelLength + 1)
        XCTAssertEqual(ImportValidation.validateItem(raw(long, "app", bundle: "com.x")), .failure(.labelTooLong))
    }

    func testSectionNameTooLongRejected() {
        let long = String(repeating: "s", count: ImportValidation.maxSectionNameLength + 1)
        XCTAssertEqual(ImportValidation.validateItem(raw("ok", "app", section: long, bundle: "com.x")), .failure(.sectionNameTooLong))
    }

    func testUnknownKindRejected() {
        XCTAssertEqual(ImportValidation.validateItem(raw("ok", "wormhole")), .failure(.unknownKind))
    }

    func testScriptMissingRejected() {
        XCTAssertEqual(ImportValidation.validateItem(raw("s", "script", script: nil)), .failure(.scriptMissing))
        XCTAssertEqual(ImportValidation.validateItem(raw("s", "script", script: "")), .failure(.scriptMissing))
    }

    func testScriptTooLargeRejected() {
        let big = String(repeating: "x", count: Sanitization.maxScriptContentSize + 1)
        XCTAssertEqual(ImportValidation.validateItem(raw("s", "script", script: big)), .failure(.scriptTooLarge))
    }

    func testValidScriptNormalizes() {
        let result = ImportValidation.validateItem(raw("  Deploy  ", "script", script: "#!/bin/sh"))
        guard case let .success(item) = result else { return XCTFail() }
        XCTAssertEqual(item.label, "Deploy")   // trimmed
        XCTAssertEqual(item.scriptContent, "#!/bin/sh")
    }

    func testAppBundleMissingRejected() {
        XCTAssertEqual(ImportValidation.validateItem(raw("a", "app", bundle: nil)), .failure(.bundleIdentifierMissing))
    }

    func testBundleIdentifierTooLongRejected() {
        let long = String(repeating: "b", count: ImportValidation.maxBundleIdentifierLength + 1)
        XCTAssertEqual(ImportValidation.validateItem(raw("a", "app", bundle: long)), .failure(.bundleIdentifierTooLong))
    }

    func testWebpageInvalidRejected() {
        XCTAssertEqual(ImportValidation.validateItem(raw("w", "webpage", script: "javascript:alert(1)")), .failure(.urlInvalid))
        XCTAssertEqual(ImportValidation.validateItem(raw("w", "webpage", script: nil)), .failure(.urlMissing))
    }

    func testWebpageTooLongRejected() {
        let long = "https://x.com/" + String(repeating: "a", count: ImportValidation.maxURLLength)
        XCTAssertEqual(ImportValidation.validateItem(raw("w", "webpage", script: long)), .failure(.urlTooLong))
    }

    func testValidWebpageNormalizesScheme() {
        let result = ImportValidation.validateItem(raw("w", "webpage", script: "example.com"))
        guard case let .success(item) = result else { return XCTFail() }
        XCTAssertEqual(item.url, "https://example.com")
    }

    // MARK: - Duplicate key + skipped summary

    func testDuplicateKeyMatchesEquivalentItems() {
        let a = ImportValidation.validateItem(raw("Site", "webpage", script: "example.com"))
        let b = ImportValidation.validateItem(raw("Site", "webpage", script: "https://example.com"))
        guard case let .success(ai) = a, case let .success(bi) = b else { return XCTFail() }
        XCTAssertEqual(ImportValidation.duplicateKey(ai), ImportValidation.duplicateKey(bi))
    }

    func testSkippedSummaryCapsAndCounts() {
        let names = (1...15).map { "item\($0)" }
        let summary = ImportValidation.skippedSummary(names, max: 10)
        XCTAssertTrue(summary.hasPrefix("item1, item2"))
        XCTAssertTrue(summary.hasSuffix("and 5 more"))
    }

    func testSkippedSummaryEmpty() {
        XCTAssertEqual(ImportValidation.skippedSummary([]), "")
    }
}
