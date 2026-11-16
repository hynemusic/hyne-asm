import XCTest
@testable import HMLauncherCore

final class PanelGlobalSearchTests: XCTestCase {
    let eq8 = item("EQ Eight", uri: "eq8", source: .audioEffects)
    let util = item("Utility", uri: "util", source: .audioEffects)
    let eq3 = item("EQ Three", uri: "eq3", source: .audioEffects)
    let proq = item("FabFilter Pro-Q 3", uri: "proq", path: ["VST3", "FabFilter"])
    let channelEQ = item("Channel EQ", uri: "ceq", source: .audioEffects)

    func makeState(items extra: [PluginItem] = []) -> PanelState {
        var c = LauncherConfig.makeDefault()
        c.addEntry(eq8, to: c.favoritesID)
        c.addEntry(util, to: c.favoritesID)
        return PanelState(config: c, items: [eq8, util, eq3, proq, channelEQ] + extra)
    }

    private func type(_ s: inout PanelState, _ text: String) { for ch in text { _ = s.handle(.character(ch)) } }

    func testCategoryMatchesFirstThenOtherPlugins() {
        var s = makeState()
        type(&s, "eq")
        XCTAssertEqual(s.rows.map(\.title), ["EQ Eight", "EQ Three", "Channel EQ"])
        XCTAssertEqual(s.rows.map(\.isGlobal), [false, true, true])
        XCTAssertEqual(s.handle(.returnKey), .insert(s.rows[0]))
    }

    func testGlobalSectionPrefersPrefixMatchesAndSkipsCategoryPlugins() {
        var s = makeState()
        type(&s, "e")
        let global = s.rows.filter(\.isGlobal).map(\.title)
        XCTAssertFalse(global.contains("EQ Eight"))
        XCTAssertEqual(global.first, "EQ Three") // starts with "e"
    }

    func testGlobalSectionIsLimited() {
        let many = (0..<200).map { item("Echo \($0)", uri: "e\($0)") }
        var s = makeState(items: many)
        type(&s, "echo")
        XCTAssertEqual(s.rows.filter(\.isGlobal).count, PanelState.maxGlobalResults)
    }

    func testGlobalRowsGetGuessedIcons() {
        var s = makeState()
        type(&s, "three")
        XCTAssertEqual(s.rows.first?.iconID, "eq")
        XCTAssertTrue(s.rows.first?.isGlobal ?? false)
    }

    func testNoGlobalRowsWithoutFilterOrInAllTab() {
        var s = makeState()
        XCTAssertFalse(s.rows.contains(where: \.isGlobal))
        s.selectTab(s.tabs.count - 1)
        type(&s, "eq")
        XCTAssertFalse(s.rows.contains(where: \.isGlobal))
        XCTAssertEqual(s.rows.map(\.title), ["EQ Eight", "EQ Three", "Channel EQ"]) // ranked: names starting with "eq" first
    }

    func testInsideFolderFolderMatchesFirst() {
        var c = LauncherConfig.makeDefault()
        let f = c.addFolder(named: "Tools", to: c.favoritesID)
        c.addEntry(util, to: c.favoritesID, folder: f)
        var s = PanelState(config: c, items: [eq8, util, eq3])
        s.openFolder(f)
        type(&s, "t")
        XCTAssertEqual(s.rows.first?.title, "Utility")
        XCTAssertFalse(s.rows[0].isGlobal)
        XCTAssertTrue(s.rows.dropFirst().allSatisfy(\.isGlobal))
    }
}
