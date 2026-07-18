import AppKit

/// Mirrors the real macOS desktop icon grid so dragged tiles snap onto the same
/// lattice as the user's desktop icons.
///
/// Rather than asking Finder over AppleScript (which pops the "Shorkut wants to
/// control Finder" Automation prompt, and — if denied — silently fell back to a
/// wrong guessed icon size), we read Finder's own saved view settings straight
/// from its preferences domain. `com.apple.finder` → `DesktopViewSettings` →
/// `IconViewSettings` carries the exact `iconSize`, `gridSpacing`, `textSize`
/// and `labelOnBottom` the desktop is laid out with. No permission required,
/// synchronous, and no nested-run-loop reentrancy to worry about.
final class DesktopIconGrid {
    static var cellWidth: CGFloat = 88
    static var cellHeight: CGFloat = 104
    private static var hasStartedRefresh = false

    struct Metrics {
        let cellWidth: CGFloat
        let cellHeight: CGFloat
    }

    /// Safe to call more than once — only the first call does any work, unless
    /// `force` is set (used by the manual "Match Finder" button in Settings).
    /// `onUpdate` fires on the main thread only if Finder's settings were read.
    static func refreshFromFinderIfNeeded(force: Bool = false, onUpdate: ((CGFloat, CGFloat) -> Void)? = nil) {
        guard force || !hasStartedRefresh else { return }
        hasStartedRefresh = true
        guard let metrics = finderDesktopMetrics() else { return }
        cellWidth = metrics.cellWidth
        cellHeight = metrics.cellHeight
        onUpdate?(metrics.cellWidth, metrics.cellHeight)
    }

    /// Reads Finder's desktop icon-view settings and derives the grid cell size.
    /// `gridSpacing` is the padding Finder adds around each icon; the horizontal
    /// pitch is `iconSize + gridSpacing`, and the vertical pitch adds room for
    /// the label underneath when labels sit on the bottom (the desktop default).
    static func finderDesktopMetrics() -> Metrics? {
        guard let settings = CFPreferencesCopyAppValue("DesktopViewSettings" as CFString,
                                                       "com.apple.finder" as CFString) as? [String: Any],
              let icon = settings["IconViewSettings"] as? [String: Any] else {
            return nil
        }

        let iconSize = (icon["iconSize"] as? NSNumber)?.doubleValue ?? 64
        let gridSpacing = (icon["gridSpacing"] as? NSNumber)?.doubleValue ?? 54
        let textSize = (icon["textSize"] as? NSNumber)?.doubleValue ?? 12
        let labelOnBottom = (icon["labelOnBottom"] as? NSNumber)?.boolValue ?? true

        // A single-line filename label is roughly the text size plus a little
        // leading; it only adds to the vertical pitch when labels sit on bottom.
        let labelHeight = labelOnBottom ? (textSize + 4) : 0

        let width = iconSize + gridSpacing
        let height = iconSize + gridSpacing + labelHeight
        return Metrics(cellWidth: CGFloat(width), cellHeight: CGFloat(height))
    }
}
