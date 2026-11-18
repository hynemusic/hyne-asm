import Foundation

public final class ConfigStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static let folderName = "HYNE ASM"
    static let legacyFolderName = "HM Launcher"

    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        moveLegacyFolder(in: support)
        return support.appendingPathComponent("\(folderName)/config.json")
    }

    /// The app used to be called "HM Launcher": carry its folder (config, versions, usage) over once.
    static func moveLegacyFolder(in support: URL) {
        let fm = FileManager.default
        let old = support.appendingPathComponent(legacyFolderName)
        let new = support.appendingPathComponent(folderName)
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        try? fm.moveItem(at: old, to: new)
    }

    /// Missing file → default. Unreadable file → backed up as config.corrupt-<timestamp>.json, then default.
    public func load() -> LauncherConfig {
        guard let data = try? Data(contentsOf: url) else { return .makeDefault() }
        if var config = try? JSONDecoder().decode(LauncherConfig.self, from: data),
           config.categories.contains(where: \.isFavorites) {
            Self.migrate(&config)
            return config
        }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let backup = url.deletingLastPathComponent().appendingPathComponent("config.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
        return .makeDefault()
    }

    /// v1 → v2: "close all plugin windows" moved from ⌘⌥W to ⌘⌃W.
    static func migrate(_ config: inout LauncherConfig) {
        if config.version < 2 {
            let old = KeyCombo(keyCode: 13, modifiers: [.cmd, .alt])
            let new = KeyCombo(keyCode: 13, modifiers: [.cmd, .ctrl])
            config.shortcuts.closeAll = config.shortcuts.closeAll.map { $0 == old ? new : $0 }
        }
        if config.version < 3 {
            // v2 → v3: entries still on the plain default icon get a guessed one.
            for c in config.categories.indices {
                for e in config.categories[c].entries.indices where config.categories[c].entries[e].iconID == IconCatalog.defaultID {
                    let entry = config.categories[c].entries[e]
                    config.categories[c].entries[e].iconID = IconGuesser.guess(
                        PluginItem(uri: entry.uri, name: entry.name, source: entry.source, path: entry.path))
                }
            }
        }
        if config.version < 4 {
            // v3 → v4: new icon kinds (amp, mic, repair, mastering …) for entries still on the generic icon,
            // in folders and in every stored profile too.
            config.categories = regessGeneric(config.categories)
            for p in config.profiles.indices { config.profiles[p].categories = regessGeneric(config.profiles[p].categories) }
        }
        config.version = LauncherConfig.currentVersion
    }

    private static func regessGeneric(_ categories: [Category]) -> [Category] {
        func fix(_ e: Entry) -> Entry {
            var e = e
            if e.isFolder {
                e.children = e.children?.map(fix)
            } else if e.iconID == IconCatalog.defaultID, e.chain == nil, e.action == nil {
                e.iconID = IconGuesser.guess(PluginItem(uri: e.uri, name: e.name, source: e.source, path: e.path))
            }
            return e
        }
        return categories.map { c in var c = c; c.entries = c.entries.map(fix); return c }
    }

    public func save(_ config: LauncherConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
