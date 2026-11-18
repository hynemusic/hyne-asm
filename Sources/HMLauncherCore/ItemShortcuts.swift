import Foundation

/// A key combination that inserts one plugin, rack or preset straight away (while Live is in front).
public struct ItemShortcut: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var combo: KeyCombo
    public var uri: String
    public var name: String
    public var source: ItemSource
    public var path: [String]

    public init(combo: KeyCombo, item: PluginItem) {
        self.combo = combo
        uri = item.uri; name = item.name; source = item.source; path = item.path
    }

    public var item: PluginItem { PluginItem(uri: uri, name: name, source: source, path: path) }
}

public extension LauncherConfig {
    /// Assigns (or moves) a shortcut to an item; one shortcut per item.
    mutating func setItemShortcut(_ combo: KeyCombo?, for item: PluginItem) {
        itemShortcuts.removeAll { $0.uri == item.uri || ($0.name == item.name && $0.source == item.source) }
        if let combo { itemShortcuts.append(ItemShortcut(combo: combo, item: item)) }
    }

    func itemShortcut(for item: PluginItem) -> ItemShortcut? {
        itemShortcuts.first { $0.uri == item.uri } ?? itemShortcuts.first { $0.name == item.name && $0.source == item.source }
    }

    /// Who else uses this combo ("Close all plugin windows", "Serum 2"); nil when it is free.
    func shortcutOwner(of combo: KeyCombo, ignoring itemID: UUID? = nil) -> String? {
        if shortcuts.closeFocused == combo { return Loc.t("Fokussiertes Plugin-Fenster schließen", "Close focused plugin window") }
        if shortcuts.closeAll.contains(combo) { return Loc.t("Alle Plugin-Fenster schließen", "Close all plugin windows") }
        if shortcuts.quickSearch.contains(combo) { return Loc.t("Schnellsuche öffnen", "Open quick search") }
        return itemShortcuts.first { $0.combo == combo && $0.id != itemID }?.name
    }
}

public extension ShortcutMatcher {
    /// Item shortcuts come after the built-in ones, so those always win.
    static func itemShortcut(keyCode: UInt16, modifiers: ModifierSet, in shortcuts: [ItemShortcut]) -> ItemShortcut? {
        let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        return shortcuts.first { $0.combo == combo }
    }
}
