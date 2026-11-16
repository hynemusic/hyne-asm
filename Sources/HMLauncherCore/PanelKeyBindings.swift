/// Rebindable keys inside the open panel. Digits 1–9, typing and ⌫ stay fixed.
public enum PanelKeyAction: String, CaseIterable, Codable, Sendable {
    case prevTab, nextTab, up, down, insert, close

    public var label: String {
        switch self {
        case .prevTab: return "Vorheriger Tab"
        case .nextTab: return "Nächster Tab"
        case .up: return "Nach oben"
        case .down: return "Nach unten"
        case .insert: return "Markiertes Plugin einfügen"
        case .close: return "Panel schließen"
        }
    }

    var panelKey: PanelKey {
        switch self {
        case .prevTab: return .left
        case .nextTab: return .right
        case .up: return .up
        case .down: return .down
        case .insert: return .returnKey
        case .close: return .escape
        }
    }
}

public struct PanelKeyBindings: Codable, Equatable, Sendable {
    private var bindings: [String: [KeyCombo]]

    public static let `default` = PanelKeyBindings(bindings: [
        PanelKeyAction.prevTab.rawValue: [KeyCombo(keyCode: 123, modifiers: [])],
        PanelKeyAction.nextTab.rawValue: [KeyCombo(keyCode: 124, modifiers: []), KeyCombo(keyCode: 48, modifiers: [])],
        PanelKeyAction.up.rawValue: [KeyCombo(keyCode: 126, modifiers: [])],
        PanelKeyAction.down.rawValue: [KeyCombo(keyCode: 125, modifiers: [])],
        PanelKeyAction.insert.rawValue: [KeyCombo(keyCode: 36, modifiers: []), KeyCombo(keyCode: 76, modifiers: [])],
        PanelKeyAction.close.rawValue: [KeyCombo(keyCode: 53, modifiers: [])],
    ])

    /// Unset actions fall back to their default.
    public subscript(action: PanelKeyAction) -> [KeyCombo] {
        get { bindings[action.rawValue] ?? Self.default.bindings[action.rawValue] ?? [] }
        set { bindings[action.rawValue] = newValue }
    }

    public func key(for combo: KeyCombo) -> PanelKey? {
        PanelKeyAction.allCases.first { self[$0].contains(combo) }?.panelKey
    }

    public static func == (a: PanelKeyBindings, b: PanelKeyBindings) -> Bool {
        PanelKeyAction.allCases.allSatisfy { a[$0] == b[$0] }
    }
}
