import Foundation

/// One plugin with all its installed formats, best first (VST3 → AU → VST2).
public struct PluginVariantGroup: Equatable, Sendable {
    public let variants: [PluginItem]
    public var preferred: PluginItem { variants[0] }
    /// Formats it is installed in, best first, each once.
    public var formats: [String] { unique(variants.map(PluginGrouping.formatLabel)) }
    /// Channel versions ("Stereo", "Mono", "Mono/Stereo", "m->s" …), preferred first; empty when there is only one kind.
    public var channels: [String] {
        let labels = unique(variants.map { PluginVariants.channel($0.name).label ?? "" })
        return labels.count > 1 ? labels.filter { !$0.isEmpty } : []
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

/// Merges the VST3/AU/VST2 copies of a plugin. Live names them differently per format, so the key normalises:
/// case and spaces, Waves' "(s)"/"(m)" = "Stereo"/"Mono", and VST2's "<Vendor> " prefix ("FabFilter Pro-L 2").
/// Live's own devices are never merged with plugins.
public enum PluginVariants {
    public struct Keys: Sendable {
        private let vendors: [String]

        public init(_ items: [PluginItem]) {
            vendors = PluginGrouping.knownVendors(items).map { $0.lowercased() }
        }

        public func key(_ item: PluginItem) -> String {
            // Presets with the same name in different folders are different files.
            if item.source.isPreset { return "preset|" + item.uri }
            guard item.source == .plugins else { return item.source.rawValue + "|" + LESMatcher.normalize(item.name) }
            var name = LESMatcher.normalize(PluginVariants.channel(item.name).base)
            if PluginGrouping.formatLabel(item) == "VST2", let vendor = vendors.first(where: { name.hasPrefix($0 + " ") }) {
                name.removeFirst(vendor.count + 1)
            }
            return "plugins|" + name
        }
    }

    /// Groups in first-seen order; within a group one item per format, best format first.
    public static func collapse(_ items: [PluginItem]) -> [PluginVariantGroup] {
        let keys = Keys(items)
        var order: [String] = []
        var byKey: [String: [PluginItem]] = [:]
        for item in items {
            let k = keys.key(item)
            if byKey[k] == nil { order.append(k) }
            byKey[k, default: []].append(item)
        }
        return order.map { k in
            // Stereo before mono, then VST3 → AU → VST2; one item per format and channel version.
            var seen = Set<String>()
            let variants = byKey[k]!
                .sorted { a, b in
                    let (ca, cb) = (channelRank(a), channelRank(b))
                    return ca != cb ? ca < cb : rank(a) < rank(b)
                }
                .filter { seen.insert(PluginGrouping.formatLabel($0) + "|" + (channel($0.name).label ?? "")).inserted }
            return PluginVariantGroup(variants: variants)
        }
    }

    /// Channel versions are one plugin: "REDD17 Mono" / "REDD17 Stereo", "CLA-76 (m)" / "(s)", "Reel ADT (m->s)",
    /// "Abbey Road Studio 3 (6->2)". Returns the name without that suffix and the version's label.
    /// ("Reel ADT Live" keeps "Live": that is a different plugin, not a channel version.)
    public static func channel(_ name: String) -> (base: String, label: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        let suffixes: [(String, String)] = [(" mono/stereo", "Mono/Stereo"), (" stereo", "Stereo"), (" mono", "Mono"),
                                             (" (s)", "Stereo"), (" (m)", "Mono"), (" (m->s)", "m->s"), (" (s->s)", "Stereo"),
                                             (" (m->m)", "Mono")]
        for (suffix, label) in suffixes where lower.hasSuffix(suffix) {
            return (String(trimmed.dropLast(suffix.count)), label)
        }
        // Surround layouts: "(6->2)", "(5->6)", "(8->2)"
        if let open = trimmed.lastIndex(of: "("), trimmed.hasSuffix(")") {
            let inside = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
            if inside.contains("->"), inside.allSatisfy({ $0.isNumber || $0 == "-" || $0 == ">" || $0 == "." }) {
                return (String(trimmed[..<open]).trimmingCharacters(in: .whitespaces), String(inside))
            }
        }
        return (trimmed, nil)
    }

    /// "VST3 · Mono" — names one version in menus.
    public static func label(_ item: PluginItem) -> String {
        [PluginGrouping.formatLabel(item), channel(item.name).label].compactMap { $0 }.joined(separator: " · ")
    }

    /// Stereo first (what most tracks need), then mono/stereo and plain names, then m->s, mono, surround.
    static func channelRank(_ item: PluginItem) -> Int {
        switch channel(item.name).label {
        case "Stereo": return 0
        case "Mono/Stereo", nil: return 1
        case "m->s": return 2
        case "Mono": return 3
        default: return 4
        }
    }

    static func rank(_ item: PluginItem) -> Int {
        switch PluginGrouping.formatLabel(item) {
        case "VST3": return 0
        case "AU": return 1
        case "VST2": return 2
        default: return 3
        }
    }
}
