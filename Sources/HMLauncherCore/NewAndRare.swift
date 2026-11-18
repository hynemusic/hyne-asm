import Foundation

/// When the app first saw each item in Live's list (`seen.json`), to mark newly installed plugins and presets.
public final class SeenStore: @unchecked Sendable {
    public let url: URL
    private(set) var firstSeen: [String: Date]
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        firstSeen = (try? decoder.decode([String: Date].self, from: Data(contentsOf: url))) ?? [:]
    }

    public static var defaultURL: URL {
        ConfigStore.defaultURL.deletingLastPathComponent().appendingPathComponent("seen.json")
    }

    /// Records items not seen before. On the very first run everything counts as known (no flood of NEW badges).
    public func update(with items: [PluginItem], now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        let firstRun = firstSeen.isEmpty
        var changed = false
        for item in items where firstSeen[item.uri] == nil {
            firstSeen[item.uri] = firstRun ? .distantPast : now
            changed = true
        }
        guard changed else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(firstSeen).write(to: url, options: .atomic)
    }

    func date(_ uri: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return firstSeen[uri]
    }
}

public enum NewItems {
    /// How long a newly installed item stays marked as new.
    public static let window: TimeInterval = 14 * 86_400

    /// Items first seen within the window that are neither filed in a category nor ever inserted.
    public static func uris(items: [PluginItem], seen: SeenStore, config: LauncherConfig, usage: [String: Int], now: Date = Date()) -> Set<String> {
        let keys = PluginVariants.Keys(items)
        let filed = config.allPluginEntries
        let filedURIs = Set(filed.map(\.uri))
        let filedNames = Set(filed.map { $0.source.rawValue + "|" + $0.name })
        var result = Set<String>()
        for item in items {
            guard let date = seen.date(item.uri), now.timeIntervalSince(date) < window, date != .distantPast else { continue }
            if filedURIs.contains(item.uri) || filedNames.contains(item.source.rawValue + "|" + item.name) { continue }
            if (usage[keys.key(item)] ?? 0) > 0 { continue }
            result.insert(item.uri)
        }
        return result
    }
}

/// Panel entries that are hardly ever used — candidates to remove (Stats page).
public struct RareEntry: Identifiable, Equatable, Sendable {
    public var id: UUID { entry.id }
    public let entry: Entry
    public let categoryID: UUID
    /// "Effects" or "Effects / Dyn".
    public let place: String
    public let count: Int
}

public enum RarelyUsed {
    /// Entries (plugins, chains, actions — also inside folders) inserted at most `threshold` times, fewest first.
    /// Entries the user chose to keep are left out.
    public static func entries(config: LauncherConfig, index: SearchIndex, usage: [String: Int], threshold: Int = 1) -> [RareEntry] {
        let kept = Set(config.keptEntries)
        var result: [RareEntry] = []
        for category in config.categories {
            for e in category.entries {
                let filed = e.isFolder ? (e.children ?? []).map { ($0, "\(category.name) / \(e.title)") } : [(e, category.name)]
                for (entry, place) in filed where !kept.contains(entry.id) {
                    let count = usage[usageKey(entry, index)] ?? 0
                    if count <= threshold {
                        result.append(RareEntry(entry: entry, categoryID: category.id, place: place, count: count))
                    }
                }
            }
        }
        return result.sorted { $0.count != $1.count ? $0.count < $1.count : $0.entry.title.localizedCaseInsensitiveCompare($1.entry.title) == .orderedAscending }
    }

    static func usageKey(_ e: Entry, _ index: SearchIndex) -> String {
        if e.action != nil { return "action|" + e.title.lowercased() }
        if e.chain != nil { return "chain|" + e.title.lowercased() }
        let uri = index.resolver.resolve(e)?.uri ?? e.uri
        return index.usageKey[uri] ?? uri
    }
}

public extension LauncherConfig {
    /// "Keep": stop listing this entry as rarely used.
    mutating func keepEntry(_ id: UUID) {
        if !keptEntries.contains(id) { keptEntries.append(id) }
    }
}
