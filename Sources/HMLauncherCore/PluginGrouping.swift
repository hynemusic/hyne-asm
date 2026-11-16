import Foundation

public struct PluginGroup: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public let title: String
    public let items: [PluginItem]
}

/// Settings browser: Live devices first, then one folder per manufacturer (VST3 → AU → VST2 inside),
/// then VST2 plugins whose manufacturer cannot be inferred.
public enum PluginGrouping {
    public static let otherVST2 = "Weitere VST2"

    private static let liveGroups: [(ItemSource, String)] = [
        (.audioEffects, "Live · Audio Effects"), (.instruments, "Live · Instruments"),
        (.midiEffects, "Live · MIDI Effects"), (.maxForLive, "Live · Max for Live"),
    ]

    public static func groups(_ items: [PluginItem], search: String) -> [PluginGroup] {
        let vendors = knownVendors(items)
        let matches = items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        var result: [PluginGroup] = []

        for (source, title) in liveGroups {
            let group = matches.filter { $0.source == source }.sorted(by: byName)
            if !group.isEmpty { result.append(PluginGroup(title: title, items: group)) }
        }

        let plugins = matches.filter { $0.source == .plugins }
        let byVendor = Dictionary(grouping: plugins) { vendor(of: $0, known: vendors) ?? otherVST2 }
        let vendorTitles = byVendor.keys.filter { $0 != otherVST2 }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        for title in vendorTitles + (byVendor[otherVST2] == nil ? [] : [otherVST2]) {
            let sorted = byVendor[title]!.sorted { a, b in
                let (fa, fb) = (formatRank(a), formatRank(b))
                return fa != fb ? fa < fb : byName(a, b)
            }
            result.append(PluginGroup(title: title, items: sorted))
        }
        return result
    }

    public static func formatLabel(_ item: PluginItem) -> String {
        guard item.source == .plugins else { return "Live" }
        switch formatRank(item) {
        case 0: return "VST3"
        case 1: return "AU"
        case 2: return "VST2"
        default: return item.path.first ?? ""
        }
    }

    private static func formatRank(_ item: PluginItem) -> Int {
        let format = item.path.first ?? ""
        if format == "VST3" { return 0 }
        if format.hasPrefix("AU") { return 1 }
        if format == "VST" { return 2 }
        return 3
    }

    /// Manufacturer folders that VST3/AU plugins live in.
    private static func knownVendors(_ items: [PluginItem]) -> [String] {
        let names = Set(items.filter { $0.source == .plugins && formatRank($0) < 2 && $0.path.count > 1 }.map { $0.path[1] })
        return names.sorted { $0.count > $1.count } // longest first
    }

    /// VST3/AU: the folder below the format. VST2 has no manufacturer folder → name prefix ("FabFilter Pro-L 2").
    private static func vendor(of item: PluginItem, known: [String]) -> String? {
        if formatRank(item) < 2, item.path.count > 1 { return item.path[1] }
        return known.first { item.name.hasPrefix($0 + " ") }
    }

    private static func byName(_ a: PluginItem, _ b: PluginItem) -> Bool {
        a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}
