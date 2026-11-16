import Foundation

// MARK: - Parsing LES menuconfig.ini

public struct LESItem: Equatable, Sendable {
    public let display: String
    public let query: String
}

public struct LESCategory: Equatable, Sendable {
    public let name: String
    public var items: [LESItem]
}

/// Parses the Live Enhancement Suite plugin menu (`~/.les/menuconfig.ini`): `/Category`, `//Sub`, `..` back up,
/// item pairs (display name line, search query line), `--` dividers, `;` comments, `/nocategory`, trailing `End`.
/// Nested folders become categories of their own (named after the folder); dividers are dropped.
public enum LESMenuParser {
    public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".les/menuconfig.ini")

    public static func parse(_ text: String) -> [LESCategory] {
        var categories: [LESCategory] = []
        var stack: [Int] = []          // indices into categories for the current folder path
        var current: Int?
        var pendingDisplay: String?

        func open(_ name: String, depth: Int) {
            pendingDisplay = nil
            stack = Array(stack.prefix(max(depth - 1, 0)))
            categories.append(LESCategory(name: name, items: []))
            stack.append(categories.count - 1)
            current = categories.count - 1
        }

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        for line in lines {
            if line.isEmpty || line.hasPrefix(";") || line == "--" { continue }
            if line == ".." {
                pendingDisplay = nil
                if stack.count > 1 { stack.removeLast() }
                current = stack.last
                continue
            }
            if line.hasPrefix("/") {
                let depth = line.prefix { $0 == "/" }.count
                let name = String(line.dropFirst(depth)).trimmingCharacters(in: .whitespaces)
                open(name.lowercased() == "nocategory" ? Loc.t("Sonstiges", "Other") : name, depth: depth)
                continue
            }
            guard let display = pendingDisplay else {
                pendingDisplay = line
                continue
            }
            pendingDisplay = nil
            if display.lowercased() == "readme" { continue }
            if current == nil { open(Loc.t("Sonstiges", "Other"), depth: 1) }
            categories[current!].items.append(LESItem(display: display, query: line))
        }
        // A dangling single line is LES's "End" marker (or garbage) — never an item.
        return mergeDuplicateNames(categories.filter { !$0.items.isEmpty })
    }

    /// "/nocategory" can appear several times; same-named folders are merged in first-seen order.
    private static func mergeDuplicateNames(_ categories: [LESCategory]) -> [LESCategory] {
        var result: [LESCategory] = []
        for c in categories {
            if let i = result.firstIndex(where: { $0.name == c.name }) { result[i].items += c.items } else { result.append(c) }
        }
        return result
    }
}

// MARK: - Queries

public enum LESFormat: Equatable, Sendable { case vst3, vst2, au, maxForLive }

/// An LES search query: quotes removed, trailing format hint (`vst3`, `vst`, `au`, `amxd`) and file extension parsed.
public struct LESQuery: Equatable, Sendable {
    public let text: String
    public let format: LESFormat?
    public let isPreset: Bool

    public init(text: String, format: LESFormat?, isPreset: Bool) {
        self.text = text; self.format = format; self.isPreset = isPreset
    }

    private static let hints: [String: LESFormat] = ["vst3": .vst3, "vst": .vst2, "au": .au, "amxd": .maxForLive]
    private static let presetExtensions = [".adv", ".adg", ".aupreset", ".fxp", ".fxb", ".vstpreset", ".als", ".alc"]

    public init(_ raw: String) {
        var tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        var format: LESFormat?
        if tokens.count > 1, let hint = Self.hints[tokens.last!.lowercased()] {
            format = hint
            tokens.removeLast()
        }
        var text = tokens.joined(separator: " ").replacingOccurrences(of: "\"", with: "").lowercased()
        var preset = false
        if text.hasSuffix(".amxd") {
            text.removeLast(5); format = .maxForLive
        } else if let ext = Self.presetExtensions.first(where: { text.hasSuffix($0) }) {
            text.removeLast(ext.count); preset = true
        }
        self.init(text: LESMatcher.normalize(text), format: format, isPreset: preset)
    }
}

// MARK: - Matching against Live's plugin list

public struct LESMatch: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case found, uncertain, notFound }
    public var status: Status
    public var item: PluginItem?
    /// For uncertain matches: one candidate per distinct plugin name, best first.
    public var alternatives: [PluginItem]
    /// The LES entry pointed at a preset/rack file; presets cannot be imported, only a suggested plugin.
    public var isPreset: Bool

    public static func manual(_ item: PluginItem) -> LESMatch {
        LESMatch(status: .found, item: item, alternatives: [], isPreset: false)
    }
}

