import Foundation

/// One plugin/device/preset on the Stats page.
public struct UsageStat: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let kind: UsageKind
    public let count: Int
    /// Share of all inserts, 0…1.
    public let share: Double
    public let iconID: String
    public let colorID: String?
    /// False when Live no longer lists it (uninstalled, renamed).
    public let isAvailable: Bool
}

public enum UsageKind: String, CaseIterable, Sendable {
    case plugins, live, maxForLive, presets

    init(_ source: ItemSource) {
        switch source {
        case .plugins: self = .plugins
        case .instruments, .audioEffects, .midiEffects: self = .live
        case .maxForLive: self = .maxForLive
        case .userLibrary, .userFolders: self = .presets
        }
    }

    /// For keys of items Live doesn't list any more: the key starts with the source ("plugins|serum 2").
    init(key: String) {
        let source = key.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
        if source == "preset" { self = .presets; return }
        self = ItemSource(rawValue: source).map(UsageKind.init) ?? .plugins
    }

    public var title: String {
        switch self {
        case .plugins: return "Plugins"
        case .live: return Loc.t("Live-Devices", "Live Devices")
        case .maxForLive: return "Max for Live"
        case .presets: return Loc.t("Eigene Presets", "Your Presets")
        }
    }
}

public struct UsageSummary: Equatable, Sendable {
    public let stats: [UsageStat]
    public let total: Int
    public let byKind: [(kind: UsageKind, count: Int)]

    public init(stats: [UsageStat], total: Int, byKind: [(kind: UsageKind, count: Int)]) {
        self.stats = stats; self.total = total; self.byKind = byKind
    }

    public static func == (a: UsageSummary, b: UsageSummary) -> Bool {
        a.stats == b.stats && a.total == b.total && a.byKind.map(\.count) == b.byKind.map(\.count)
    }

    /// Share of all inserts that went to the `n` most used.
    public func topShare(_ n: Int) -> Double {
        total == 0 ? 0 : Double(stats.prefix(n).reduce(0) { $0 + $1.count }) / Double(total)
    }
}

public enum UsageStats {
    /// Turns the raw counts into named, sorted rows. Names, icons and colors come from Live's list and the menu;
    /// keys Live no longer lists keep a readable name taken from the key itself.
    public static func summarize(_ counts: [String: Int], items: [PluginItem], config: LauncherConfig) -> UsageSummary {
        let keys = PluginVariants.Keys(items)
        var byKey: [String: PluginItem] = [:]
        for group in PluginVariants.collapse(items) {
            let k = keys.key(group.preferred)
            if byKey[k] == nil { byKey[k] = group.preferred }
        }
        let entries = config.allPluginEntries
        let total = counts.values.filter { $0 > 0 }.reduce(0, +)

        let stats: [UsageStat] = counts.filter { $0.value > 0 }.map { key, count -> UsageStat in
            let item = byKey[key] ?? (key.hasPrefix("preset|") ? items.first { "preset|" + $0.uri == key } : nil)
            let entry = item.flatMap { i in entries.first { $0.name == i.name && $0.source == i.source } }
            return UsageStat(
                key: key,
                name: entry?.title ?? item?.name ?? readableName(key),
                kind: item.map { UsageKind($0.source) } ?? UsageKind(key: key),
                count: count,
                share: total == 0 ? 0 : Double(count) / Double(total),
                iconID: entry?.iconID ?? item.map(IconGuesser.guess) ?? IconCatalog.defaultID,
                colorID: item.flatMap { config.colorID(for: $0) },
                isAvailable: item != nil)
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var perKind: [UsageKind: Int] = [:]
        for stat in stats { perKind[stat.kind, default: 0] += stat.count }
        let byKind: [(kind: UsageKind, count: Int)] = UsageKind.allCases
            .compactMap { kind -> (kind: UsageKind, count: Int)? in
                guard let count = perKind[kind] else { return nil }
                return (kind: kind, count: count)
            }
            .sorted { $0.count > $1.count }
        return UsageSummary(stats: stats, total: total, byKind: byKind)
    }

    /// "plugins|serum 2" → "Serum 2".
    static func readableName(_ key: String) -> String {
        let name = key.split(separator: "|", maxSplits: 1).last.map(String.init) ?? key
        return name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
