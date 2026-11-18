import Foundation

public struct QuickResult: Equatable, Sendable {
    public let row: PanelRow
    /// Where the plugin is filed ("Effects / UAD"); nil for hits from the whole plugin list.
    public let place: String?
}

/// The ⌃Space search: every category (and folder) first, then all installed plugins, ranked by match quality
/// and insert count. With nothing typed it offers the most used plugins (or Favorites when nothing is used yet).
public struct QuickSearch {
    public static let maxResults = 30
    public static let maxSuggestions = 8

    private let local: [(row: PanelRow, place: String, prepared: SearchMatcher.Prepared, order: Int)]
    private let index: SearchIndex
    private let favorites: [QuickResult]
    private let usage: [String: Int]
    private let rules: [SearchRule]

    /// Builds the index on the spot (tests, one-off use).
    public init(config: LauncherConfig, items: [PluginItem], usage: [String: Int]) {
        self.init(config: config, index: SearchIndex(items: items, config: config), usage: usage)
    }

    public init(config: LauncherConfig, index: SearchIndex, usage: [String: Int]) {
        self.usage = usage
        self.index = index
        rules = config.searchRules

        func row(_ e: Entry) -> PanelRow {
            let resolved = index.resolver.resolve(e)
            let uri = resolved?.uri ?? e.uri
            return PanelRow(uri: uri, name: e.name, source: e.source, path: resolved?.path ?? e.path, iconID: e.iconID,
                            title: e.title, isAvailable: resolved != nil,
                            usageKey: index.usageKey[uri] ?? uri, colorID: config.colorID(for: e))
        }

        var seen = Set<String>()
        var local: [(PanelRow, String, SearchMatcher.Prepared, Int)] = []
        for category in config.categories {
            for e in category.entries {
                let filed: [(Entry, String)] = e.isFolder
                    ? (e.children ?? []).map { ($0, "\(category.name) / \(e.title)") }
                    : [(e, category.name)]
                for (entry, place) in filed {
                    let r = row(entry)
                    guard seen.insert(r.usageKey).inserted else { continue }
                    local.append((r, place, SearchMatcher.Prepared(r.title), local.count))
                }
            }
        }
        self.local = local
        let favoritesCategory = config.categories.first(where: \.isFavorites)
        favorites = (favoritesCategory?.entries ?? []).filter { !$0.isFolder }
            .prefix(Self.maxSuggestions).map { QuickResult(row: row($0), place: favoritesCategory?.name) }
    }

    private func uses(_ r: PanelRow) -> Int { usage[r.usageKey] ?? 0 }

    public func results(_ query: String) -> [QuickResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return suggestions }
        let q = SearchMatcher.Prepared(query)
        let localHits = local.compactMap { l in SearchMatcher.score(l.prepared, q).map { (l, $0) } }
            .sorted { a, b in
                a.1 != b.1 ? a.1 > b.1 : (uses(a.0.row) != uses(b.0.row) ? uses(a.0.row) > uses(b.0.row) : a.0.order < b.0.order)
            }
            .map { QuickResult(row: $0.0.row, place: $0.0.place) }
        let shown = Set(localHits.map(\.row.usageKey))
        var global: [(row: PanelRow, score: Int)] = []
        for (i, r) in index.globalRows.enumerated() where !shown.contains(r.usageKey) {
            if let score = SearchMatcher.score(index.globalPrepared[i], q) { global.append((r, score)) }
        }
        global.sort { a, b in a.score != b.score ? a.score > b.score : uses(a.row) > uses(b.row) }
        let globalHits = global.map { QuickResult(row: $0.row, place: nil) }
        // The user's search rules: hidden results go, pinned ones lead (even if their name doesn't match).
        let shaped = SearchTuning.apply(localHits + globalHits, key: \.row.usageKey, rule: SearchTuning.rule(for: query, in: rules)) { key in
            if let l = local.first(where: { $0.row.usageKey == key }) { return QuickResult(row: l.row, place: l.place) }
            return index.globalRow(forKey: key).map { QuickResult(row: $0, place: nil) }
        }
        return Array(shaped.prefix(Self.maxResults))
    }

    /// Most used plugins first; without any history, the Favorites.
    private var suggestions: [QuickResult] {
        let byUse = (local.map { ($0.row, Optional($0.place)) } + index.globalRows.map { ($0, nil as String?) })
            .filter { uses($0.0) > 0 }
        var seen = Set<String>()
        let ranked = byUse.sorted { uses($0.0) > uses($1.0) }
            .filter { seen.insert($0.0.usageKey).inserted }
            .prefix(Self.maxSuggestions)
            .map { QuickResult(row: $0.0, place: $0.1) }
        return ranked.isEmpty ? favorites : Array(ranked)
    }
}

/// Typing and keys of the quick search window.
public struct QuickSearchState {
    private let search: QuickSearch
    private var input = TextInput()
    public var query: String { input.text }
    /// ⌘A selected the whole query (drawn highlighted; the next key replaces it).
    public var isQuerySelected: Bool { input.isAllSelected }
    public private(set) var highlighted = 0
    public private(set) var results: [QuickResult]

    public init(search: QuickSearch) {
        self.search = search
        results = search.results("")
    }

    public mutating func handle(_ key: PanelKey) -> PanelAction {
        switch key {
        case .down:
            input.deselect()
            highlighted = min(highlighted + 1, max(results.count - 1, 0))
        case .up:
            input.deselect()
            highlighted = max(highlighted - 1, 0)
        case .returnKey:
            guard results.indices.contains(highlighted), results[highlighted].row.isAvailable else { return .none }
            return .insert(results[highlighted].row)
        case .escape: return .close
        case .left, .right, .tab: break
        default:
            let before = query
            if input.apply(key), query != before {
                results = search.results(query)
                highlighted = 0
            }
        }
        return .none
    }

    public mutating func highlight(_ index: Int) {
        if results.indices.contains(index) { highlighted = index }
    }

}
