import XCTest
@testable import ShorkutCore

final class AppRestartTests: XCTestCase {
    private struct DummyError: Error {}

    func testLaunchedWithoutErrorTerminatesSelf() {
        XCTAssertEqual(AppRestart.outcome(launchedAppExists: true, error: nil), .relaunchedTerminateSelf)
    }

    func testLaunchFailedWithErrorKeepsRunning() {
        XCTAssertEqual(AppRestart.outcome(launchedAppExists: false, error: DummyError()), .failedKeepRunning)
    }

    func testNoErrorButNoAppKeepsRunning() {
        XCTAssertEqual(AppRestart.outcome(launchedAppExists: false, error: nil), .failedKeepRunning)
    }

    func testErrorEvenWithAppKeepsRunning() {
        XCTAssertEqual(AppRestart.outcome(launchedAppExists: true, error: DummyError()), .failedKeepRunning)
    }
}
