import Foundation

/// One plugin with all its installed formats, best first (VST3 → AU → VST2).
public struct PluginVariantGroup: Equatable, Sendable {
    public let variants: [PluginItem]
    public var preferred: PluginItem { variants[0] }
    public var formats: [String] { variants.map(PluginGrouping.formatLabel) }
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
            var name = LESMatcher.normalize(item.name)
            if PluginGrouping.formatLabel(item) == "VST2", let vendor = vendors.first(where: { name.hasPrefix($0 + " ") }) {
                name.removeFirst(vendor.count + 1)
            }
            name = name.replacingOccurrences(of: " (s)", with: " stereo").replacingOccurrences(of: " (m)", with: " mono")
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
            var seen = Set<String>()
            let variants = byKey[k]!.sorted { rank($0) < rank($1) }.filter { seen.insert(PluginGrouping.formatLabel($0)).inserted }
            return PluginVariantGroup(variants: variants)
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
