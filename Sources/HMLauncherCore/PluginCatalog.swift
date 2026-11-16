import Foundation

@MainActor
public final class PluginCatalog: ObservableObject {
    @Published public private(set) var items: [PluginItem] = []
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

    /// On failure the current items are kept.
    public func refresh() async throws {
        let fresh = try await client.listItems()
        items = fresh
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(fresh).write(to: cacheURL, options: .atomic)
    }
}