public struct LESMatcher {
    private let items: [(item: PluginItem, name: String)]

    public init(items: [PluginItem]) {
        self.items = items.map { ($0, Self.normalize($0.name)) }
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Query matches score 100 exact / 90 exact ignoring spaces & punctuation / 85 prefix / 75 contains / 60 all words;
    /// the LES display name a bit lower (95/85/80/70/55) so the search query stays decisive. Below 55 nothing matched.
    /// A single plugin name scoring ≥ 70 counts as found; ties between names or weaker hits are "uncertain".
    public func match(display: String, query rawQuery: String) -> LESMatch {
        let query = LESQuery(rawQuery)
        let displayText = Self.normalize(display)
        var best = 0
        var scored: [(item: PluginItem, name: String, score: Int)] = []
        for (item, name) in items {
            let s = max(Self.score(name, query.text, [100, 90, 85, 75, 60]), Self.score(name, displayText, [95, 85, 80, 70, 55]))
            guard s >= 55 else { continue }
            scored.append((item, name, s))
            best = max(best, s)
        }
        guard best >= 55 else { return LESMatch(status: .notFound, item: nil, alternatives: [], isPreset: query.isPreset) }

        // One representative per distinct name, preferring the hinted format.
        var byName: [String: (item: PluginItem, score: Int)] = [:]
        for s in scored {
            if let existing = byName[s.name], rank(existing.item, query.format) <= rank(s.item, query.format) { continue }
            byName[s.name] = (s.item, s.score)
        }
        let ranked = byName.values.sorted { a, b in
            a.score != b.score ? a.score > b.score : a.item.name.localizedCaseInsensitiveCompare(b.item.name) == .orderedAscending
        }
        let top = ranked.filter { $0.score == best }
        let chosen = top[0].item
        let unique = top.count == 1
        let status: LESMatch.Status = (unique && best >= 70 && !query.isPreset) ? .found : .uncertain
        return LESMatch(status: status, item: chosen,
                        alternatives: status == .found ? [] : Array(ranked.prefix(8).map(\.item)),
                        isPreset: query.isPreset)
    }

    private static func score(_ name: String, _ q: String, _ points: [Int]) -> Int {
        guard !q.isEmpty else { return 0 }
        if name == q { return points[0] }
        let (cn, cq) = (compact(name), compact(q))
        if !cq.isEmpty, cn == cq { return points[1] }
        if name.hasPrefix(q) { return points[2] }
        if name.contains(q) || (cq.count >= 4 && cn.contains(cq)) { return points[3] }
        let words = q.split(separator: " ")
        if words.count > 1, words.allSatisfy({ name.contains($0) }) { return points[4] }
        return 0
    }

    /// "UADx Lexicon 224" and "uadx lexicon224" compare equal.
    private static func compact(_ s: String) -> String {
        String(s.unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }

    /// Lower is better: the hinted format first; without a hint Live's own devices, then VST3, AU, VST2, Max for Live.
    private func rank(_ item: PluginItem, _ hint: LESFormat?) -> Int {
        let format = Self.format(of: item)
        if let hint, format == hint { return -1 }
        switch format {
        case nil: return 0
        case .vst3?: return 1
        case .au?: return 2
        case .vst2?: return 3
        case .maxForLive?: return 4
        }
    }

    static func format(of item: PluginItem) -> LESFormat? {
        if item.source == .maxForLive { return .maxForLive }
        guard item.source == .plugins else { return nil }
        let f = item.path.first ?? ""
        if f == "VST3" { return .vst3 }
        if f.hasPrefix("AU") { return .au }
        if f == "VST" { return .vst2 }
        return nil
    }
}

// MARK: - Editable import preview

public struct ImportRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var display: String
    public let query: String
    public var match: LESMatch
}

public struct ImportCategory: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var rows: [ImportRow]
}

public enum ImportMode: Sendable { case replace, add }

public struct ImportDraft: Equatable, Sendable {
    public struct Counts: Equatable, Sendable {
        public var found = 0, uncertain = 0, notFound = 0
        public init(found: Int = 0, uncertain: Int = 0, notFound: Int = 0) {
            self.found = found; self.uncertain = uncertain; self.notFound = notFound
        }
    }

    public var categories: [ImportCategory]

    public init(categories: [ImportCategory] = []) { self.categories = categories }

