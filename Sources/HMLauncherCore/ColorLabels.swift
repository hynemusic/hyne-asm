import Foundation

public struct ColorDef: Hashable, Sendable {
    public let id: String
    let de: String
    let en: String
    public let red: Double, green: Double, blue: Double
    public var label: String { Loc.t(de, en) }
}

public enum ColorPalette {
    /// Stored on an entry to mean "no color, even if a rule would give one".
    public static let noneID = "none"

    public static let all: [ColorDef] = [
        ColorDef(id: "red", de: "Rot", en: "Red", red: 0.93, green: 0.33, blue: 0.31),
        ColorDef(id: "orange", de: "Orange", en: "Orange", red: 0.98, green: 0.58, blue: 0.20),
        ColorDef(id: "yellow", de: "Gelb", en: "Yellow", red: 0.97, green: 0.83, blue: 0.25),
        ColorDef(id: "green", de: "Grün", en: "Green", red: 0.40, green: 0.80, blue: 0.38),
        ColorDef(id: "teal", de: "Türkis", en: "Teal", red: 0.25, green: 0.78, blue: 0.75),
        ColorDef(id: "blue", de: "Blau", en: "Blue", red: 0.33, green: 0.58, blue: 0.96),
        ColorDef(id: "purple", de: "Lila", en: "Purple", red: 0.67, green: 0.47, blue: 0.93),
        ColorDef(id: "pink", de: "Pink", en: "Pink", red: 0.95, green: 0.45, blue: 0.70),
        ColorDef(id: "gray", de: "Grau", en: "Gray", red: 0.62, green: 0.62, blue: 0.62),
    ]

    public static func color(_ id: String?) -> ColorDef? {
        all.first { $0.id == id }
    }
}

/// Colors that apply to a whole group of plugins — also to ones added later and to search hits.
public enum ColorRule: Hashable, Sendable {
    case liveDevices
    case vendor(String)

    var key: String {
        switch self {
        case .liveDevices: return "live"
        case .vendor(let name): return "vendor:" + name
        }
    }

    /// Rules that can apply to a plugin: Live's own devices, or the manufacturer folder of a VST3/AU.
    public static func forItem(_ item: PluginItem) -> [ColorRule] {
        switch item.source {
        case .instruments, .audioEffects, .midiEffects: return [.liveDevices]
        case .maxForLive, .userLibrary, .userFolders: return []
        case .plugins:
            guard PluginGrouping.formatLabel(item) != "VST2", item.path.count > 1 else { return [] }
            return [.vendor(item.path[1])]
        }
    }
}

public extension LauncherConfig {
    /// The entry's own color, else a matching rule. `ColorPalette.noneID` on the entry means no color.
    func colorID(for entry: Entry) -> String? {
        if let own = entry.colorID { return own == ColorPalette.noneID ? nil : own }
        if entry.isFolder { return nil }
        return colorID(for: PluginItem(uri: entry.uri, name: entry.name, source: entry.source, path: entry.path))
    }

    func colorID(for item: PluginItem) -> String? {
        ColorRule.forItem(item).lazy.compactMap { colorRules[$0.key] }.first
    }

    func colorRule(_ rule: ColorRule) -> String? { colorRules[rule.key] }

    mutating func setColorRule(_ colorID: String?, for rule: ColorRule) {
        colorRules[rule.key] = colorID
    }

    /// Like icons, a color belongs to the plugin: every entry of it (all categories, all formats) changes.
    /// `nil` falls back to the rules; a folder's color only changes that folder.
    mutating func setColor(_ colorID: String?, entry: UUID, in categoryID: UUID) {
        guard let target = findEntry(entry, in: categoryID) else { return }
        for ci in categories.indices {
            for ei in categories[ci].entries.indices {
                let e = categories[ci].entries[ei]
                if e.id == target.id || (!target.isFolder && !e.isFolder && Self.sameColorPlugin(e, target)) {
                    categories[ci].entries[ei].colorID = colorID
                }
                for ki in (e.children ?? []).indices where !target.isFolder && Self.sameColorPlugin(e.children![ki], target) {
                    categories[ci].entries[ei].children![ki].colorID = colorID
                }
            }
        }
    }

    private static func sameColorPlugin(_ a: Entry, _ b: Entry) -> Bool {
        a.uri == b.uri || (a.name == b.name && a.source == b.source)
    }
}
