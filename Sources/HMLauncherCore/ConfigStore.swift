import Foundation

public final class ConfigStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HM Launcher/config.json")
    }

    /// Missing file → default. Unreadable file → backed up as config.corrupt-<timestamp>.json, then default.
    public func load() -> LauncherConfig {
        guard let data = try? Data(contentsOf: url) else { return .makeDefault() }
        if let config = try? JSONDecoder().decode(LauncherConfig.self, from: data),
           config.categories.contains(where: \.isFavorites) {
            return config
        }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let backup = url.deletingLastPathComponent().appendingPathComponent("config.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
        return .makeDefault()
    }

    public func save(_ config: LauncherConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
