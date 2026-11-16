import XCTest
@testable import HMLauncherCore

final class FolderEditingTests: XCTestCase {
    let la2 = item("LA-2", uri: "la2", path: ["VST3", "UA"])
    let ssl = item("SSL E Channel", uri: "ssl", path: ["VST3", "UA"])
    let eq = item("EQ Eight", uri: "eq", source: .audioEffects)

    func makeConfig() -> (LauncherConfig, UUID, UUID) {
        var c = LauncherConfig.makeDefault()
        let fx = c.categories[2].id
        c.addEntry(eq, to: fx)
        let folder = c.addFolder(named: "UAD", to: fx)
        c.addEntry(la2, to: fx, folder: folder)
        c.addEntry(ssl, to: fx, folder: folder)
        return (c, fx, folder)
    }

    func testAddFolderAndEntriesIntoIt() {
        let (c, _, _) = makeConfig()
        let fx = c.categories[2].entries
        XCTAssertEqual(fx.map(\.title), ["EQ Eight", "UAD"])
        XCTAssertTrue(fx[1].isFolder)
        XCTAssertFalse(fx[0].isFolder)
        XCTAssertEqual(fx[1].iconID, "folder")
        XCTAssertEqual(fx[1].children?.map(\.name), ["LA-2", "SSL E Channel"])
        XCTAssertEqual(fx[1].children?[1].iconID, "console")
    }

    func testNoDuplicateInsideSameFolder() {
        var (c, fx, folder) = makeConfig()
        c.addEntry(la2, to: fx, folder: folder)
        XCTAssertEqual(c.categories[2].entries[1].children?.count, 2)
    }

    func testMoveEntryIntoAndOutOfFolder() {
        var (c, fx, folder) = makeConfig()
        let eqID = c.categories[2].entries[0].id
        c.moveEntry(eqID, toFolder: folder, in: fx)
        XCTAssertEqual(c.categories[2].entries.map(\.title), ["UAD"])
        XCTAssertEqual(c.categories[2].entries[0].children?.map(\.name), ["LA-2", "SSL E Channel", "EQ Eight"])
        c.moveEntry(eqID, toFolder: nil, in: fx)
        XCTAssertEqual(c.categories[2].entries.map(\.title), ["UAD", "EQ Eight"])
    }

    func testFoldersCannotGoIntoFolders() {
        var (c, fx, folder) = makeConfig()
        let other = c.addFolder(named: "Other", to: fx)
        c.moveEntry(other, toFolder: folder, in: fx)
        XCTAssertEqual(c.categories[2].entries.map(\.title), ["EQ Eight", "UAD", "Other"])
    }

    func testReorderInsideFolder() {
        var (c, fx, folder) = makeConfig()
        c.moveEntry(in: fx, folder: folder, from: 1, to: 0)
        XCTAssertEqual(c.categories[2].entries[1].children?.map(\.name), ["SSL E Channel", "LA-2"])
    }

    func testDissolveFolderKeepsChildrenInPlace() {
        var (c, fx, folder) = makeConfig()
        c.addEntry(item("Utility", source: .audioEffects), to: fx)
        c.dissolveFolder(folder, in: fx)
        XCTAssertEqual(c.categories[2].entries.map(\.title), ["EQ Eight", "LA-2", "SSL E Channel", "Utility"])
    }

    func testRemoveRenameAndIconForNestedEntries() {
        var (c, fx, folder) = makeConfig()
        let la2ID = c.categories[2].entries[1].children![0].id
        c.setDisplayName("LA-2A", entry: la2ID, in: fx)
        c.setIcon("heart", entry: la2ID, in: fx)
        XCTAssertEqual(c.categories[2].entries[1].children?[0].title, "LA-2A")
        XCTAssertEqual(c.categories[2].entries[1].children?[0].iconID, "heart")
        c.renameFolder(folder, in: fx, to: "Universal Audio")
        XCTAssertEqual(c.categories[2].entries[1].title, "Universal Audio")
        c.removeEntry(la2ID, from: fx)
        XCTAssertEqual(c.categories[2].entries[1].children?.map(\.name), ["SSL E Channel"])
        c.removeEntry(folder, from: fx)
        XCTAssertEqual(c.categories[2].entries.map(\.title), ["EQ Eight"])
    }

