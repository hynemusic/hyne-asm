import ApplicationServices

/// Closes Live's plugin windows via the Accessibility API. Live's main window is never closed.
enum WindowCloser {
    /// Returns false if the focused window is Live's main window (the key then goes to Live).
    static func closeFocused(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        guard let focused: AXUIElement = attribute(app, kAXFocusedWindowAttribute), !isMainWindow(focused, app: app) else { return false }
        return close(focused)
    }

    @discardableResult
    static func closeAll(pid: pid_t) -> Int {
        let app = AXUIElementCreateApplication(pid)
        let windows: [AXUIElement] = attribute(app, kAXWindowsAttribute) ?? []
        return windows.filter { !isMainWindow($0, app: app) && close($0) }.count
    }

    /// Live's main window is titled "<Set> - Ableton Live 12 <Edition>"; plugin windows are not.
    /// Without a title, fall back to the AX main window.
    private static func isMainWindow(_ window: AXUIElement, app: AXUIElement) -> Bool {
        if let title: String = attribute(window, kAXTitleAttribute), !title.isEmpty {
            return title.contains("Ableton Live")
        }
        guard let main: AXUIElement = attribute(app, kAXMainWindowAttribute) else { return false }
        return CFEqual(main, window)
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
