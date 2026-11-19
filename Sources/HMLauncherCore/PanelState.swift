import Foundation

public struct PanelRow: Equatable, Sendable {
    public let uri: String
    public let name: String
    public let source: ItemSource
    public let path: [String]
    public var iconID: String
    public let title: String
    public let isAvailable: Bool
    /// Set for folder rows: activating them opens the folder instead of inserting.
    public var folderID: UUID? = nil
    public var childCount: Int = 0
    /// A search hit from the whole plugin list, shown after the category's own hits.
    public var isGlobal: Bool = false
    /// Counts inserts per plugin (shared by its formats).
    public var usageKey: String = ""
    /// Color label (`ColorPalette` id), already resolved against the color rules.
    public var colorID: String? = nil
    /// A chain: the URIs to insert, in order.
    public var chain: [String]? = nil
    /// A Live action to run instead of inserting.
    public var action: LiveAction? = nil
    /// Not yet filed or inserted, first seen recently.
    public var isNew: Bool = false
}

extension PanelRow {
    /// Row for a chain or Live action entry; nil for plugins and folders.
    static func special(_ e: Entry, index: SearchIndex, colorID: String?) -> PanelRow? {
        if let action = e.action {
            return PanelRow(uri: "", name: e.name, source: e.source, path: [], iconID: e.iconID, title: e.title,
                            isAvailable: true, usageKey: "action|" + e.title.lowercased(), colorID: colorID, action: action)
        }
        if let steps = e.chain {
            let uris = steps.map { index.resolver.resolve(Entry(item: $0))?.uri }
            return PanelRow(uri: "", name: e.name, source: e.source, path: [], iconID: e.iconID, title: e.title,
                            isAvailable: !uris.isEmpty && !uris.contains(nil), usageKey: "chain|" + e.title.lowercased(),
                            colorID: colorID, chain: uris.compactMap { $0 })
        }
        return nil
    }
}

/// One tab per category. (An "All" tab drew every installed plugin at once and froze the panel;
/// typing searches all plugins instead.)
public enum PanelTab: Equatable, Sendable {
    case category(UUID, String)
}

public enum PanelKey: Equatable, Sendable {
    case digit(Int), character(Character)
    case backspace, left, right, tab, up, down, returnKey, escape
    /// Text editing in the filter / quick search: ⌘A, ⌥⌫, ⌘⌫.
    case selectAll, deleteWord, deleteToStart
}

public enum PanelAction: Equatable, Sendable {
    case none, close
    case insert(PanelRow)
}

public struct PanelState {
    private let config: LauncherConfig
    /// Shared, prebuilt view of the plugin list (see `SearchIndex`).
    private let search: SearchIndex
    private let usage: [String: Int]
    public private(set) var tabs: [PanelTab]
    public private(set) var selectedTab: Int
    private var input = TextInput()
    public var filter: String { input.text }
    /// ⌘A selected the whole filter (drawn highlighted; the next key replaces it).
    public var isFilterSelected: Bool { input.isAllSelected }
    public private(set) var highlighted: Int?
    /// The folder shown instead of the category's top level.
    public private(set) var openFolderID: UUID?

    public init(config: LauncherConfig, index: SearchIndex, selectedTab: Int = 0, usage: [String: Int] = [:]) {
        self.usage = usage
        self.config = config
        search = index
        tabs = config.categories.map { .category($0.id, $0.name) }
        self.selectedTab = min(max(selectedTab, 0), tabs.count - 1)
    }

    /// Builds the index on the spot (tests, one-off use).
    public init(config: LauncherConfig, items: [PluginItem], selectedTab: Int = 0, usage: [String: Int] = [:]) {
        self.init(config: config, index: SearchIndex(items: items, config: config), selectedTab: selectedTab, usage: usage)
    }

