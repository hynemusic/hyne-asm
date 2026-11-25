import XCTest
@testable import HMLauncherCore

final class MultiEditTests: XCTestCase {
    var c = LauncherConfig.makeDefault()
    var fx: UUID!
    var ids: [String: UUID] = [:]

    override func setUp() {
        c = LauncherConfig.makeDefault()
        fx = c.categories[2].id
        for n in ["A", "B", "C", "D", "E"] {
            c.addEntry(item(n, uri: "u:\(n)"), to: fx)
            ids[n] = c.categories[2].entries.last!.id
        }
    }

    private var top: [String] { c.categories[2].entries.map(\.title) }

    func testMoveEntriesBeforeAnchorKeepsOrder() {
        c.moveEntries([ids["B"]!, ids["D"]!], toFolder: nil, before: ids["A"]!, in: fx)
        XCTAssertEqual(top, ["B", "D", "A", "C", "E"])
    }

    func testMoveEntriesToEnd() {
        c.moveEntries([ids["A"]!, ids["B"]!], toFolder: nil, before: nil, in: fx)
        XCTAssertEqual(top, ["C", "D", "E", "A", "B"])
    }

    func testMoveEntriesIntoFolderAndBackOut() {
        let f = c.addFolder(named: "F", to: fx)
        c.moveEntries([ids["A"]!, ids["C"]!], toFolder: f, before: nil, in: fx)
        XCTAssertEqual(top, ["B", "D", "E", "F"])
        XCTAssertEqual(c.categories[2].entries[3].children?.map(\.title), ["A", "C"])
        c.moveEntries([ids["E"]!], toFolder: f, before: ids["C"]!, in: fx)
        XCTAssertEqual(c.categories[2].entries[2].children?.map(\.title), ["A", "E", "C"])
        c.moveEntries([ids["A"]!, ids["C"]!], toFolder: nil, before: ids["B"]!, in: fx)
        XCTAssertEqual(top, ["A", "C", "B", "D", "F"])
    }

    func testFoldersStayOutOfFolders() {
        let f = c.addFolder(named: "F", to: fx)
        let g = c.addFolder(named: "G", to: fx)
        c.moveEntries([g, ids["A"]!], toFolder: f, before: nil, in: fx)
        XCTAssertEqual(top, ["B", "C", "D", "E", "F", "G"])
        XCTAssertEqual(c.categories[2].entries[4].children?.map(\.title), ["A"])
    }

    func testMovingAFolderAtTopLevel() {
        let f = c.addFolder(named: "F", to: fx)
        c.moveEntries([f], toFolder: nil, before: ids["A"]!, in: fx)
        XCTAssertEqual(top, ["F", "A", "B", "C", "D", "E"])
    }

    func testGroupCreatesFolderAtFirstSelectedPosition() {
        let folder = c.groupEntries([ids["D"]!, ids["B"]!], in: fx, named: "Group")
        XCTAssertEqual(top, ["A", "Group", "C", "E"])
        XCTAssertEqual(c.findEntry(folder!, in: fx)?.children?.map(\.title), ["B", "D"]) // list order, not click order
    }

    func testGroupTakesPluginsFromOtherFoldersAndIgnoresFolders() {
        let f = c.addFolder(named: "F", to: fx)
        c.moveEntries([ids["E"]!], toFolder: f, before: nil, in: fx)
        let folder = c.groupEntries([ids["A"]!, ids["E"]!, f], in: fx, named: "Group")
        XCTAssertEqual(top, ["Group", "B", "C", "D", "F"])
        XCTAssertEqual(c.findEntry(folder!, in: fx)?.children?.map(\.title), ["A", "E"])
        XCTAssertEqual(c.findEntry(f, in: fx)?.children?.count, 0)
    }

    func testGroupWithOnlyFoldersDoesNothing() {
        let f = c.addFolder(named: "F", to: fx)
        XCTAssertNil(c.groupEntries([f], in: fx, named: "Group"))
        XCTAssertEqual(top, ["A", "B", "C", "D", "E", "F"])
    }

    func testOrderedIDsFollowListOrder() {
        let f = c.addFolder(named: "F", to: fx)
        c.moveEntries([ids["A"]!], toFolder: f, before: nil, in: fx)
        XCTAssertEqual(c.orderedEntryIDs(in: fx), [ids["B"]!, ids["C"]!, ids["D"]!, ids["E"]!, f, ids["A"]!])
    }
}

final class MoveToCategoryTests: XCTestCase {
    func testMoveEntriesToOtherCategory() {
        var c = LauncherConfig.makeDefault()
        let fx = c.categories[2].id, inst = c.categories[1].id
        for n in ["A", "B", "C"] { c.addEntry(item(n, uri: "u:\(n)"), to: fx) }
        let f = c.addFolder(named: "F", to: fx)
        c.addEntry(item("D", uri: "u:D"), to: fx, folder: f)
        c.addEntry(item("B", uri: "u:B"), to: inst) // already there → no duplicate
        let ids = c.categories[2].entries
        let d = c.findEntry(f, in: fx)!.children![0].id
        c.moveEntries([ids[0].id, ids[1].id, d, f], toCategory: inst, from: fx)
        XCTAssertEqual(c.categories[2].entries.map(\.title), ["C"])
        XCTAssertEqual(c.categories[1].entries.map(\.title), ["B", "A", "F"])
        XCTAssertEqual(c.categories[1].entries[2].children?.map(\.title), ["D"]) // moved folder keeps its plugins
    }