    public static func make(text: String, items: [PluginItem]) -> ImportDraft {
        let matcher = LESMatcher(items: items)
        return ImportDraft(categories: LESMenuParser.parse(text).map { les in
            var seen = Set<String>()
            let rows: [ImportRow] = les.items.compactMap { it in
                let match = matcher.match(display: it.display, query: it.query)
                let key = match.item?.uri ?? "query:" + it.query.lowercased()
                guard seen.insert(key).inserted else { return nil }
                return ImportRow(id: UUID(), display: it.display, query: it.query, match: match)
            }
            return ImportCategory(id: UUID(), name: les.name, rows: rows)
        })
    }

    public var counts: Counts {
        categories.flatMap(\.rows).reduce(into: Counts()) { c, row in
            switch row.match.status {
            case .found: c.found += 1
            case .uncertain: c.uncertain += 1
            case .notFound: c.notFound += 1
            }
        }
    }

    private func index(_ id: UUID) -> Int? { categories.firstIndex { $0.id == id } }

    public mutating func removeRow(_ rowID: UUID, from categoryID: UUID) {
        guard let c = index(categoryID) else { return }
        categories[c].rows.removeAll { $0.id == rowID }
    }

    public mutating func moveRow(in categoryID: UUID, from: Int, to: Int) {
        guard let c = index(categoryID), categories[c].rows.indices.contains(from),
              (0..<categories[c].rows.count).contains(to) else { return }
        categories[c].rows.insert(categories[c].rows.remove(at: from), at: to)
    }

    public mutating func renameCategory(_ id: UUID, to name: String) {
        guard let c = index(id) else { return }
        categories[c].name = name
    }

    public mutating func removeCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
    }

    public mutating func moveCategory(from: Int, to: Int) {
        guard categories.indices.contains(from), (0..<categories.count).contains(to) else { return }
        categories.insert(categories.remove(at: from), at: to)
    }

    /// Appends the source's rows to the target (skipping plugins already there) and removes the source.
    public mutating func mergeCategory(_ sourceID: UUID, into targetID: UUID) {
        guard sourceID != targetID, let s = index(sourceID), let t = index(targetID) else { return }
        let existing = Set(categories[t].rows.compactMap { $0.match.item?.uri })
        categories[t].rows += categories[s].rows.filter { $0.match.item.map { !existing.contains($0.uri) } ?? true }
        categories.remove(at: s)
    }

    public mutating func setMatch(_ item: PluginItem, for rowID: UUID, in categoryID: UUID) {
        guard let c = index(categoryID), let r = categories[c].rows.firstIndex(where: { $0.id == rowID }) else { return }
        categories[c].rows[r].match = .manual(item)
    }
}

public extension LauncherConfig {
    /// Pushes an import preview into the menu. `.replace` swaps every category except Favorites;
    /// `.add` merges into same-named categories and appends new ones. Rows without a plugin are skipped.
    /// The LES display name is kept as display name when it differs from the plugin's name.
    mutating func apply(_ draft: ImportDraft, mode: ImportMode) {
        if mode == .replace { categories.removeAll { !$0.isFavorites } }
        for imported in draft.categories {
            let targetID: UUID
            if mode == .add, let existing = categories.first(where: {
                !$0.isFavorites && $0.name.localizedCaseInsensitiveCompare(imported.name) == .orderedSame
            }) {
                targetID = existing.id
            } else {
                targetID = addCategory(named: imported.name)
            }
            for row in imported.rows {
                guard let item = row.match.item, row.match.status != .notFound else { continue }
                addEntry(item, to: targetID)
                guard LESMatcher.normalize(row.display) != LESMatcher.normalize(item.name),
                      let c = categories.firstIndex(where: { $0.id == targetID }),
                      let e = categories[c].entries.lastIndex(where: { $0.uri == item.uri }),
                      categories[c].entries[e].displayName == nil else { continue }
                categories[c].entries[e].displayName = row.display
            }
        }
    }

    /// Replaces the menu (categories only — shortcuts and language stay). Guarantees one Favorites category at index 0.
    mutating func restoreMenu(_ restored: [Category]) {
        var cats = restored
        if let f = cats.firstIndex(where: \.isFavorites) {
            let fav = cats.remove(at: f)
            for i in cats.indices { cats[i].isFavorites = false }
            cats.insert(fav, at: 0)
        } else {
            cats.insert(Category(name: "Favorites", isFavorites: true), at: 0)
        }
        categories = cats
    }
}
