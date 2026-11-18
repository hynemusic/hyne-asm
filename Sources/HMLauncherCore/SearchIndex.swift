import Foundation

/// What searching needs from Live's plugin list, worked out once and shared by the panel and the quick search.
/// Building it costs ~50–130 ms for ~3,500 items (merging formats, sorting, guessing icons), so it is rebuilt only
/// when the plugin list or the menu changes — not on every double-right-click or ⌃Space.
public final class SearchIndex: @unchecked Sendable {
    public let resolver: EntryResolver.Index
    /// uri → usage key (all formats of a plugin share one key).
    public let usageKey: [String: String]
    /// One row per plugin in its best format, alphabetical, icon guessed, colour resolved, marked as a global hit.
    public let globalRows: [PanelRow]
    public let globalPrepared: [SearchMatcher.Prepared]
    /// `Popularity.score` per global row (tie-break after the user's own counts).
    public let globalPopularity: [Int]
    private let rowIndexByKey: [String: Int]

    public init(items: [PluginItem], config: LauncherConfig) {
        resolver = EntryResolver.Index(items)
        let keys = PluginVariants.Keys(items)
        var usageKey: [String: String] = [:]
        for item in items { usageKey[item.uri] = keys.key(item) }
        self.usageKey = usageKey
        let rows = PluginVariants.collapse(items).map(\.preferred)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { item in
                PanelRow(uri: item.uri, name: item.name, source: item.source, path: item.path,
                         iconID: IconGuesser.guess(item), title: item.name, isAvailable: true,
                         isGlobal: true, usageKey: keys.key(item), colorID: config.colorID(for: item))
            }
        globalRows = rows
        globalPrepared = rows.map { SearchMatcher.Prepared($0.title) }
        globalPopularity = rows.map { Popularity.score($0.title) }
        var byKey: [String: Int] = [:]
        for (i, r) in rows.enumerated() where byKey[r.usageKey] == nil { byKey[r.usageKey] = i }
        rowIndexByKey = byKey
    }

    public func globalRow(forKey key: String) -> PanelRow? {
        rowIndexByKey[key].map { globalRows[$0] }
    }
}
