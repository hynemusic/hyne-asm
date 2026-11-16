import XCTest
@testable import HMLauncherCore

@MainActor
final class PluginCatalogTests: XCTestCase {
    func testCatalogRefreshWritesCacheAndLoadCacheRestores() async throws {
        let server = FakeBridgeServer()
        try server.start()
        defer { server.stop() }
        server.respond = { ok($0, ["items": [["uri": "u:eq", "name": "EQ Eight", "source": "audio_effects", "path": [] as [String]]]]) }
        let client = BridgeClient(port: server.port)
        await client.start()
        _ = await waitUntil { await client.isConnected }
        let cache = tempDir().appendingPathComponent("catalog-cache.json")

        let catalog = PluginCatalog(cacheURL: cache, client: client)
        try await catalog.refresh()
        XCTAssertEqual(catalog.items.map(\.name), ["EQ Eight"])

        let restored = PluginCatalog(cacheURL: cache, client: client)
        restored.loadCache()
        XCTAssertEqual(restored.items, catalog.items)
        await client.stop()
    }

    func testCatalogRefreshFailureKeepsItems() async throws {
        let cache = tempDir().appendingPathComponent("catalog-cache.json")
        let items = [PluginItem(uri: "u:1", name: "Utility", source: .audioEffects, path: [])]
        try JSONEncoder().encode(items).write(to: cache)
        let catalog = PluginCatalog(cacheURL: cache, client: BridgeClient(port: 1))
        catalog.loadCache()
        do { try await catalog.refresh(); XCTFail("expected error") } catch {}
        XCTAssertEqual(catalog.items, items)
    }
}
