import ApplicationServices
import HMLauncherCore

/// Opens Live's plugin windows by pressing the device view's "Show/Hide Plug-In Window" buttons (the wrench)
/// through the Accessibility API. Live 12 names them `TrackView.Device[…].TitleBar.PluginEdit`, whatever its language.
/// Call off the main thread: every lookup is a round trip to Live.
enum PluginWindowOpener {
    enum Outcome: Equatable {
        case pressed(Int)
        /// The device view isn't on screen (Live shows the clip view, or the detail view is hidden).
        case noDeviceView
        /// The track has no plugin.
        case noPlugins
    }

    private struct Found {
        let element: AXUIElement
        let button: PluginWindowButton
    }

    /// A plugin's X-Y field under the mouse: the field's element and its plugin's wrench id.
    struct XYTarget {
        let field: AXUIElement
        let wrenchID: String
    }

    /// The point lookup runs inside the event-tap callback; past this Live keeps the click.
    static let clickTimeout: Float = 0.05

    /// Shortcut: every plugin of the selected track (opens the closed ones, or closes all when all are open).
    static func openAll(pid: pid_t) -> Outcome {
        let app = liveApp(pid)
        guard let trackView = findTrackView(app) else { return .noDeviceView }
        let found = buttons(in: trackView)
        let press = PluginWindowPlanner.toPress(found.map(\.button))
        guard !press.isEmpty else { return .noPlugins }
        for b in press {
            if let e = found.first(where: { $0.button.identifier == b.identifier })?.element { pressButton(e) }
        }
        return .pressed(press.count)
    }

    /// What a click at `point` lands on: the element and its id (`TrackView.Device[3].PluginXyControl` …).
    /// One or two quick round trips, safe inside the event-tap callback; nil when Live doesn't answer in time.
    static func element(at point: CGPoint, pid: pid_t) -> (element: AXUIElement, id: String?)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, clickTimeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success, let hit else { return nil }
        AXUIElementSetMessagingTimeout(hit, clickTimeout)
        return (hit, attribute(hit, "AXIdentifier"))
    }

    /// Several selected devices: opens their closed plugin windows, or closes them all when all are open.
    static func toggle(devices: [String], pid: pid_t) {
        guard let trackView = findTrackView(liveApp(pid)) else { return }
        let wanted = Set(devices)
        let found = buttons(in: trackView).filter { $0.button.devicePath.map(wanted.contains) ?? false }
        for b in PluginWindowPlanner.toPress(found.map(\.button)) {
            if let e = found.first(where: { $0.button.identifier == b.identifier })?.element { pressButton(e) }
        }
    }

    /// Presses the wrench of the plugin the X-Y field belongs to (off the event-tap callback).
    static func toggle(_ target: XYTarget) {
        var element: AXUIElement? = target.field
        while let e = element {   // up to the device group, which holds the title bar's wrench
            if let wrench = children(e).first(where: { (attribute($0, "AXIdentifier") as String?) == target.wrenchID }) {
                pressButton(wrench)
                return
            }
            element = attribute(e, kAXParentAttribute)
        }
    }

    // MARK: Accessibility tree

    private static func liveApp(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, WindowCloser.messagingTimeout)
        return app
    }

    /// The device view sits a few levels below Live's main window (window → group → `TrackView`).
    private static func findTrackView(_ app: AXUIElement) -> AXUIElement? {
        let windows: [AXUIElement] = attribute(app, kAXWindowsAttribute) ?? []
        var level = windows
        for _ in 0..<4 {
            var next: [AXUIElement] = []
            for e in level {
                if (attribute(e, "AXIdentifier") as String?) == PluginWindowPlanner.trackViewID { return e }
                next += children(e)
            }
            level = next
        }
        return nil
    }

    /// Every wrench in the device view, racks included (their contents are devices inside the rack's group).
    private static func buttons(in trackView: AXUIElement) -> [Found] {
        var result: [Found] = []
        func visit(_ device: AXUIElement) {
            for child in children(device) {
                guard let id: String = attribute(child, "AXIdentifier") else { continue }
                if id.hasSuffix(PluginWindowPlanner.buttonSuffix) {
                    let open = (attribute(child, kAXValueAttribute) as NSNumber?)?.boolValue ?? false
                    result.append(Found(element: child, button: PluginWindowButton(identifier: id, isOpen: open)))
                } else if PluginWindowPlanner.devicePath(of: id) == id {
                    visit(child)
                }
            }
        }
        visit(trackView)
        return result
    }

    private static func pressButton(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) ?? []
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
