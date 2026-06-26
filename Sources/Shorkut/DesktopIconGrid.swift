import AppKit

/// Mirrors the real macOS desktop icon grid: queries Finder once (off the main
/// thread, async) for the user's configured icon size, then derives the same
/// cell padding Finder uses around it. Falls back to Finder's own default icon
/// size (64) until the query resolves, or permanently if Automation access is
/// denied.
///
/// The query is fired once, explicitly, well before any tile can schedule a
/// snap timer — never call it synchronously from a timer/run-loop callback.
/// NSAppleScript pumps a nested run loop while it waits for Finder's reply,
/// and if a second tile's debounce timer fires during that wait and tries to
/// re-enter a lazily-initialized `static let`, Swift's dispatch_once detects
/// the reentrancy and traps. Plain mutable statics plus a one-shot background
/// refresh avoid that path entirely.
final class DesktopIconGrid {
    static var cellWidth: CGFloat = 64 + 34
    static var cellHeight: CGFloat = 64 + 41
    private static var hasStartedRefresh = false

    /// Safe to call more than once — only the first call does any work, unless
    /// `force` is set (used by the manual "Match Finder" button in Settings).
    /// `onUpdate` fires on the main thread only if the query actually succeeds.
    static func refreshFromFinderIfNeeded(force: Bool = false, onUpdate: ((CGFloat, CGFloat) -> Void)? = nil) {
        guard force || !hasStartedRefresh else { return }
        hasStartedRefresh = true
        DispatchQueue.global(qos: .utility).async {
            guard let iconSize = queryIconSize() else { return }
            DispatchQueue.main.async {
                cellWidth = iconSize + 34
                cellHeight = iconSize + 41
                onUpdate?(cellWidth, cellHeight)
            }
        }
    }

    private static func queryIconSize() -> CGFloat? {
        let source = """
        tell application "Finder"
            set vo to icon view options of container window of desktop
            return icon size of vo
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        let value = result.int32Value
        guard value > 0 else { return nil }
        return CGFloat(value)
    }
}
