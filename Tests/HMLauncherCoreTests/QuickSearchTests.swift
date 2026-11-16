import XCTest
@testable import HMLauncherCore

final class QuickSearchTests: XCTestCase {
    let proQ = item("Pro-Q 4", uri: "pq", path: ["VST3", "FabFilter"])
    let proL = item("Pro-L 2", uri: "pl", path: ["VST3", "FabFilter"])
    let la2 = item("LA-2", uri: "la2", path: ["VST3", "UA"])
    let serum = item("Serum 2", uri: "serum", path: ["VST3", "Xfer Records"])
    let eq8 = item("EQ Eight", uri: "eq8", source: .audioEffects)

    func makeConfig() -> LauncherConfig {
        var c = LauncherConfig.makeDefault()
        c.addEntry(eq8, to: c.favoritesID)
        let fx = c.categories[2].id
        c.addEntry(proL, to: fx)
        let f = c.addFolder(named: "UAD", to: fx)
        c.addEntry(la2, to: fx, folder: f)
        c.addEntry(proL, to: c.categories[1].id) // same plugin in two categories
        return c
    }

    private var items: [PluginItem] { [proQ, proL, la2, serum, eq8] }

    func testCategoryHitsFirstWithPlaceThenAllPlugins() {
        let r = QuickSearch(config: makeConfig(), items: items, usage: [:]).results("pro")
        XCTAssertEqual(r.map(\.row.title), ["Pro-L 2", "Pro-Q 4"])
        XCTAssertEqual(r[0].place, "Instruments")   // first category it is filed in, no duplicate
        XCTAssertFalse(r[0].row.isGlobal)
        XCTAssertTrue(r[1].row.isGlobal)
        XCTAssertNil(r[1].place)
    }

    func testFindsPluginsInsideFolders() {
        let r = QuickSearch(config: makeConfig(), items: items, usage: [:]).results("la 2")
        XCTAssertEqual(r.first?.row.title, "LA-2")
        XCTAssertEqual(r.first?.place, "Effects / UAD")
    }

    func testUsageRanksEqualMatches() {
        let keys = PluginVariants.Keys(items)
        let r = QuickSearch(config: .makeDefault(), items: items, usage: [keys.key(proQ): 3]).results("pro")
        XCTAssertEqual(r.map(\.row.title), ["Pro-Q 4", "Pro-L 2"])
    }

    func testEmptyQueryShowsMostUsedThenFavorites() {
        let keys = PluginVariants.Keys(items)
        let used = QuickSearch(config: makeConfig(), items: items, usage: [keys.key(serum): 5, keys.key(la2): 2]).results("")
        XCTAssertEqual(used.map(\.row.title), ["Serum 2", "LA-2"])
        let fresh = QuickSearch(config: makeConfig(), items: items, usage: [:]).results("")
        XCTAssertEqual(fresh.map(\.row.title), ["EQ Eight"])
    }

    func testStateTypingNavigationAndInsert() {
        var s = QuickSearchState(search: QuickSearch(config: makeConfig(), items: items, usage: [:]))
        for ch in "pro" { _ = s.handle(.character(ch)) }
        XCTAssertEqual(s.query, "pro")
        XCTAssertEqual(s.highlighted, 0)
        _ = s.handle(.down)
        XCTAssertEqual(s.highlighted, 1)
        _ = s.handle(.down)
        XCTAssertEqual(s.highlighted, 1)
        XCTAssertEqual(s.handle(.returnKey), .insert(s.results[1].row))
        _ = s.handle(.digit(4))
        XCTAssertEqual(s.query, "pro4")
        _ = s.handle(.backspace)
        XCTAssertEqual(s.query, "pro")
        XCTAssertEqual(s.handle(.escape), .close)
    }

    func testReturnWithoutResultsDoesNothing() {
        var s = QuickSearchState(search: QuickSearch(config: makeConfig(), items: items, usage: [:]))
        for ch in "zzz" { _ = s.handle(.character(ch)) }
        XCTAssertTrue(s.results.isEmpty)
        XCTAssertEqual(s.handle(.returnKey), PanelAction.none)
    }
}

final class QuickSearchShortcutTests: XCTestCase {
    func testDefaultIsCtrlSpaceAndMatches() {
        XCTAssertEqual(ShortcutSettings.default.quickSearch, [KeyCombo(keyCode: 49, modifiers: [.ctrl])])
        XCTAssertEqual(ShortcutMatcher(settings: .default).match(keyCode: 49, modifiers: [.ctrl]), .quickSearch)
    }

    func testOlderConfigWithoutQuickSearchGetsDefault() throws {
        let json = #"{"closeFocused":{"keyCode":13,"modifiers":1},"closeAll":[]}"#
        let s = try JSONDecoder().decode(ShortcutSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.quickSearch, ShortcutSettings.default.quickSearch)
        XCTAssertEqual(s.closeAll, [])
    }

    func testDisabledQuickSearchStaysDisabled() throws {
        var s = ShortcutSettings.default
        s.quickSearch = []
        let back = try JSONDecoder().decode(ShortcutSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.quickSearch, [])
    }
}
