import XCTest
@testable import HMLauncherCore

final class UsageStatsTests: XCTestCase {
    let serum3 = PluginItem(uri: "u:s3", name: "Serum 2", source: .plugins, path: ["VST3", "Xfer Records"])
    let serumAU = PluginItem(uri: "u:sau", name: "Serum 2", source: .plugins, path: ["AUv2", "Xfer Records"])
    let eq = PluginItem(uri: "u:eq", name: "EQ Eight", source: .audioEffects, path: [])
    let glue = PluginItem(uri: "u:glue", name: "My Glue", source: .userLibrary, path: [], format: "adg")

    func testSummarizeNamesSortsAndShares() {
        let items = [serum3, serumAU, eq, glue]
        let keys = PluginVariants.Keys(items)
        let counts = [keys.key(serum3): 6, keys.key(eq): 3, keys.key(glue): 1, "plugins|old thing": 2]
        let s = UsageStats.summarize(counts, items: items, config: .makeDefault())
        XCTAssertEqual(s.total, 12)
        XCTAssertEqual(s.stats.map(\.name), ["Serum 2", "EQ Eight", "Old Thing", "My Glue"])
        XCTAssertEqual(s.stats[0].share, 0.5, accuracy: 0.001)
        XCTAssertEqual(s.stats.map(\.kind), [.plugins, .live, .plugins, .presets])
        XCTAssertFalse(s.stats[2].isAvailable)
        XCTAssertEqual(s.byKind.map(\.kind), [.plugins, .live, .presets])
        XCTAssertEqual(s.byKind.map(\.count), [8, 3, 1])
        XCTAssertEqual(s.topShare(2), 0.75, accuracy: 0.001)
    }

    func testEmpty() {
        let s = UsageStats.summarize([:], items: [eq], config: .makeDefault())
        XCTAssertEqual(s.total, 0)
        XCTAssertTrue(s.stats.isEmpty)
        XCTAssertEqual(s.topShare(10), 0)
    }

    func testStoreReplaceMergeResetAndExportRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = UsageStore(url: url)
        store.record("plugins|a")
        store.merge(["plugins|a": 2, "plugins|b": 1, "plugins|zero": 0])
        XCTAssertEqual(store.counts, ["plugins|a": 3, "plugins|b": 1])
        XCTAssertEqual(UsageStore(url: url).counts, ["plugins|a": 3, "plugins|b": 1]) // persisted

        let data = try UsageExport(counts: store.counts).data()
        XCTAssertEqual(try UsageExport.read(data), ["plugins|a": 3, "plugins|b": 1])

        store.replaceAll(["plugins|c": 5])
        XCTAssertEqual(store.counts, ["plugins|c": 5])
        store.reset()
        XCTAssertEqual(UsageStore(url: url).counts, [:])
        try? FileManager.default.removeItem(at: url)
    }

    func testReadAcceptsRawUsageJSONAndRejectsOtherFiles() {
        XCTAssertEqual(try UsageExport.read(Data(#"{"plugins|serum 2":9}"#.utf8)), ["plugins|serum 2": 9])
        XCTAssertThrowsError(try UsageExport.read(Data(#"{"name":"x"}"#.utf8)))
        XCTAssertThrowsError(try UsageExport.read(Data("nope".utf8)))
    }
}
