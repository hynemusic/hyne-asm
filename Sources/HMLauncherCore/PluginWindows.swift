import Foundation

/// Opening plugin windows from the keyboard or with a click in a plugin's X-Y field.
/// Stored as an optional block in the config, so files without it (and the Windows app) keep their exact form.
public struct PluginWindowSettings: Codable, Equatable, Sendable {
    /// Opens (or closes) every plugin window of the selected track; empty = off.
    public var openAll: [KeyCombo] = []
    /// A click in a plugin's X-Y field opens its window; Live never gets the click, so the X-Y dot stays put.
    public var xyClick = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openAll = try c.decodeIfPresent([KeyCombo].self, forKey: .openAll) ?? []
        xyClick = try c.decodeIfPresent(Bool.self, forKey: .xyClick) ?? true
    }

    public static let `default` = PluginWindowSettings()
}

/// One "Show/Hide Plug-In Window" button (the wrench) in Live's device view, as Live 12's accessibility tree shows it.
/// `identifier` looks like `TrackView.Device[0].Device[1].TitleBar.PluginEdit` (independent of Live's language).
public struct PluginWindowButton: Equatable, Sendable {
    public var identifier: String
    public var isOpen: Bool

    public init(identifier: String, isOpen: Bool) { self.identifier = identifier; self.isOpen = isOpen }

    /// `TrackView.Device[0].Device[1]`.
    public var devicePath: String? { PluginWindowPlanner.devicePath(of: identifier) }
}

public enum PluginWindowPlanner {
    public static let trackViewID = "TrackView"
    public static let buttonSuffix = ".TitleBar.PluginEdit"
    public static let xySuffix = ".PluginXyControl"

    /// The device an element belongs to: `TrackView.Device[0].Device[1].TitleBar.DeviceOn` → `TrackView.Device[0].Device[1]`.
    /// nil outside the device view (track headers, clips, the browser …).
    public static func devicePath(of identifier: String?) -> String? {
        guard let identifier else { return nil }
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.first == Substring(trackViewID) else { return nil }
        let devices = parts.dropFirst().prefix { $0.hasPrefix("Device[") && $0.hasSuffix("]") }
        guard !devices.isEmpty else { return nil }
        return ([trackViewID] + devices.map(String.init)).joined(separator: ".")
    }

    /// The wrench of the plugin whose X-Y field (or a part of it) is `identifier`; nil for anything else.
    /// `TrackView.Device[3].PluginXyControl` → `TrackView.Device[3].TitleBar.PluginEdit`.
    public static func xyButton(for identifier: String?) -> String? {
        guard let identifier, let device = devicePath(of: identifier),
              identifier.hasPrefix(device + xySuffix) else { return nil }
        let rest = identifier.dropFirst(device.count + xySuffix.count)
        guard rest.isEmpty || rest.hasPrefix(".") else { return nil }
        return device + buttonSuffix
    }

    /// Opens the closed ones; when every one is already open, closes them (the shortcut toggles).
    public static func toPress(_ buttons: [PluginWindowButton]) -> [PluginWindowButton] {
        let closed = buttons.filter { !$0.isOpen }
        return closed.isEmpty ? buttons : closed
    }
}

/// Live doesn't report which devices are selected, so the app follows the clicks: a click on a device selects it,
/// ⇧-click selects the range from the last plain click (within one chain), a click anywhere else clears the selection.
public struct DeviceSelectionTracker: Equatable, Sendable {
    public private(set) var anchor: String?
    public private(set) var selection: [String] = []

    public init() {}

    /// `identifier`: what was clicked (any element; nil or outside the device view clears).
    public mutating func click(on identifier: String?, extend: Bool) {
        guard let device = PluginWindowPlanner.devicePath(of: identifier) else {
            anchor = nil; selection = []
            return
        }
        if extend, let anchor, let range = Self.range(from: anchor, to: device) {
            selection = range
            return
        }
        anchor = device
        selection = [device]
    }

    /// The devices a click in `device`'s X-Y field acts on: the whole selection when the device is part of it.
    public func devices(forClickOn device: String) -> [String] {
        selection.count > 1 && selection.contains(device) ? selection : [device]
    }

    /// `TrackView.Device[1]` … `TrackView.Device[3]`; nil when the two aren't in the same chain.
    static func range(from a: String, to b: String) -> [String]? {
        guard let (parentA, i) = split(a), let (parentB, j) = split(b), parentA == parentB else { return nil }
        return (min(i, j)...max(i, j)).map { "\(parentA)Device[\($0)]" }
    }

    /// `TrackView.Device[0].Device[2]` → (`TrackView.Device[0].`, 2).
    private static func split(_ path: String) -> (String, Int)? {
        guard let open = path.range(of: "Device[", options: .backwards), path.hasSuffix("]"),
              let index = Int(path[open.upperBound..<path.index(before: path.endIndex)]) else { return nil }
        return (String(path[..<open.lowerBound]), index)
    }
}
