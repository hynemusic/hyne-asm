import XCTest
@testable import HMLauncherCore

final class PluginVariantsTests: XCTestCase {
    let items: [PluginItem] = [
        item("Pro-L 2", uri: "pl-au", path: ["AUv2", "FabFilter"]),
        item("FabFilter Pro-L 2", uri: "pl-v2a", path: ["VST", "Local"]),
        item("FabFilter Pro-L 2", uri: "pl-v2b", path: ["VST", "Custom", "VST"]),
        item("Pro-L 2", uri: "pl-v3", path: ["VST3", "FabFilter"]),
        item("CLA-76 (m)", uri: "cla-au-m", path: ["AUv2", "Waves"]),
        item("CLA-76 (s)", uri: "cla-au-s", path: ["AUv2", "Waves"]),
        item("CLA-76 Mono", uri: "cla-v3-m", path: ["VST3", "Waves"]),
        item("CLA-76 Stereo", uri: "cla-v3-s", path: ["VST3", "Waves"]),
        item("RX 10 De-ess", uri: "rx", path: ["AUv2", "iZotope"]),
        item("Serum", uri: "serum-v2", path: ["VST", "Local"]),
        item("Utility", uri: "util-live", source: .audioEffects),
        item("Utility", uri: "util-plug", path: ["VST3", "Someone"]),
    ]

    private func group(_ uri: String, in groups: [PluginVariantGroup]) -> PluginVariantGroup? {
        groups.first { $0.variants.contains { $0.uri == uri } }
    }

    func testFormatsOfOnePluginCollapseWithVST3Preferred() {
        let groups = PluginVariants.collapse(items)
        let prol = group("pl-au", in: groups)!
        XCTAssertEqual(prol.preferred.uri, "pl-v3")
        XCTAssertEqual(prol.variants.map(\.uri), ["pl-v3", "pl-au", "pl-v2a"]) // duplicate VST2 dropped
        XCTAssertEqual(prol.formats, ["VST3", "AU", "VST2"])
    }

    /// Mono/Stereo variants are one plugin: one row, Stereo VST3 inserted, the others kept as alternatives.
    func testChannelVariantsMergeWithStereoPreferred() {
        let groups = PluginVariants.collapse(items)
        let cla = group("cla-au-m", in: groups)!
        XCTAssertEqual(cla.preferred.uri, "cla-v3-s")
        XCTAssertEqual(Set(cla.variants.map(\.uri)), ["cla-v3-s", "cla-au-s", "cla-v3-m", "cla-au-m"])
        XCTAssertEqual(cla.formats, ["VST3", "AU"])
        XCTAssertEqual(cla.channels, ["Stereo", "Mono"])
    }

    func testLibraryExamples() {
        let lib = [
            item("REDD17 Mono", uri: "r17m", path: ["VST3", "Waves"]), item("REDD17 Stereo", uri: "r17s", path: ["VST3", "Waves"]),
            item("Reel ADT (m->s)", uri: "adt", path: ["VST3", "Waves"]),
            item("Reel ADT Live Mono", uri: "adtlm", path: ["VST3", "Waves"]),
            item("Reel ADT Live Mono/Stereo", uri: "adtlms", path: ["VST3", "Waves"]),
            item("Reel ADT Live Stereo", uri: "adtls", path: ["VST3", "Waves"]),
            item("Abbey Road Studio 3 (6->2)", uri: "ar62", path: ["VST3", "Waves"]),
            item("Abbey Road Studio 3 (8->2)", uri: "ar82", path: ["VST3", "Waves"]),
        ]
        let groups = PluginVariants.collapse(lib)
        XCTAssertEqual(groups.count, 4)   // REDD17 · Reel ADT · Reel ADT Live · Abbey Road Studio 3
        XCTAssertEqual(group("r17m", in: groups)?.preferred.uri, "r17s")
        XCTAssertEqual(group("adtlm", in: groups)?.preferred.uri, "adtls")
        XCTAssertNotEqual(group("adt", in: groups)?.preferred.uri, group("adtls", in: groups)?.preferred.uri)  // "Live" is its own plugin
        XCTAssertEqual(group("ar82", in: groups)?.variants.count, 2)
    }

    func testSingleFormatPluginsStay() {
        let groups = PluginVariants.collapse(items)
        XCTAssertEqual(group("rx", in: groups)?.preferred.uri, "rx")
        XCTAssertEqual(group("serum-v2", in: groups)?.preferred.uri, "serum-v2")
    }

    func testLiveDeviceAndPluginWithSameNameStaySeparate() {
        let groups = PluginVariants.collapse(items)
        XCTAssertNotEqual(group("util-live", in: groups)?.preferred.uri, group("util-plug", in: groups)?.preferred.uri)
    }

    func testCollapseCount() {
        // Pro-L 2, CLA-76 (mono + stereo), RX, Serum, Utility (Live), Utility (plugin)
        XCTAssertEqual(PluginVariants.collapse(items).count, 6)
    }

    func testKeyMatchesAcrossFormats() {
        let keys = PluginVariants.Keys(items)
        XCTAssertEqual(keys.key(items[0]), keys.key(items[1]))
        XCTAssertEqual(keys.key(items[5]), keys.key(items[7]))
        XCTAssertEqual(keys.key(items[4]), keys.key(items[5]))      // CLA-76 (m) and (s): one plugin
        XCTAssertNotEqual(keys.key(items[0]), keys.key(items[4]))
    }
}

final class PanelVariantTests: XCTestCase {
    func testAllTabAndGlobalSearchShowEachPluginOnce() {
        let items = [
            item("Pro-L 2", uri: "pl-au", path: ["AUv2", "FabFilter"]),
            item("FabFilter Pro-L 2", uri: "pl-v2", path: ["VST", "Local"]),
            item("Pro-L 2", uri: "pl-v3", path: ["VST3", "FabFilter"]),
            item("Pro-Q 3", uri: "pq-v3", path: ["VST3", "FabFilter"]),
        ]
        var s = PanelState(config: .makeDefault(), items: items)
        for ch in "pro" { _ = s.handle(.character(ch)) }
        XCTAssertEqual(s.rows.map(\.uri).sorted(), ["pl-v3", "pq-v3"])
        for ch in "-l" { _ = s.handle(.character(ch)) }
        XCTAssertEqual(s.rows.map(\.uri), ["pl-v3"])
    }

    func testGlobalSearchSkipsOtherFormatsOfCategoryPlugins() {
        let au = item("Pro-L 2", uri: "pl-au", path: ["AUv2", "FabFilter"])
        let v3 = item("Pro-L 2", uri: "pl-v3", path: ["VST3", "FabFilter"])
        var c = LauncherConfig.makeDefault()
        c.addEntry(au, to: c.favoritesID)
        var s = PanelState(config: c, items: [au, v3])
        for ch in "pro" { _ = s.handle(.character(ch)) }
        XCTAssertEqual(s.rows.map(\.uri), ["pl-au"]) // the AU in Favorites; its VST3 is not repeated below
    }
}
