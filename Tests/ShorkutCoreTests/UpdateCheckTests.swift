import XCTest
@testable import ShorkutCore

final class UpdateCheckTests: XCTestCase {

    // MARK: - SemVer parsing (strict)

    func testParsesPlainAndVPrefixed() {
        XCTAssertEqual(SemVer.parse("1.2.3"), SemVer(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(SemVer.parse("v1.2.3"), SemVer(major: 1, minor: 2, patch: 3))
    }

    func testParsesPrerelease() {
        XCTAssertEqual(SemVer.parse("v2.0.0-beta.1"), SemVer(major: 2, minor: 0, patch: 0, prerelease: "beta.1"))
    }

    func testRejectsMalformedComponentsInsteadOfDropping() {
        // The old compactMap would turn "1.x.0" into [1,0] == 1.0.0; strict parse rejects it.
        XCTAssertNil(SemVer.parse("1.x.0"))
        XCTAssertNil(SemVer.parse("1.2"))
        XCTAssertNil(SemVer.parse("1.2.3.4"))
        XCTAssertNil(SemVer.parse(""))
        XCTAssertNil(SemVer.parse("v"))
        XCTAssertNil(SemVer.parse("1..3"))
        XCTAssertNil(SemVer.parse("1.2.-3"))
        XCTAssertNil(SemVer.parse("1.2.3-"))
    }

    // MARK: - Comparison

    func testNumericComparisonNotLexical() {
        XCTAssertTrue(UpdateCheck.isNewer("1.10.0", than: "1.9.0"))
        XCTAssertFalse(UpdateCheck.isNewer("1.9.0", than: "1.10.0"))
    }

    func testEqualIsNotNewer() {
        XCTAssertFalse(UpdateCheck.isNewer("1.2.3", than: "1.2.3"))
        XCTAssertFalse(UpdateCheck.isNewer("v1.2.3", than: "1.2.3"))
    }

    func testPrereleaseCandidateNeverOffered() {
        // Even a higher-core prerelease is not auto-offered.
        XCTAssertFalse(UpdateCheck.isNewer("2.0.0-beta", than: "1.0.0"))
        XCTAssertFalse(UpdateCheck.isNewer("1.2.4-rc.1", than: "1.2.3"))
    }

    func testReleaseNewerThanSameCorePrereleaseCurrent() {
        XCTAssertTrue(UpdateCheck.isNewer("2.0.0", than: "2.0.0-beta"))
    }

    func testMalformedTagsNeverTriggerUpdate() {
        XCTAssertFalse(UpdateCheck.isNewer("garbage", than: "1.0.0"))
        XCTAssertFalse(UpdateCheck.isNewer("1.2.3", than: "not-a-version"))
    }

    // MARK: - HTTP status

    func testStatusSuccessRange() {
        XCTAssertTrue(UpdateCheck.isSuccessful(status: 200))
        XCTAssertTrue(UpdateCheck.isSuccessful(status: 204))
        XCTAssertFalse(UpdateCheck.isSuccessful(status: 301))
        XCTAssertFalse(UpdateCheck.isSuccessful(status: 404))
        XCTAssertFalse(UpdateCheck.isSuccessful(status: 500))
    }

    // MARK: - URL validation

    func testApprovedReleaseURLAcceptsGitHubHTTPS() {
        XCTAssertNotNil(UpdateCheck.approvedReleaseURL("https://github.com/jpinela24/Shorkut/releases/tag/v1.2.0"))
        XCTAssertNotNil(UpdateCheck.approvedReleaseURL("https://www.github.com/x/y/releases"))
    }

    func testApprovedReleaseURLRejectsNonHTTPSorForeignHost() {
        XCTAssertNil(UpdateCheck.approvedReleaseURL("http://github.com/x"))         // not https
        XCTAssertNil(UpdateCheck.approvedReleaseURL("https://evil.example.com/x"))   // foreign host
        XCTAssertNil(UpdateCheck.approvedReleaseURL("https://github.com.evil.com/x"))// look-alike host
        XCTAssertNil(UpdateCheck.approvedReleaseURL("javascript:alert(1)"))
        XCTAssertNil(UpdateCheck.approvedReleaseURL(""))
    }
}
