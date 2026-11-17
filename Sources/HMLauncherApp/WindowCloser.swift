import ApplicationServices
import HMLauncherCore

/// Closes Live's plugin windows via the Accessibility API. Live's main window is never closed.
enum WindowCloser {
    /// Keeps the event-tap callback from hanging while Live's main thread is busy (e.g. loading a plugin).
    static let messagingTimeout: Float = 0.25

    private static func liveApp(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return app
    }

    /// Returns false if the focused window is Live's main window (the key then goes to Live).
    static func closeFocused(pid: pid_t) -> Bool {
        let app = liveApp(pid)
        let screen = screenWindows(pid)
        guard let focused: AXUIElement = attribute(app, kAXFocusedWindowAttribute), !isMainWindow(focused, app: app, screen: screen) else { return false }
        return close(focused)
    }

    @discardableResult
    static func closeAll(pid: pid_t) -> Int {
        let app = liveApp(pid)
        let windows: [AXUIElement] = attribute(app, kAXWindowsAttribute) ?? []
        let screen = screenWindows(pid)
        return windows.filter { !isMainWindow($0, app: app, screen: screen) && close($0) }.count
    }

    private static func isMainWindow(_ window: AXUIElement, app: AXUIElement, screen: [MainWindowGuard.ScreenWindow]) -> Bool {
        let main: AXUIElement? = attribute(app, kAXMainWindowAttribute)
        return MainWindowGuard.isMain(
            frame: frame(window),
            title: attribute(window, kAXTitleAttribute),
            isAXMain: main.map { CFEqual($0, window) } ?? false,
            screen: screen)
    }

    /// Live's on-screen windows with their window layer (plugin windows float above layer 0).
    private static func screenWindows(_ pid: pid_t) -> [MainWindowGuard.ScreenWindow] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b) else { return nil }
            return .init(frame: rect, layer: w[kCGWindowLayer as String] as? Int ?? 0, title: w[kCGWindowName as String] as? String ?? "")
        }
    }

    private static func frame(_ window: AXUIElement) -> CGRect? {
        guard let p: AXValue = attribute(window, kAXPositionAttribute), let s: AXValue = attribute(window, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private static func close(_ window: AXUIElement) -> Bool {
        guard let button: AXUIElement = attribute(window, kAXCloseButtonAttribute) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
