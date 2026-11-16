import XCTest
@testable import HMLauncherCore

final class ConfigEditingTests: XCTestCase {
    func testDefaultConfigHasFavoritesFirst() {
        let c = LauncherConfig.makeDefault()
        XCTAssertEqual(c.categories.map(\.name), ["Favorites", "Instruments", "Effects"])
        XCTAssertTrue(c.categories[0].isFavorites)
        XCTAssertTrue(c.categories.allSatisfy { $0.entries.isEmpty })
        XCTAssertEqual(c.favoritesID, c.categories[0].id)
    }

    func testDefaultShortcuts() {
        let s = LauncherConfig.makeDefault().shortcuts
        XCTAssertEqual(s.closeFocused, KeyCombo(keyCode: 13, modifiers: [.cmd]))
        XCTAssertEqual(s.closeAll, [KeyCombo(keyCode: 13, modifiers: [.cmd, .ctrl]), KeyCombo(keyCode: 53, modifiers: [.cmd])])
    }

    func testAddEntryIgnoresDuplicateUriInSameCategory() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(item("EQ Eight"), to: c.favoritesID)
        c.addEntry(item("EQ Eight"), to: c.favoritesID)
        XCTAssertEqual(c.categories[0].entries.count, 1)
    }

    func testAddEntryUsesDefaultIcon() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(item("EQ Eight", source: .audioEffects, path: ["x"]), to: c.favoritesID)
        let e = c.categories[0].entries[0]
        XCTAssertEqual(e.iconID, IconCatalog.defaultID)
        XCTAssertEqual(e.title, "EQ Eight")
        XCTAssertEqual(e.path, ["x"])
        XCTAssertEqual(e.source, .audioEffects)
    }

    func testMoveEntryReorders() {
        var c = LauncherConfig.makeDefault()
        for n in ["A", "B", "C"] { c.addEntry(item(n), to: c.favoritesID) }
        c.moveEntry(in: c.favoritesID, from: 2, to: 0)
        XCTAssertEqual(c.categories[0].entries.map(\.name), ["C", "A", "B"])
    }

    func testFavoritesCannotBeDeletedOrMoved() {
        var c = LauncherConfig.makeDefault()
        c.deleteCategory(c.favoritesID)
        XCTAssertEqual(c.categories.count, 3)
        c.moveCategory(from: 0, to: 2)
        XCTAssertTrue(c.categories[0].isFavorites)
        c.moveCategory(from: 2, to: 0)
        XCTAssertTrue(c.categories[0].isFavorites)
        XCTAssertEqual(c.categories.map(\.name), ["Favorites", "Effects", "Instruments"])
    }

    func testCategoryCrud() {
        var c = LauncherConfig.makeDefault()
        let id = c.addCategory(named: "Reverb & Echos")
        c.renameCategory(id, to: "Space")
        XCTAssertEqual(c.categories.last?.name, "Space")
        c.deleteCategory(id)
        XCTAssertEqual(c.categories.count, 3)
    }

    func testRemoveSetIconAndDisplayName() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(item("EQ Eight"), to: c.favoritesID)
        let id = c.categories[0].entries[0].id
        c.setIcon("eq", entry: id, in: c.favoritesID)
        c.setDisplayName("EQ8", entry: id, in: c.favoritesID)
        XCTAssertEqual(c.categories[0].entries[0].iconID, "eq")
        XCTAssertEqual(c.categories[0].entries[0].title, "EQ8")
        c.removeEntry(id, from: c.favoritesID)
        XCTAssertTrue(c.categories[0].entries.isEmpty)
    }
}