    func testIconSyncReachesIntoFolders() {
        var (c, fx, _) = makeConfig()
        c.addEntry(la2, to: c.favoritesID)
        c.setIcon("star", entry: c.categories[0].entries[0].id, in: c.favoritesID)
        XCTAssertEqual(c.categories[2].entries[1].children?[0].iconID, "star")
        c.addEntry(ssl, to: c.favoritesID)
        XCTAssertEqual(c.categories[0].entries[1].iconID, "console") // reused from inside the folder
        _ = fx
    }

    func testOldEntriesWithoutChildrenDecodeAsPlugins() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","uri":"u","name":"X","source":"plugins","path":[],"iconID":"generic"}"#
        let e = try JSONDecoder().decode(Entry.self, from: Data(json.utf8))
        XCTAssertFalse(e.isFolder)
        XCTAssertNil(e.children)
    }

    func testFolderRoundTrip() throws {
        let (c, _, _) = makeConfig()
        let d = try JSONDecoder().decode(LauncherConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(d.categories[2].entries[1].children?.count, 2)
    }
}

final class PanelFolderTests: XCTestCase {
    let la2 = item("LA-2", uri: "la2", path: ["VST3", "UA"])
    let ssl = item("SSL E Channel", uri: "ssl", path: ["VST3", "UA"])
    let eq = item("EQ Eight", uri: "eq", source: .audioEffects)

    func makeState() -> PanelState {
        var c = LauncherConfig.makeDefault()
        let fav = c.favoritesID
        c.addEntry(eq, to: fav)
        let folder = c.addFolder(named: "UAD", to: fav)
        c.addEntry(la2, to: fav, folder: folder)
        c.addEntry(ssl, to: fav, folder: folder)
        return PanelState(config: c, items: [eq, la2, ssl])
    }

    func testFolderRowShowsCountAndOpensOnDigit() {
        var s = makeState()
        XCTAssertEqual(s.rows.map(\.title), ["EQ Eight", "UAD"])
        XCTAssertEqual(s.rows[1].childCount, 2)
        XCTAssertNotNil(s.rows[1].folderID)
        XCTAssertEqual(s.handle(.digit(2)), PanelAction.none)
        XCTAssertEqual(s.openFolderName, "UAD")
        XCTAssertEqual(s.rows.map(\.title), ["LA-2", "SSL E Channel"])
        XCTAssertEqual(s.handle(.digit(2)), .insert(s.rows[1]))
        XCTAssertEqual(s.rows[1].uri, "ssl")
    }

    func testReturnOnHighlightedFolderOpensIt() {
        var s = makeState()
        _ = s.handle(.down); _ = s.handle(.down)
        XCTAssertEqual(s.handle(.returnKey), PanelAction.none)
        XCTAssertEqual(s.openFolderName, "UAD")
        XCTAssertNil(s.highlighted)
    }

    func testEscapeLeavesFolderThenCloses() {
        var s = makeState()
        _ = s.handle(.digit(2))
        XCTAssertEqual(s.handle(.escape), PanelAction.none)
        XCTAssertNil(s.openFolderName)
        XCTAssertEqual(s.handle(.escape), .close)
    }

    func testBackspaceWithEmptyFilterLeavesFolder() {
        var s = makeState()
        _ = s.handle(.digit(2))
        _ = s.handle(.character("s"))
        _ = s.handle(.backspace)
        XCTAssertEqual(s.openFolderName, "UAD")
        _ = s.handle(.backspace)
        XCTAssertNil(s.openFolderName)
    }

    func testFilterAtTopLevelFindsPluginsInsideFolders() {
        var s = makeState()
        for ch in "la-2" { _ = s.handle(.character(ch)) }
        XCTAssertEqual(s.rows.map(\.title), ["LA-2"])
        XCTAssertEqual(s.handle(.returnKey), .insert(s.rows[0]))
    }

    func testTabSwitchLeavesFolder() {
        var s = makeState()
        _ = s.handle(.digit(2))
        _ = s.handle(.right)
        _ = s.handle(.left)
        XCTAssertNil(s.openFolderName)
        XCTAssertEqual(s.rows.map(\.title), ["EQ Eight", "UAD"])
    }

    func testOpenAndCloseFolderDirectly() {
        var s = makeState()
        s.openFolder(s.rows[1].folderID!)
        XCTAssertEqual(s.rows.count, 2)
        s.closeFolder()
        XCTAssertNil(s.openFolderName)
    }
}
