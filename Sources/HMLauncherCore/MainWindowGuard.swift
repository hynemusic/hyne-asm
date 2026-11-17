import CoreGraphics

/// Decides which of Live's windows must never be closed by the close-plugin-window shortcuts.
/// Live 12 titles its main window with just the set name ("Untitled", "My Song"), so the title alone
/// can't tell it apart. Plugin windows float (window layer > 0); the main window is on layer 0.
public enum MainWindowGuard {
    public struct ScreenWindow: Equatable {
        public var frame: CGRect
        public var layer: Int
        public var title: String
        public init(frame: CGRect, layer: Int, title: String) { self.frame = frame; self.layer = layer; self.title = title }
    }

    /// Main windows on screen: the largest normal-layer window plus any other normal-layer window
    /// with the same title (Live's second window shows the same set name).
    public static func mainWindows(_ windows: [ScreenWindow]) -> [ScreenWindow] {
        let normal = windows.filter { $0.layer == 0 && $0.frame.width >= 300 && $0.frame.height >= 300 }
        guard let largest = normal.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return [] }
        return normal.filter { $0 == largest || (!largest.title.isEmpty && $0.title == largest.title) }
    }

    /// True if an accessibility window with this frame/title is one of Live's main windows.
    public static func isMain(frame: CGRect?, title: String?, isAXMain: Bool, screen: [ScreenWindow]) -> Bool {
        if isAXMain { return true }
        if let title, title.contains("Ableton Live") { return true }
        guard let frame else { return false }
        return mainWindows(screen).contains { close($0.frame, frame) }
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 4 && abs(a.minY - b.minY) <= 4 && abs(a.width - b.width) <= 4 && abs(a.height - b.height) <= 4
    }
}
