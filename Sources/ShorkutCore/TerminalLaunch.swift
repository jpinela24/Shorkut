import Foundation

/// A fully-resolved description of how to launch a script in a terminal,
/// independent of AppKit so it can be unit-tested. The app layer turns a plan
/// into an actual `Process`; nothing here ever builds a shell string from a
/// user-controlled path without quoting it.
public enum TerminalLaunchPlan: Equatable {
    /// Run `osascript -e <source>`. The embedded path is single-quoted for the
    /// shell first, then escaped for the AppleScript string literal.
    case appleScript(String)
    /// Run `/usr/bin/open -n -a <appName> --args <args>`. Arguments are passed
    /// as an argv array (never concatenated into a shell command), so a path
    /// with spaces/quotes/`$`/backticks/`;` is delivered verbatim and unparsed.
    case openArgs(appName: String, args: [String])
}

public enum TerminalLaunch {
    /// The terminals Shorkut can actually *execute* a script in. Warp and Hyper
    /// were removed from the selector: neither exposes a reliable "run this
    /// command" mechanism, so advertising them meant silently opening a folder
    /// instead of running the shortcut.
    public enum Target: String, CaseIterable, Sendable {
        case terminal
        case iterm
        case alacritty
        case kitty
    }

    /// Wraps a path in single quotes for safe use as a single shell argument —
    /// neutralizes `$`, backticks, `;`, spaces, and other metacharacters, not
    /// just quote chars. A literal `'` becomes `'\''` (close-quote, escaped
    /// quote, reopen-quote).
    public static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes a string for embedding inside an AppleScript double-quoted literal.
    public static func appleScriptEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The safely-quoted token that gets embedded in a Terminal/iTerm AppleScript
    /// `do script`/`write text` command for `scriptPath`.
    public static func appleScriptSafePath(_ scriptPath: String) -> String {
        appleScriptEscaped(shellQuoted(scriptPath))
    }

    /// Builds the exact launch plan for `target`. `alreadyRunning` only affects
    /// the AppleScript terminals (a cold launch reuses the app's own first
    /// window instead of racing to open a second one).
    public static func plan(for target: Target, scriptPath: String, alreadyRunning: Bool) -> TerminalLaunchPlan {
        switch target {
        case .terminal:
            let p = appleScriptSafePath(scriptPath)
            let source = alreadyRunning ? """
            tell application "Terminal"
                activate
                do script "\(p)"
            end tell
            """ : """
            tell application "Terminal"
                activate
                delay 0.6
                do script "\(p)" in front window
            end tell
            """
            return .appleScript(source)

        case .iterm:
            let p = appleScriptSafePath(scriptPath)
            let source = alreadyRunning ? """
            tell application "iTerm"
                activate
                if (count of windows) = 0 then
                    create window with default profile
                else
                    tell current window to create tab with default profile
                end if
                tell current session of current window
                    write text "\(p)"
                end tell
            end tell
            """ : """
            tell application "iTerm"
                activate
                delay 0.6
                tell current session of current window
                    write text "\(p)"
                end tell
            end tell
            """
            return .appleScript(source)

        case .alacritty:
            // `alacritty -e <program>`: the script is executable with a shebang,
            // so it's passed as its own argv element — no shell parsing.
            return .openArgs(appName: "Alacritty", args: ["-e", scriptPath])

        case .kitty:
            // `kitty <program>`: kitty treats the first non-option arg as the
            // program to run.
            return .openArgs(appName: "kitty", args: [scriptPath])
        }
    }
}
