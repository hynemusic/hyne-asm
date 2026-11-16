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
    private let global: [(row: PanelRow, prepared: SearchMatcher.Prepared)]
    private let favorites: [QuickResult]
    private let usage: [String: Int]

    public init(config: LauncherConfig, items: [PluginItem], usage: [String: Int]) {
        self.usage = usage
        let index = EntryResolver.Index(items)
        let keys = PluginVariants.Keys(items)
        let byURI = Dictionary(items.map { ($0.uri, $0) }, uniquingKeysWith: { a, _ in a })

        func row(_ e: Entry) -> PanelRow {
            let resolved = index.resolve(e)
            let uri = resolved?.uri ?? e.uri
            return PanelRow(uri: uri, name: e.name, source: e.source, path: resolved?.path ?? e.path, iconID: e.iconID,
                            title: e.title, isAvailable: resolved != nil,
                            usageKey: byURI[uri].map(keys.key) ?? uri, colorID: config.colorID(for: e))
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
        favorites = (config.categories.first(where: \.isFavorites)?.entries ?? []).filter { !$0.isFolder }
            .prefix(Self.maxSuggestions).map { QuickResult(row: row($0), place: config.categories.first(where: \.isFavorites)?.name) }

        global = PluginVariants.collapse(items).map(\.preferred)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { item in
                let r = PanelRow(uri: item.uri, name: item.name, source: item.source, path: item.path,
                                 iconID: IconGuesser.guess(item), title: item.name, isAvailable: true,
                                 isGlobal: true, usageKey: keys.key(item), colorID: config.colorID(for: item))
                return (r, SearchMatcher.Prepared(item.name))
            }
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
        let globalHits = global.filter { !shown.contains($0.row.usageKey) }
            .compactMap { g in SearchMatcher.score(g.prepared, q).map { (g.row, $0) } }
            .sorted { a, b in a.1 != b.1 ? a.1 > b.1 : uses(a.0) > uses(b.0) }
            .map { QuickResult(row: $0.0, place: nil) }
        return Array((localHits + globalHits).prefix(Self.maxResults))
    }

    /// Most used plugins first; without any history, the Favorites.
    private var suggestions: [QuickResult] {
        let byUse = (local.map { ($0.row, Optional($0.place)) } + global.map { ($0.row, nil as String?) })
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
    public private(set) var query = ""
    public private(set) var highlighted = 0
    public private(set) var results: [QuickResult]

    public init(search: QuickSearch) {
        self.search = search
        results = search.results("")
    }

    public mutating func handle(_ key: PanelKey) -> PanelAction {
        switch key {
        case .character(let c): setQuery(query + String(c))
        case .digit(let d): setQuery(query + String(d))
        case .backspace: if !query.isEmpty { setQuery(String(query.dropLast())) }
        case .down: highlighted = min(highlighted + 1, max(results.count - 1, 0))
        case .up: highlighted = max(highlighted - 1, 0)
        case .returnKey:
            guard results.indices.contains(highlighted), results[highlighted].row.isAvailable else { return .none }
            return .insert(results[highlighted].row)
        case .escape: return .close
        case .left, .right, .tab: break
        }
        return .none
    }

    public mutating func highlight(_ index: Int) {
        if results.indices.contains(index) { highlighted = index }
    }

    private mutating func setQuery(_ q: String) {
        query = q
        results = search.results(q)
        highlighted = 0
    }
}
