import Foundation

/// Forgiving name search: case, spaces and punctuation don't matter, words may be abbreviated and every
/// typed word must appear. "pro q 4", "proq4", "pro 4" all find "Pro-Q 4"; "pro 4" does not find "Pro-L 2".
/// Higher score = better match (name starts with it > words in order > words anywhere > letters inside).
public enum SearchMatcher {
    public struct Prepared: Sendable {
        let lower: String
        let compact: String
        let words: [String]

        public init(_ text: String) {
            lower = text.lowercased()
            compact = SearchMatcher.compact(lower)
            words = SearchMatcher.words(text)
        }
    }

    public static func score(_ name: String, _ query: String) -> Int? {
        score(Prepared(name), Prepared(query))
    }

    public static func score(_ name: Prepared, _ query: Prepared) -> Int? {
        let q = query.lower.trimmingCharacters(in: .whitespaces)
        if q.isEmpty || query.compact.isEmpty { return 0 }
        if name.lower.hasPrefix(q) { return 100 }
        if name.compact.hasPrefix(query.compact) { return 90 }
        if prefixesInOrder(query.words, name.words) { return query.words.first.map { name.words.first?.hasPrefix($0) == true } == true ? 85 : 80 }
        if query.words.allSatisfy({ w in name.words.contains { $0.hasPrefix(w) } }) { return 70 }
        if name.compact.contains(query.compact) { return 60 }
        if query.words.allSatisfy({ name.compact.contains($0) }) { return 50 }
        return nil
    }

    private static func prefixesInOrder(_ query: [String], _ name: [String]) -> Bool {
        var i = 0
        for w in query {
            guard let hit = name[i...].firstIndex(where: { $0.hasPrefix(w) }) else { return false }
            i = hit + 1
        }
        return true
    }

    static func compact(_ s: String) -> String {
        String(s.unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }

    /// Words split at spaces/punctuation and at camelCase ("ValhallaVintageVerb" → valhalla, vintage, verb).
    static func words(_ s: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previous: Character?
        for ch in s {
            if !(ch.isLetter || ch.isNumber) {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                if let p = previous, p.isLowercase, ch.isUppercase, !current.isEmpty { result.append(current); current = "" }
                current.append(ch)
            }
            previous = ch
        }
        if !current.isEmpty { result.append(current) }
        return result.map { $0.lowercased() }
    }
}

/// How often each plugin was inserted (key: `PluginVariants.Keys.key`, so all formats count together).
public final class UsageStore {
    public private(set) var counts: [String: Int]
    private let url: URL

    public init(url: URL) {
        self.url = url
        counts = (try? JSONDecoder().decode([String: Int].self, from: Data(contentsOf: url))) ?? [:]
    }

    public static var defaultURL: URL {
        ConfigStore.defaultURL.deletingLastPathComponent().appendingPathComponent("usage.json")
    }

    public func record(_ key: String) {
        counts[key, default: 0] += 1
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(counts).write(to: url, options: .atomic)
    }
}