    func testMovePluginOutOfFolderIntoOtherCategory() {
        var c = LauncherConfig.makeDefault()
        let fx = c.categories[2].id, inst = c.categories[1].id
        let f = c.addFolder(named: "F", to: fx)
        c.addEntry(item("D", uri: "u:D"), to: fx, folder: f)
        let d = c.findEntry(f, in: fx)!.children![0].id
        c.moveEntries([d], toCategory: inst, from: fx)
        XCTAssertEqual(c.findEntry(f, in: fx)?.children?.count, 0)
        XCTAssertEqual(c.categories[1].entries.map(\.title), ["D"])
    }

    func testMoveToSameCategoryDoesNothing() {
        var c = LauncherConfig.makeDefault()
        let fx = c.categories[2].id
        c.addEntry(item("A", uri: "u:A"), to: fx)
        c.moveEntries([c.categories[2].entries[0].id], toCategory: fx, from: fx)
        XCTAssertEqual(c.categories[2].entries.map(\.title), ["A"])
    }
}

extension MultiEditTests {
    // MARK: Copy, cut, paste

    func testCopyPasteAddsNewEntriesAfterAnchor() throws {
        let other = c.categories[1].id
        let clip = try XCTUnwrap(c.clipboard([ids["B"]!, ids["D"]!], in: fx, cut: false))
        let pasted = c.paste(clip, into: other, folder: nil, before: nil)
        XCTAssertEqual(c.categories[1].entries.map(\.title), ["B", "D"])
        XCTAssertEqual(top, ["A", "B", "C", "D", "E"]) // the originals stay
        XCTAssertFalse(pasted.contains(ids["B"]!)) // new ids
    }

    func testCopyIntoSameContainerSkipsPluginsItHolds() throws {
        let clip = try XCTUnwrap(c.clipboard([ids["A"]!], in: fx, cut: false))
        XCTAssertEqual(c.paste(clip, into: fx, folder: nil, before: nil), [])
        XCTAssertEqual(top, ["A", "B", "C", "D", "E"])
    }

    func testCutPasteMovesInFrontOfAnchor() throws {
        let clip = try XCTUnwrap(c.clipboard([ids["D"]!, ids["E"]!], in: fx, cut: true))
        let pasted = c.paste(clip, into: fx, folder: nil, before: ids["B"]!)
        XCTAssertEqual(top, ["A", "D", "E", "B", "C"])
        XCTAssertEqual(pasted, [ids["D"]!, ids["E"]!]) // ids kept
    }

    func testCutPasteIntoFolderAndAcrossCategories() throws {
        let folder = c.addFolder(named: "F", to: fx)
        let clip = try XCTUnwrap(c.clipboard([ids["A"]!, ids["C"]!], in: fx, cut: true))
        c.paste(clip, into: fx, folder: folder, before: nil)
        XCTAssertEqual(top, ["B", "D", "E", "F"])
        XCTAssertEqual(c.findEntry(folder, in: fx)?.children?.map(\.title), ["A", "C"])
        // The whole folder, cut, to another category: it moves with its plugins.
        let other = c.categories[1].id
        c.paste(try XCTUnwrap(c.clipboard([folder], in: fx, cut: true)), into: other, folder: nil, before: nil)
        XCTAssertEqual(top, ["B", "D", "E"])
        XCTAssertEqual(c.categories[1].entries.first?.children?.map(\.title), ["A", "C"])
    }

    func testFolderPastedIntoFolderGivesItsPluginsAndNeverIntoItself() throws {
        let f = c.addFolder(named: "F", to: fx)
        let g = c.addFolder(named: "G", to: fx)
        c.moveEntries([ids["A"]!], toFolder: f, before: nil, in: fx)
        let copy = try XCTUnwrap(c.clipboard([f], in: fx, cut: false))
        c.paste(copy, into: fx, folder: g, before: nil)
        XCTAssertEqual(c.findEntry(g, in: fx)?.children?.map(\.title), ["A"])
        let cut = try XCTUnwrap(c.clipboard([f], in: fx, cut: true))
        XCTAssertEqual(c.paste(cut, into: fx, folder: f, before: nil), [])
        XCTAssertEqual(c.findEntry(f, in: fx)?.children?.map(\.title), ["A"])
    }

    func testSelectedFolderCarriesItsPluginsOnce() throws {
        let f = c.addFolder(named: "F", to: fx)
        c.moveEntries([ids["A"]!], toFolder: f, before: nil, in: fx)
        let a: UUID = ids["A"]!
        let picked: Set<UUID> = [f, a]
        let clip = try XCTUnwrap(c.clipboard(picked, in: fx, cut: false))
        XCTAssertEqual(clip.entries.map(\.title), ["F"])
    }
}
