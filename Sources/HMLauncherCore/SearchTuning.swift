import Foundation

/// The user's own shaping of search results for a search term: results pinned to the top (in this order)
/// and results hidden. A rule for "ser" also applies to "seru", "serum" … — the longest matching rule wins.
public struct SearchRule: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    /// Normalized: lowercase, single spaces.
    public var query: String
    /// Usage keys (`PluginVariants.Keys.key`) shown first, in this order. A pinned plugin is shown even if its
    /// name doesn't contain the search term ("verb" → Valhalla).
    public var pinned: [String] = []
    /// Usage keys never shown for this search.
    public var hidden: [String] = []

    public init(query: String, pinned: [String] = [], hidden: [String] = []) {
        self.query = SearchTuning.normalize(query)
        self.pinned = pinned
        self.hidden = hidden
    }

    var isEmpty: Bool { pinned.isEmpty && hidden.isEmpty }
}

public enum SearchTuning {
    public static func normalize(_ query: String) -> String {
        query.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The rule for a typed search: the longest rule query the search starts with.
    public static func rule(for query: String, in rules: [SearchRule]) -> SearchRule? {
        let q = normalize(query)
        guard !q.isEmpty else { return nil }
        return rules.filter { !$0.query.isEmpty && q.hasPrefix($0.query) }.max { $0.query.count < $1.query.count }
    }

    /// Hidden results removed, pinned ones moved to the front in pin order. Pinned keys missing from `results`
    /// are added through `inject` (return nil to skip them).
    public static func apply<T>(_ results: [T], key: (T) -> String, rule: SearchRule?, inject: (String) -> T? = { _ in nil }) -> [T] {
        guard let rule else { return results }
        let hidden = Set(rule.hidden)
        let visible = results.filter { !hidden.contains(key($0)) }
        var byKey: [String: T] = [:]
        for r in visible where byKey[key(r)] == nil { byKey[key(r)] = r }
        var front: [T] = []
        var used = Set<String>()
        for k in rule.pinned where !hidden.contains(k) && !used.contains(k) {
            if let r = byKey[k] ?? inject(k) { front.append(r); used.insert(k) }
        }
        return front + visible.filter { !used.contains(key($0)) }
    }
}

public extension LauncherConfig {
    func searchRule(exactly query: String) -> SearchRule? {
        let q = SearchTuning.normalize(query)
        return searchRules.first { $0.query == q }
    }

    mutating func pinSearchResult(_ key: String, for query: String) {
        editRule(query) { rule in
            rule.hidden.removeAll { $0 == key }
            if !rule.pinned.contains(key) { rule.pinned.append(key) }
        }
    }

    mutating func unpinSearchResult(_ key: String, for query: String) {
        editRule(query) { $0.pinned.removeAll { $0 == key } }
    }

    mutating func hideSearchResult(_ key: String, for query: String) {
        editRule(query) { rule in
            rule.pinned.removeAll { $0 == key }
            if !rule.hidden.contains(key) { rule.hidden.append(key) }
        }
    }

    mutating func unhideSearchResult(_ key: String, for query: String) {
        editRule(query) { $0.hidden.removeAll { $0 == key } }
    }

    /// Moves a pinned result up (-1) or down (+1).
    mutating func movePinnedSearchResult(_ key: String, by offset: Int, for query: String) {
        editRule(query) { rule in
            guard let i = rule.pinned.firstIndex(of: key) else { return }
            let j = min(max(i + offset, 0), rule.pinned.count - 1)
            rule.pinned.remove(at: i)
            rule.pinned.insert(key, at: j)
        }
    }

    mutating func removeSearchRule(_ id: UUID) {
        searchRules.removeAll { $0.id == id }
    }

    /// Creates the rule on first use and drops it again once it is empty. A new rule for "serum" starts as a copy
    /// of the "ser" rule that applied so far, so shaping a longer search doesn't lose the shorter one's choices.
    private mutating func editRule(_ query: String, _ change: (inout SearchRule) -> Void) {
        let q = SearchTuning.normalize(query)
        guard !q.isEmpty else { return }
        let inherited = SearchTuning.rule(for: q, in: searchRules)
        var rule = searchRules.first { $0.query == q }
            ?? SearchRule(query: q, pinned: inherited?.pinned ?? [], hidden: inherited?.hidden ?? [])
        change(&rule)
        searchRules.removeAll { $0.query == q }
        if !rule.isEmpty { searchRules.append(rule) }
        searchRules.sort { $0.query < $1.query }
    }
}
