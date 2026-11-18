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
}

/// One tab per category. (An "All" tab drew every installed plugin at once and froze the panel;
/// typing searches all plugins instead.)
public enum PanelTab: Equatable, Sendable {
    case category(UUID, String)
}

public enum PanelKey: Equatable, Sendable {
    case digit(Int), character(Character)
    case backspace, left, right, tab, up, down, returnKey, escape
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
    public private(set) var filter = ""
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
        let rule = SearchTuning.rule(for: filter, in: config.searchRules)
        let ranked = candidates.enumerated()
            .compactMap { i, r in SearchMatcher.score(SearchMatcher.Prepared(r.title), query).map { (r, $0, i) } }
            .sorted { a, b in
                a.1 != b.1 ? a.1 > b.1 : (uses(a.0) != uses(b.0) ? uses(a.0) > uses(b.0) : a.2 < b.2)
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

    private func uses(_ row: PanelRow) -> Int { usage[row.usageKey] ?? 0 }

    /// Hits from every installed plugin (one row per plugin), plugins already shown left out.
    private func globalMatches(excluding shown: Set<String>, limit: Int?, markGlobal: Bool) -> [PanelRow] {
        let query = SearchMatcher.Prepared(filter)
        var hits: [(row: PanelRow, score: Int)] = []
        for (i, r) in search.globalRows.enumerated() where !shown.contains(r.usageKey) {
            if let score = SearchMatcher.score(search.globalPrepared[i], query) { hits.append((r, score)) }
        }
        hits.sort { a, b in a.score != b.score ? a.score > b.score : uses(a.row) > uses(b.row) } // stable: alphabetical
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
        let resolved = search.resolver.resolve(e)
        let uri = resolved?.uri ?? e.uri
        return PanelRow(uri: uri, name: e.name, source: e.source, path: resolved?.path ?? e.path,
                        iconID: e.iconID, title: e.title, isAvailable: resolved != nil, usageKey: search.usageKey[uri] ?? uri,
                        colorID: config.colorID(for: e))
    }

    public mutating func selectTab(_ index: Int) {
        selectedTab = (index % tabs.count + tabs.count) % tabs.count
        filter = ""
        highlighted = nil
        openFolderID = nil
    }

    public mutating func openFolder(_ id: UUID) {
        openFolderID = id
        filter = ""
        highlighted = nil
    }

    public mutating func closeFolder() {
        openFolderID = nil
        filter = ""
        highlighted = nil
    }

    public mutating func handle(_ key: PanelKey) -> PanelAction {
        switch key {
        case .digit(let d):
            if !filter.isEmpty { return edit { $0.append(String(d)) } }
            guard (1...9).contains(d) else { return .none }
            return insert(at: d - 1)
        case .character(let c):
            return edit { $0.append(c) }
        case .backspace:
            if filter.isEmpty, openFolderID != nil { closeFolder(); return .none }
            return edit { if !$0.isEmpty { $0.removeLast() } }
        case .left:
            selectTab(selectedTab - 1)
        case .right, .tab:
            selectTab(selectedTab + 1)
        case .down:
            guard !rows.isEmpty else { return .none }
            highlighted = highlighted.map { min($0 + 1, rows.count - 1) } ?? 0
        case .up:
            guard !rows.isEmpty else { return .none }
            highlighted = highlighted.map { max($0 - 1, 0) } ?? 0
        case .returnKey:
            if let h = highlighted { return insert(at: h) }
            return filter.isEmpty ? .none : insert(at: 0)
        case .escape:
            if openFolderID != nil { closeFolder(); return .none }
            return .close
        }
        return .none
    }

    private mutating func edit(_ change: (inout String) -> Void) -> PanelAction {
        change(&filter)
        highlighted = nil
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
