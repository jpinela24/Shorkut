import XCTest
@testable import ShorkutCore

final class TerminalLaunchTests: XCTestCase {

    // MARK: - shellQuoted

    func testShellQuotedWrapsPlainPath() {
        XCTAssertEqual(TerminalLaunch.shellQuoted("/tmp/a.sh"), "'/tmp/a.sh'")
    }

    func testShellQuotedNeutralizesSpaces() {
        XCTAssertEqual(TerminalLaunch.shellQuoted("/tmp/my script.sh"), "'/tmp/my script.sh'")
    }

    func testShellQuotedEscapesEmbeddedSingleQuote() {
        // close-quote, escaped quote, reopen-quote
        XCTAssertEqual(TerminalLaunch.shellQuoted("/tmp/it's.sh"), "'/tmp/it'\\''s.sh'")
    }

    func testShellQuotedNeutralizesDangerousMetacharacters() {
        // $ ` ; & | all stay literal inside single quotes
        let path = "/tmp/$(rm -rf ~)`whoami`;evil&.sh"
        let quoted = TerminalLaunch.shellQuoted(path)
        XCTAssertTrue(quoted.hasPrefix("'"))
        XCTAssertTrue(quoted.hasSuffix("'"))
        // The only way to break out is an unescaped single quote; there are none here.
        XCTAssertFalse(quoted.dropFirst().dropLast().contains("'"))
    }

    // MARK: - appleScriptEscaped

    func testAppleScriptEscapesBackslashAndQuote() {
        XCTAssertEqual(TerminalLaunch.appleScriptEscaped("a\\b\"c"), "a\\\\b\\\"c")
    }

    func testAppleScriptSafePathOrdersEscapingCorrectly() {
        // Shell-quote first, then AppleScript-escape the result: the wrapping
        // single quotes survive, and any embedded backslash/quote is escaped.
        let path = "/tmp/a\"b.sh"
        let safe = TerminalLaunch.appleScriptSafePath(path)
        // shellQuoted => '/tmp/a"b.sh' ; appleScriptEscaped escapes the "
        XCTAssertEqual(safe, "'/tmp/a\\\"b.sh'")
    }

    // MARK: - AppleScript plans (Terminal / iTerm)

    func testTerminalRunningPlanEmbedsQuotedPath() {
        let plan = TerminalLaunch.plan(for: .terminal, scriptPath: "/tmp/a b.sh", alreadyRunning: true)
        guard case let .appleScript(src) = plan else { return XCTFail("expected appleScript") }
        XCTAssertTrue(src.contains("do script \"'/tmp/a b.sh'\""))
        XCTAssertFalse(src.contains("delay"))
    }

    func testTerminalColdLaunchUsesFrontWindow() {
        let plan = TerminalLaunch.plan(for: .terminal, scriptPath: "/tmp/a.sh", alreadyRunning: false)
        guard case let .appleScript(src) = plan else { return XCTFail("expected appleScript") }
        XCTAssertTrue(src.contains("in front window"))
        XCTAssertTrue(src.contains("delay 0.6"))
    }

    func testITermPlanWritesQuotedPath() {
        let plan = TerminalLaunch.plan(for: .iterm, scriptPath: "/tmp/x;y.sh", alreadyRunning: true)
        guard case let .appleScript(src) = plan else { return XCTFail("expected appleScript") }
        XCTAssertTrue(src.contains("write text \"'/tmp/x;y.sh'\""))
    }

    func testAdversarialPathCannotBreakOutOfAppleScriptLiteral() {
        // A path trying to close the AppleScript string and inject a command.
        let evil = "/tmp/\"; do shell script \"rm -rf ~\" --.sh"
        let plan = TerminalLaunch.plan(for: .terminal, scriptPath: evil, alreadyRunning: true)
        guard case let .appleScript(src) = plan else { return XCTFail("expected appleScript") }
        // The injected double-quote must be escaped (\") so the literal never closes early.
        XCTAssertTrue(src.contains("\\\""))
        // The path is single-quoted for the shell, so the embedded do-shell-script is inert text.
        XCTAssertTrue(src.contains("'/tmp/"))
    }

    // MARK: - openArgs plans (Alacritty / kitty) — argv, never a shell string

    func testAlacrittyPlanPassesPathAsSeparateArgv() {
        let plan = TerminalLaunch.plan(for: .alacritty, scriptPath: "/tmp/my $cript;rm.sh", alreadyRunning: false)
        XCTAssertEqual(plan, .openArgs(appName: "Alacritty", args: ["-e", "/tmp/my $cript;rm.sh"]))
    }

    func testKittyPlanPassesPathAsSeparateArgv() {
        let plan = TerminalLaunch.plan(for: .kitty, scriptPath: "/tmp/`whoami`.sh", alreadyRunning: false)
        XCTAssertEqual(plan, .openArgs(appName: "kitty", args: ["/tmp/`whoami`.sh"]))
    }

    func testOpenArgsPathIsUnmodifiedForArgvSafety() {
        // Because these go through an argv array, the path must be delivered
        // byte-for-byte with NO quoting added (quoting would corrupt the arg).
        let path = "/tmp/a'b\"c d.sh"
        let plan = TerminalLaunch.plan(for: .kitty, scriptPath: path, alreadyRunning: false)
        guard case let .openArgs(_, args) = plan else { return XCTFail("expected openArgs") }
        XCTAssertEqual(args.last, path)
    }

    // MARK: - Only supported terminals exist

    func testWarpAndHyperAreNotSelectable() {
        let ids = Set(TerminalLaunch.Target.allCases.map { $0.rawValue })
        XCTAssertEqual(ids, ["terminal", "iterm", "alacritty", "kitty"])
    }
}
