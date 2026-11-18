import Foundation

@MainActor
public final class PluginCatalog: ObservableObject {
    @Published public private(set) var items: [PluginItem] = [] { didSet { index = EntryResolver.Index(items) } }
    /// Built once per plugin list; use it to resolve entries while drawing.
    public private(set) var index = EntryResolver.Index([])
    private let cacheURL: URL
    private let client: BridgeClient

    public init(cacheURL: URL, client: BridgeClient) {
        self.cacheURL = cacheURL
        self.client = client
    }

    public static var defaultCacheURL: URL {
        ConfigStore.defaultURL.deletingLastPathComponent().appendingPathComponent("catalog-cache.json")
    }

    public func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode([PluginItem].self, from: data) else { return }
        items = cached
    }

    /// On failure the current items are kept. `rescan`: Live walks its browser again (new plugins, new presets).
    public func refresh(rescan: Bool = false) async throws {
        let fresh = try await client.listItems(refresh: rescan)
        guard fresh != items else { return } // nothing changed: no redraws, no index rebuild
        items = fresh
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(fresh).write(to: cacheURL, options: .atomic)
    }
}
