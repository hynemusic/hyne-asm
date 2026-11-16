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