    /// Without a filter: the category's top level (plugins and folders) or the open folder's plugins, in the
    /// user's order. With a filter: the category's hits (reaching into folders), then hits from all plugins —
    /// each ranked by match quality, then by how often the plugin was inserted.
    public var rows: [PanelRow] {
        let entries = categoryEntries
        let candidates: [PanelRow]
        if let openFolderID {
            candidates = (entries.first { $0.id == openFolderID }?.children ?? []).map(row)
        } else {
            candidates = filter.isEmpty ? entries.map(row)
                : entries.flatMap { e in e.isFolder ? [row(e)] + (e.children ?? []).map(row) : [row(e)] }
        }
        guard !filter.isEmpty else { return candidates }
        let query = SearchMatcher.Prepared(filter)
        let tags = SearchVocabulary.icons(for: filter)
        let rule = SearchTuning.rule(for: filter, in: config.searchRules)
        let ranked = candidates.enumerated()
            .compactMap { i, r in SearchMatcher.score(SearchMatcher.Prepared(r.title), query, iconID: r.iconID, tagIcons: tags).map { (r, $0, i) } }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                if uses(a.0) != uses(b.0) { return uses(a.0) > uses(b.0) }
                let (pa, pb) = (Popularity.score(a.0.title), Popularity.score(b.0.title))
                return pa != pb ? pa > pb : a.2 < b.2
            }
            .map(\.0)
        // The user's search rules: hidden results go, pinned ones lead (in the category part and in "all plugins").
        let local = SearchTuning.apply(ranked, key: \.usageKey, rule: rule)
        let excluded = Set(local.map(\.usageKey)).union(rule?.hidden ?? [])
        let global = SearchTuning.apply(globalMatches(excluding: excluded, limit: Self.maxGlobalResults, markGlobal: true),
                                        key: \.usageKey, rule: rule) { key in
            excluded.contains(key) ? nil : search.globalRow(forKey: key)
        }
        return local + global
    }

    public static let maxGlobalResults = 50

    /// Top-level entries of the fullest category: the panel takes that size when it opens, so hovering the
    /// tabs never resizes it.
    public var largestTabCount: Int { config.categories.map(\.entries.count).max() ?? 0 }

    private func uses(_ row: PanelRow) -> Int { usage[row.usageKey] ?? 0 }

    /// Hits from every installed plugin (one row per plugin), plugins already shown left out.
    private func globalMatches(excluding shown: Set<String>, limit: Int?, markGlobal: Bool) -> [PanelRow] {
        let query = SearchMatcher.Prepared(filter)
        let tags = SearchVocabulary.icons(for: filter)
        var hits: [(row: PanelRow, score: Int, popularity: Int)] = []
        for (i, r) in search.globalRows.enumerated() where !shown.contains(r.usageKey) {
            if let score = SearchMatcher.score(search.globalPrepared[i], query, iconID: r.iconID, tagIcons: tags) {
                hits.append((r, score, search.globalPopularity[i]))
            }
        }
        hits.sort { a, b in  // stable: alphabetical last
            if a.score != b.score { return a.score > b.score }
            if uses(a.row) != uses(b.row) { return uses(a.row) > uses(b.row) }
            return a.popularity > b.popularity
        }
        return hits.prefix(limit ?? hits.count).map(\.row)
    }

    /// The plugins of a folder in the current category, for the side list that opens on hover.
    public func folderRows(_ folderID: UUID) -> [PanelRow] {
        (categoryEntries.first { $0.id == folderID }?.children ?? []).map(row)
    }

    public var openFolderName: String? {
        guard let openFolderID else { return nil }
        return categoryEntries.first { $0.id == openFolderID }?.title
    }

    private var categoryEntries: [Entry] {
        guard case .category(let id, _) = tabs[selectedTab] else { return [] }
        return config.categories.first { $0.id == id }?.entries ?? []
    }

    private func row(_ e: Entry) -> PanelRow {
        if e.isFolder {
            return PanelRow(uri: "", name: e.name, source: e.source, path: [], iconID: e.iconID, title: e.title,
                            isAvailable: true, folderID: e.id, childCount: e.children?.count ?? 0, usageKey: "folder:\(e.id)",
                            colorID: config.colorID(for: e))
        }
        if let special = PanelRow.special(e, index: search, colorID: config.colorID(for: e)) { return special }
        let resolved = search.resolver.resolve(e)
        let uri = resolved?.uri ?? e.uri
        return PanelRow(uri: uri, name: e.name, source: e.source, path: resolved?.path ?? e.path,
                        iconID: e.iconID, title: e.title, isAvailable: resolved != nil, usageKey: search.usageKey[uri] ?? uri,
                        colorID: config.colorID(for: e))
    }

    public mutating func selectTab(_ index: Int) {
        selectedTab = (index % tabs.count + tabs.count) % tabs.count
        input = TextInput()
        highlighted = nil
        openFolderID = nil
    }

    public mutating func openFolder(_ id: UUID) {
        openFolderID = id
        input = TextInput()
        highlighted = nil
    }

    public mutating func closeFolder() {
        openFolderID = nil
        input = TextInput()
        highlighted = nil
    }

    /// The panel's page of 9 on show: digit keys 1–9 pick from it.
    public var page = 0

    public mutating func handle(_ key: PanelKey) -> PanelAction {
        switch key {
        case .digit(let d) where filter.isEmpty:
            guard (1...9).contains(d) else { return .none }
            return insert(at: page * 9 + d - 1)
        case .backspace where filter.isEmpty && openFolderID != nil:
            closeFolder()
            return .none
        case .left:
            selectTab(selectedTab - 1)
        case .right, .tab:
            selectTab(selectedTab + 1)
        case .down:
            input.deselect()
            guard !rows.isEmpty else { return .none }
            highlighted = highlighted.map { min($0 + 1, rows.count - 1) } ?? 0
        case .up:
            input.deselect()
            guard !rows.isEmpty else { return .none }
            highlighted = highlighted.map { max($0 - 1, 0) } ?? 0
        case .returnKey:
            if let h = highlighted { return insert(at: h) }
            return filter.isEmpty ? .none : insert(at: 0)
        case .escape:
            if openFolderID != nil { closeFolder(); return .none }
            return .close
        default:
            if input.apply(key) { highlighted = nil }
        }
        return .none
    }

    /// Folder rows open; plugin rows insert.
    private mutating func insert(at index: Int) -> PanelAction {
        let rows = self.rows
        guard rows.indices.contains(index), rows[index].isAvailable else { return .none }
        if let folder = rows[index].folderID {
            openFolder(folder)
            return .none
        }
        return .insert(rows[index])
    }
}
