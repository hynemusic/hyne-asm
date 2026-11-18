import XCTest
@testable import HMLauncherCore

final class SearchIndexTests: XCTestCase {
    private func library(_ count: Int) -> [PluginItem] {
        (0..<count).map { i in
            PluginItem(uri: "u:\(i)", name: "Plugin \(i / 3) \(["Comp", "EQ", "Verb", "Delay"][i % 4])",
                       source: .plugins, path: [["VST3", "AUv2", "VST"][i % 3], "Vendor\(i % 60)"])
        }
    }

    /// Opening the panel or the quick search must not redo the expensive work (it took 50–130 ms per open).
    func testOpeningWithAPrebuiltIndexIsCheap() {
        let items = library(3500)
        var config = LauncherConfig.makeDefault()
        for i in stride(from: 0, to: 60, by: 3) { config.addEntry(items[i], to: config.favoritesID) }
        let index = SearchIndex(items: items, config: config)
        let start = Date()
        for _ in 0..<20 {
            _ = PanelState(config: config, index: index)
            _ = QuickSearch(config: config, index: index, usage: [:])
        }
        XCTAssertLessThan(Date().timeIntervalSince(start) / 20, 0.01)
    }

    func testIndexRowsAndLookups() {
        let items = [PluginItem(uri: "a3", name: "Pro-Q 4", source: .plugins, path: ["VST3", "FabFilter"]),
                     PluginItem(uri: "aau", name: "Pro-Q 4", source: .plugins, path: ["AUv2", "FabFilter"]),
                     PluginItem(uri: "eq", name: "EQ Eight", source: .audioEffects, path: [])]
        let index = SearchIndex(items: items, config: .makeDefault())
        XCTAssertEqual(index.globalRows.map(\.title), ["EQ Eight", "Pro-Q 4"])   // one row per plugin, alphabetical
        XCTAssertTrue(index.globalRows.allSatisfy(\.isGlobal))
        XCTAssertEqual(index.usageKey["a3"], index.usageKey["aau"])               // formats share a key
        XCTAssertEqual(index.globalRow(forKey: index.usageKey["aau"]!)?.uri, "a3") // best format
        XCTAssertEqual(index.globalRows.first { $0.title == "Pro-Q 4" }?.iconID, "eq")
    }
}

final class SearchIndexAlternativesTests: XCTestCase {
    func testAlternativesListTheOtherVersions() {
        let items = [item("REDD17 Mono", uri: "m", path: ["VST3", "Waves"]), item("REDD17 Stereo", uri: "s", path: ["VST3", "Waves"]),
                     item("Solo", uri: "x", path: ["VST3", "Y"])]
        let index = SearchIndex(items: items, config: .makeDefault())
        let row = index.globalRows.first { $0.uri == "s" }!
        XCTAssertEqual(index.alternatives(forKey: row.usageKey).map(\.uri), ["m"])
        XCTAssertTrue(index.alternatives(forKey: index.globalRows.first { $0.uri == "x" }!.usageKey).isEmpty)
        XCTAssertEqual(PluginVariants.label(items[0]), "VST3 · Mono")
    }
}

final class SearchIndexTitleTests: XCTestCase {
    func testMergedChannelVersionsShowTheBaseName() {
        let items = [item("REDD17 Mono", uri: "m", path: ["VST3", "Waves"]), item("REDD17 Stereo", uri: "s", path: ["VST3", "Waves"]),
                     item("Lone Stereo", uri: "l", path: ["VST3", "Y"])]
        let index = SearchIndex(items: items, config: .makeDefault())
        XCTAssertEqual(index.globalRows.map(\.title).sorted(), ["Lone Stereo", "REDD17"])   // a single version keeps its full name
        XCTAssertEqual(index.globalRows.first { $0.title == "REDD17" }?.uri, "s")
    }
}
