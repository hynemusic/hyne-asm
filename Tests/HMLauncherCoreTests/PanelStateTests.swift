import XCTest
@testable import HMLauncherCore

final class PanelStateTests: XCTestCase {
    let eq = item("EQ Eight", uri: "u:eq", source: .audioEffects)
    let util = item("Utility", uri: "u:util", source: .audioEffects)
    let prol = item("Pro-L 2", uri: "u:prol", path: ["VST3", "FabFilter"])
    let diva = item("Diva", uri: "u:diva")

    func makeState(items: [PluginItem]? = nil) -> PanelState {
        var c = LauncherConfig.makeDefault()
        for i in [eq, util, prol] { c.addEntry(i, to: c.favoritesID) }
        c.addEntry(diva, to: c.categories[1].id)
        return PanelState(config: c, items: items ?? [eq, util, prol, diva])
    }

    func testTabsAreTheCategories() {
        let s = makeState()
        XCTAssertEqual(s.tabs.count, 3)
        guard case .category(_, let name) = s.tabs[0] else { return XCTFail() }
        XCTAssertEqual(name, "Favorites")
        XCTAssertEqual(s.rows.map(\.title), ["EQ Eight", "Utility", "Pro-L 2"])
    }

    func testLargestTabCountSizesThePanelForEveryCategory() {
        var s = makeState()
        XCTAssertEqual(s.largestTabCount, 3)   // Favorites has 3, the second category 1
        s.selectTab(1)
        XCTAssertEqual(s.largestTabCount, 3)   // same whichever tab is open
    }

    func testDigitInsertsRowWhenFilterEmpty() {
        var s = makeState()
        XCTAssertEqual(s.handle(.digit(2)), .insert(s.rows[1]))
        XCTAssertEqual(s.rows[1].uri, "u:util")
    }

    func testDigitBeyondRowCountDoesNothing() {
        var s = makeState()
        XCTAssertEqual(s.handle(.digit(9)), PanelAction.none)
    }

    func testDigitZeroDoesNothing() {
        var s = makeState()
        XCTAssertEqual(s.handle(.digit(0)), PanelAction.none)
        XCTAssertEqual(s.filter, "")
    }

    func testDigitIsTextWhenFilterNotEmpty() {
        var s = makeState()
        for ch in "pro-l " { _ = s.handle(.character(ch)) }
        XCTAssertEqual(s.handle(.digit(2)), PanelAction.none)
        XCTAssertEqual(s.filter, "pro-l 2")
        XCTAssertEqual(s.rows.map(\.title), ["Pro-L 2"])
    }

    func testReturnInsertsHighlightedOrFirstFilteredRow() {
        var s = makeState()
        _ = s.handle(.character("u"))
        XCTAssertEqual(s.rows.map(\.title), ["Utility"])
        XCTAssertEqual(s.handle(.returnKey), .insert(s.rows[0]))
        var t = makeState()
        _ = t.handle(.down); _ = t.handle(.down)
        XCTAssertEqual(t.handle(.returnKey), .insert(t.rows[1]))
    }

    func testReturnWithEmptyFilterAndNoHighlightDoesNothing() {
        var s = makeState()
        XCTAssertEqual(s.handle(.returnKey), PanelAction.none)
    }

    func testUpDownMoveHighlightWithinBounds() {
        var s = makeState()
        _ = s.handle(.down)
        XCTAssertEqual(s.highlighted, 0)
        for _ in 0..<5 { _ = s.handle(.down) }
        XCTAssertEqual(s.highlighted, 2)
        for _ in 0..<5 { _ = s.handle(.up) }
        XCTAssertEqual(s.highlighted, 0)
    }

    func testLeftRightAndTabSwitchTabsWrappingAndResetFilter() {
        var s = makeState()
        _ = s.handle(.character("e"))
        _ = s.handle(.down)
        _ = s.handle(.left)
        XCTAssertEqual(s.selectedTab, 2)
        XCTAssertEqual(s.filter, "")
        XCTAssertNil(s.highlighted)
        _ = s.handle(.right)
        XCTAssertEqual(s.selectedTab, 0)
        _ = s.handle(.tab)
        XCTAssertEqual(s.selectedTab, 1)
        XCTAssertEqual(s.rows.map(\.title), ["Diva"])
    }

    func testEscapeCloses() {
        var s = makeState()
        XCTAssertEqual(s.handle(.escape), .close)
    }

    func testBackspaceEditsFilter() {
        var s = makeState()
        _ = s.handle(.character("u")); _ = s.handle(.character("x"))
        _ = s.handle(.backspace)
        XCTAssertEqual(s.filter, "u")
        _ = s.handle(.backspace); _ = s.handle(.backspace)
        XCTAssertEqual(s.filter, "")
    }

    func testUnavailableRowIsNotInserted() {
        var s = makeState(items: [eq, prol])
        XCTAssertFalse(s.rows[1].isAvailable)
        XCTAssertEqual(s.handle(.digit(2)), PanelAction.none)
        XCTAssertEqual(s.handle(.digit(1)), .insert(s.rows[0]))
    }

    func testRowUsesResolvedUriWhenEntryUriIsStale() {
        let moved = item("Pro-L 2", uri: "u:prol-new", path: ["VST3", "FabFilter"])
        var s = makeState(items: [eq, util, moved])
        XCTAssertEqual(s.handle(.digit(3)), .insert(s.rows[2]))
        XCTAssertEqual(s.rows[2].uri, "u:prol-new")
    }

    func testRowCarriesIconAndDisplayName() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(eq, to: c.favoritesID)
        let id = c.categories[0].entries[0].id
        c.setIcon("eq", entry: id, in: c.favoritesID)
        c.setDisplayName("EQ8", entry: id, in: c.favoritesID)
        let s = PanelState(config: c, items: [eq])
        XCTAssertEqual(s.rows[0].iconID, "eq")
        XCTAssertEqual(s.rows[0].title, "EQ8")
        XCTAssertEqual(s.rows[0].name, "EQ Eight")
    }
}
