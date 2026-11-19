import Foundation

public enum ItemSource: String, Codable, CaseIterable, Sendable {
    case plugins, instruments
    case audioEffects = "audio_effects"
    case midiEffects = "midi_effects"
    case maxForLive = "max_for_live"
    /// The user's own presets (.adg, .vstpreset …) from Live's User Library and from the folders under "Places".
    case userLibrary = "user_library"
    case userFolders = "user_folders"

    public var isPreset: Bool { self == .userLibrary || self == .userFolders }
}

public struct PluginItem: Codable, Hashable, Sendable {
    public var uri: String
    public var name: String
    public var source: ItemSource
    public var path: [String]
    /// Presets only: file extension without the dot ("adg", "vstpreset"). Nil for devices and plugins.
    public var format: String?

    public init(uri: String, name: String, source: ItemSource, path: [String], format: String? = nil) {
        self.uri = uri; self.name = name; self.source = source; self.path = path; self.format = format
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
    /// Own color label (`ColorPalette` id); nil = follow the color rules.
    public var colorID: String?
    /// A chain: these items are inserted one after the other.
    public var chain: [PluginItem]?
    /// A Live action ("New MIDI Track", "Tempo 128") instead of a plugin.
    public var action: LiveAction?

    public var title: String { displayName ?? name }
    public var isFolder: Bool { children != nil }

    public init(folderNamed name: String) {
        id = UUID(); uri = ""; self.name = name; source = .plugins; path = []
        iconID = IconCatalog.folderID; displayName = nil; children = []
    }

    public init(chainNamed name: String, steps: [PluginItem], iconID: String = "rack") {
        id = UUID(); uri = ""; self.name = name; source = .plugins; path = []
        self.iconID = iconID; displayName = nil; chain = steps
    }

    public init(action: LiveAction) {
        id = UUID(); uri = ""; name = action.title; source = .plugins; path = []
        iconID = action.kind.iconID; displayName = nil; self.action = action
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
    /// Opens the quick search window; empty = disabled.
    public var quickSearch: [KeyCombo]
    /// Switches to the next profile; empty = disabled (the default).
    public var nextProfile: [KeyCombo] = []

    public static let `default` = ShortcutSettings(
        closeFocused: KeyCombo(keyCode: 13, modifiers: [.cmd]),
        closeAll: [KeyCombo(keyCode: 13, modifiers: [.cmd, .ctrl]), KeyCombo(keyCode: 53, modifiers: [.cmd])],
        quickSearch: [KeyCombo(keyCode: 49, modifiers: [.ctrl])]
    )

    public init(closeFocused: KeyCombo?, closeAll: [KeyCombo], quickSearch: [KeyCombo] = ShortcutSettings.default.quickSearch) {
        self.closeFocused = closeFocused
        self.closeAll = closeAll
        self.quickSearch = quickSearch
    }

    /// Shortcuts added later get their default in older config files.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        closeFocused = try c.decodeIfPresent(KeyCombo.self, forKey: .closeFocused)
        closeAll = try c.decodeIfPresent([KeyCombo].self, forKey: .closeAll) ?? []
        quickSearch = try c.decodeIfPresent([KeyCombo].self, forKey: .quickSearch) ?? ShortcutSettings.default.quickSearch
        nextProfile = try c.decodeIfPresent([KeyCombo].self, forKey: .nextProfile) ?? []
    }
}

public struct LauncherConfig: Codable, Sendable {
    public var version: Int
    public var categories: [Category]
    public var shortcuts: ShortcutSettings
    public var panelKeys: PanelKeyBindings
    /// nil = follow the macOS language
    public var language: Language?
    /// Color rules by `ColorRule.key` (Live devices, a manufacturer) → `ColorPalette` id.
    public var colorRules: [String: String] = [:]
    /// Pinned / hidden search results per search term.
    public var searchRules: [SearchRule] = []
    /// Key combinations that insert a single plugin, rack or preset.
    public var itemShortcuts: [ItemShortcut] = []
    /// Look of the app's windows.
    public var theme: AppTheme = .pads
    /// Where inserted items land and on which tracks.
    public var insert: InsertOptions = .default
    /// Stats page: list panel entries that are hardly used (can be switched off).
    public var showRarelyUsed = true
    /// Entries the user chose to keep although they are rarely used.
    public var keptEntries: [UUID] = []
    /// Local HTTP endpoint for Stream Deck & co. (127.0.0.1 only); off unless switched on.
    public var streamDeckEnabled = false
    /// Columns of 9 entries the panel may put side by side (1–9).
    public var panelColumns: Int {
        get { storedPanelColumns }
        set { storedPanelColumns = min(max(newValue, 1), PanelGrid.maxColumns) }
    }
    private var storedPanelColumns = PanelGrid.columns
    /// Width of a panel column and height of an entry (resize grip in the panel).
    public var panelSize = PanelSize.default
    /// The welcome window was finished or skipped.
    public var onboardingDone = false
    /// Secret part of every Stream Deck link, so a web page can't trigger commands on the local endpoint.
    public var streamDeckToken = LauncherConfig.newToken()
    /// All profiles (named menus); the active one's menu is `categories`.
    public var profiles: [Profile] = []
    public var activeProfileID = UUID()

    public init(version: Int, categories: [Category], shortcuts: ShortcutSettings, panelKeys: PanelKeyBindings = .default) {
        self.version = version
        self.categories = categories
        self.shortcuts = shortcuts
        self.panelKeys = panelKeys
        ensureProfile()
    }

    /// Fields added later decode with defaults, so older config files keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        categories = try c.decode([Category].self, forKey: .categories)
        shortcuts = try c.decodeIfPresent(ShortcutSettings.self, forKey: .shortcuts) ?? .default
        panelKeys = try c.decodeIfPresent(PanelKeyBindings.self, forKey: .panelKeys) ?? .default
        language = try c.decodeIfPresent(Language.self, forKey: .language)
        colorRules = try c.decodeIfPresent([String: String].self, forKey: .colorRules) ?? [:]
        searchRules = try c.decodeIfPresent([SearchRule].self, forKey: .searchRules) ?? []
        itemShortcuts = try c.decodeIfPresent([ItemShortcut].self, forKey: .itemShortcuts) ?? []
        theme = (try? c.decodeIfPresent(AppTheme.self, forKey: .theme)) ?? .pads
        insert = (try? c.decodeIfPresent(InsertOptions.self, forKey: .insert)) ?? .default
        showRarelyUsed = try c.decodeIfPresent(Bool.self, forKey: .showRarelyUsed) ?? true
        keptEntries = try c.decodeIfPresent([UUID].self, forKey: .keptEntries) ?? []
        streamDeckEnabled = try c.decodeIfPresent(Bool.self, forKey: .streamDeckEnabled) ?? false
        panelColumns = try c.decodeIfPresent(Int.self, forKey: .storedPanelColumns) ?? PanelGrid.columns
        panelSize = (try? c.decodeIfPresent(PanelSize.self, forKey: .panelSize)) ?? .default
        onboardingDone = try c.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? false
        streamDeckToken = try c.decodeIfPresent(String.self, forKey: .streamDeckToken) ?? LauncherConfig.newToken()
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID) ?? UUID()
        ensureProfile()
    }

    public static let currentVersion = 4

    public static func makeDefault() -> LauncherConfig {
        LauncherConfig(
            version: currentVersion,
            categories: [Category(name: "Favorites", isFavorites: true), Category(name: "Instruments"), Category(name: "Effects")],
            shortcuts: .default
        )
    }
}
