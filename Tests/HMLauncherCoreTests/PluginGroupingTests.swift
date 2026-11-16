import XCTest
@testable import HMLauncherCore

final class PluginGroupingTests: XCTestCase {
    let items: [PluginItem] = [
        item("FabFilter Pro-L 2", uri: "v2", path: ["VST", "Local"]),
        item("Pro-L 2", uri: "au", path: ["AUv2", "FabFilter"]),
        item("Pro-L 2", uri: "v3", path: ["VST3", "FabFilter"]),
        item("Pro-Q 3", uri: "q3", path: ["VST3", "FabFilter"]),
        item("Serum", uri: "serum", path: ["VST", "Local"]),
        item("Kontakt 7", uri: "k7", path: ["AUv2", "Native Instruments"]),
        item("EQ Eight", uri: "eq", source: .audioEffects),
        item("Drift", uri: "drift", source: .instruments),
    ]

    func testLiveGroupsFirstThenVendorsAlphabeticallyThenOtherVST2() {
        let titles = PluginGrouping.groups(items, search: "").map(\.title)
        XCTAssertEqual(titles, ["Live · Audio Effects", "Live · Instruments", "FabFilter", "Native Instruments", "Weitere VST2"])
    }

    func testWithinVendorVST3ThenAUThenVST2() {
        let fab = PluginGrouping.groups(items, search: "").first { $0.title == "FabFilter" }!
        XCTAssertEqual(fab.items.map(\.uri), ["v3", "q3", "au", "v2"])
    }

    func testVST2WithoutKnownVendorGoesToOther() {
        let other = PluginGrouping.groups(items, search: "").first { $0.title == "Weitere VST2" }!
        XCTAssertEqual(other.items.map(\.name), ["Serum"])
    }

    func testSearchFiltersAndDropsEmptyGroups() {
        let groups = PluginGrouping.groups(items, search: "pro-l")
        XCTAssertEqual(groups.map(\.title), ["FabFilter"])
        XCTAssertEqual(groups[0].items.map(\.uri), ["v3", "au", "v2"])
    }

    func testFormatLabel() {
        XCTAssertEqual(PluginGrouping.formatLabel(items[2]), "VST3")
        XCTAssertEqual(PluginGrouping.formatLabel(items[1]), "AU")
        XCTAssertEqual(PluginGrouping.formatLabel(items[0]), "VST2")
        XCTAssertEqual(PluginGrouping.formatLabel(items[6]), "Live")
    }
}
