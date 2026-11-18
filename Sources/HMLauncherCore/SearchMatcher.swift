import Foundation

/// Forgiving name search: case, spaces and punctuation don't matter, words may be abbreviated and every
/// typed word must appear. "pro q 4", "proq4", "pro 4" all find "Pro-Q 4"; "pro 4" does not find "Pro-L 2".
/// Higher score = better match (name starts with it > words in order > words anywhere > letters inside).
public enum SearchMatcher {
    public struct Prepared: Sendable {
        let lower: String
        let compact: String
        let words: [String]
        /// `words` as UTF-8, prepared once for the typo check.
        let wordBytes: [[UInt8]]

        public init(_ text: String) {
            lower = text.lowercased()
            compact = SearchMatcher.compact(lower)
            words = SearchMatcher.words(text)
            wordBytes = words.map { Array($0.utf8) }
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
        if typoMatch(query.wordBytes, name.wordBytes) { return typoScore }
        return nil
    }

    /// Score of a match with a typo — below every exact match, above a tag match.
    public static let typoScore = 40
    /// Score of an item found only through its kind ("comp" → every compressor).
    public static let tagScore = 30

    /// Name score, else a tag hit when the item's icon kind is one the query stands for.
    public static func score(_ name: Prepared, _ query: Prepared, iconID: String, tagIcons: Set<String>) -> Int? {
        if let s = score(name, query) { return s }
        return tagIcons.contains(iconID) ? tagScore : nil
    }

    /// Every typed word appears in the name, words of ≥ 4 letters with one typo (≥ 7 letters: two).
    /// Shorter words and numbers must match exactly — too many names are one edit away from "eq" or "pro".
    /// Typos in the first letter are not forgiven: that keeps the check cheap for 20,000 names.
    static func typoMatch(_ query: [[UInt8]], _ name: [[UInt8]]) -> Bool {
        guard !query.isEmpty, query.contains(where: { $0.count >= 4 }) else { return false }
        return query.allSatisfy { w in
            if name.contains(where: { $0.starts(with: w) }) { return true }   // exact: no distance needed
            // Short words and numbers must match exactly ("Pro-Q 4" is not "Pro-Q 3").
            if w.count < 4 || !w.contains(where: { (97...122).contains($0) }) { return false }
            let allowed = w.count >= 7 ? 2 : 1
            return w.withUnsafeBufferPointer { wp in
                name.contains { n in
                    guard n.first == w.first else { return false }
                    return n.withUnsafeBufferPointer { np in
                        let prefix = UnsafeBufferPointer(rebasing: np[..<min(np.count, wp.count)])
                        return editDistance(wp, prefix, limit: allowed) <= allowed
                            || (abs(np.count - wp.count) <= allowed && editDistance(wp, np, limit: allowed) <= allowed)
                    }
                }
            }
        }
    }

    /// Edit distance with swapped neighbours counting as one edit ("sreum" → "serum"). Stops early once every
    /// path exceeds `limit` (returns limit + 1 then). Rows live in one stack buffer: no allocation per call.
    static func editDistance(_ a: UnsafeBufferPointer<UInt8>, _ b: UnsafeBufferPointer<UInt8>, limit: Int = .max) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        if abs(a.count - b.count) > limit { return limit + 1 }
        let width = b.count + 1
        return withUnsafeTemporaryAllocation(of: Int.self, capacity: width * 3) { buf in
            var prev2 = 0, prev = width, cur = 2 * width   // row offsets
            for j in 0...b.count { buf[prev + j] = j; buf[prev2 + j] = 0 }
            for i in 1...a.count {
                buf[cur] = i
                var rowMin = i
                for j in 1...b.count {
                    let cost = a[i - 1] == b[j - 1] ? 0 : 1
                    var v = Swift.min(buf[prev + j] + 1, buf[cur + j - 1] + 1, buf[prev + j - 1] + cost)
                    if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { v = Swift.min(v, buf[prev2 + j - 2] + 1) }
                    buf[cur + j] = v
                    rowMin = Swift.min(rowMin, v)
                }
                if rowMin > limit { return limit + 1 }
                (prev2, prev, cur) = (prev, cur, prev2)
            }
            return buf[prev + b.count]
        }
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        Array(a.utf8).withUnsafeBufferPointer { ap in Array(b.utf8).withUnsafeBufferPointer { bp in editDistance(ap, bp) } }
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

    /// Posted after every change, so an open Stats page can refresh.
    public static let didChange = Notification.Name("HYNEASM.usageDidChange")

    public func record(_ key: String) {
        counts[key, default: 0] += 1
        save()
    }

    /// Replaces everything (import "replace", reset with `[:]`).
    public func replaceAll(_ newCounts: [String: Int]) {
        counts = newCounts.filter { $0.value > 0 }
        save()
    }

    /// Adds imported counts to the existing ones.
    public func merge(_ other: [String: Int]) {
        for (key, value) in other where value > 0 { counts[key, default: 0] += value }
        save()
    }

    public func reset() { replaceAll([:]) }

    /// Forgets one plugin's count (Stats page), so it no longer ranks higher in search.
    public func remove(_ key: String) {
        counts[key] = nil
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(counts).write(to: url, options: .atomic)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

/// The file the Stats page exports and imports: the insert counts that rank search results.
public struct UsageExport: Codable, Equatable {
    public static let formatID = "hyne-asm-usage"
    public static let fileExtension = "hmlusage"

    public var format = UsageExport.formatID
    public var version = 1
    public var exported: Date
    public var counts: [String: Int]

    public init(counts: [String: Int], exported: Date = Date()) {
        self.counts = counts
        self.exported = exported
    }

    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public enum ReadError: Error { case notUsageFile }

    /// Reads an export, or a raw usage.json copied out of the app's folder.
    public static func read(_ data: Data) throws -> [String: Int] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(UsageExport.self, from: data), file.format == formatID { return file.counts }
        if let raw = try? decoder.decode([String: Int].self, from: data), raw.keys.allSatisfy({ $0.contains("|") }) { return raw }
        throw ReadError.notUsageFile
    }
}
