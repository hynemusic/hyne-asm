import Foundation

public enum ItemSource: String, Codable, CaseIterable, Sendable {
    case plugins, instruments
    case audioEffects = "audio_effects"
    case midiEffects = "midi_effects"
    case maxForLive = "max_for_live"
}

public struct PluginItem: Codable, Hashable, Sendable {
    public var uri: String
    public var name: String
    public var source: ItemSource
    public var path: [String]

    public init(uri: String, name: String, source: ItemSource, path: [String]) {
        self.uri = uri; self.name = name; self.source = source; self.path = path
    }
}

public struct Entry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var uri: String
    public var name: String
    public var source: ItemSource
    public var path: [String]
    public var iconID: String
    public var displayName: String?
    /// Non-nil makes this entry a folder of plugins (one level deep; folders hold no folders).
    public var children: [Entry]?

    public var title: String { displayName ?? name }
    public var isFolder: Bool { children != nil }

    public init(folderNamed name: String) {
        id = UUID(); uri = ""; self.name = name; source = .plugins; path = []
        iconID = IconCatalog.folderID; displayName = nil; children = []
    }

    public init(item: PluginItem, iconID: String = IconCatalog.defaultID) {
        id = UUID(); uri = item.uri; name = item.name; source = item.source; path = item.path
        self.iconID = iconID; displayName = nil
    }
}

public struct Category: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isFavorites: Bool
    public var entries: [Entry]

    public init(name: String, isFavorites: Bool = false, entries: [Entry] = []) {
        id = UUID(); self.name = name; self.isFavorites = isFavorites; self.entries = entries
    }
}

public struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let cmd = ModifierSet(rawValue: 1 << 0)
    public static let alt = ModifierSet(rawValue: 1 << 1)
    public static let shift = ModifierSet(rawValue: 1 << 2)
    public static let ctrl = ModifierSet(rawValue: 1 << 3)
}

public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: ModifierSet
    public init(keyCode: UInt16, modifiers: ModifierSet) { self.keyCode = keyCode; self.modifiers = modifiers }
}

public struct ShortcutSettings: Codable, Equatable, Sendable {
    /// nil = disabled
    public var closeFocused: KeyCombo?
    /// empty = disabled
    public var closeAll: [KeyCombo]

    public static let `default` = ShortcutSettings(
        closeFocused: KeyCombo(keyCode: 13, modifiers: [.cmd]),
        closeAll: [KeyCombo(keyCode: 13, modifiers: [.cmd, .ctrl]), KeyCombo(keyCode: 53, modifiers: [.cmd])]
    )
}

public struct LauncherConfig: Codable, Sendable {
    public var version: Int
    public var categories: [Category]
    public var shortcuts: ShortcutSettings
    public var panelKeys: PanelKeyBindings
    /// nil = follow the macOS language
    public var language: Language?

    public init(version: Int, categories: [Category], shortcuts: ShortcutSettings, panelKeys: PanelKeyBindings = .default) {
        self.version = version
        self.categories = categories
        self.shortcuts = shortcuts
        self.panelKeys = panelKeys
    }

    /// Fields added later decode with defaults, so older config files keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        categories = try c.decode([Category].self, forKey: .categories)
        shortcuts = try c.decodeIfPresent(ShortcutSettings.self, forKey: .shortcuts) ?? .default
        panelKeys = try c.decodeIfPresent(PanelKeyBindings.self, forKey: .panelKeys) ?? .default
        language = try c.decodeIfPresent(Language.self, forKey: .language)
    }

    public static let currentVersion = 3

    public static func makeDefault() -> LauncherConfig {
        LauncherConfig(
            version: currentVersion,
            categories: [Category(name: "Favorites", isFavorites: true), Category(name: "Instruments"), Category(name: "Effects")],
            shortcuts: .default
        )
    }
}
