import XCTest
@testable import HMLauncherCore

final class PanelGridTests: XCTestCase {
    func testUpToNineIsOneColumn() {
        XCTAssertEqual(PanelGrid.blocks(0..<4), [[[0, 1, 2, 3], []]])
        XCTAssertEqual(PanelGrid.rows(4), 4)
    }

    func testFillsLeftColumnThenRight() {
        let b = PanelGrid.blocks(0..<12)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b[0][0], Array(0..<9))
        XCTAssertEqual(b[0][1], [9, 10, 11])
        XCTAssertEqual(PanelGrid.rows(12), 9)
    }

    func testMoreThanEighteenContinuesBelow() {
        let b = PanelGrid.blocks(0..<23)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b[1][0], [18, 19, 20, 21, 22])
        XCTAssertEqual(b[1][1], [])
        XCTAssertEqual(PanelGrid.rows(23), 14)
        XCTAssertEqual(PanelGrid.rows(36), 18)
    }

    func testRangeOffsetsAreKept() {
        XCTAssertEqual(PanelGrid.blocks(3..<6), [[[3, 4, 5], []]])
    }
}

final class PanelGridColumnsTests: XCTestCase {
    func testOneColumnUpToNineRowsTwoBeyond() {
        XCTAssertEqual(PanelGrid.columnsNeeded(local: 4, global: 0), 1)
        XCTAssertEqual(PanelGrid.columnsNeeded(local: 9, global: 0), 1)
        XCTAssertEqual(PanelGrid.columnsNeeded(local: 10, global: 0), 2)
        XCTAssertEqual(PanelGrid.columnsNeeded(local: 3, global: 12), 2)   // search hits spill into the second column
        XCTAssertEqual(PanelGrid.columnsNeeded(local: 0, global: 0), 1)
    }
}

final class PanelGridSettingTests: XCTestCase {
    func testColumnsGrowUpToTheSetting() {
        XCTAssertEqual(PanelGrid.columnsNeeded(local: 25, global: 0, max: 3), 3)   // 9 + 9 + 7
        XCTAssertEqual(PanelGrid.columnsNeeded(local: 25, global: 0, max: 2), 2)
        XCTAssertEqual(PanelGrid.columnsNeeded(local: 12, global: 0, max: 5), 2)   // only as many as needed
        XCTAssertEqual(PanelGrid.columnsNeeded(local: 80, global: 0, max: 9), 9)
        XCTAssertEqual(PanelGrid.columnsNeeded(local: 25, global: 0, max: 1), 1)
    }

    func testBlocksAndRowsFollowTheColumnCount() {
        let b = PanelGrid.blocks(0..<25, columns: 3)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b[0].map(\.count), [9, 9, 7])
        XCTAssertEqual(PanelGrid.rows(25, columns: 3), 9)
        XCTAssertEqual(PanelGrid.rows(25, columns: 1), 25)
    }

    func testConfigKeepsTheSettingBetweenOneAndNine() throws {
        var c = LauncherConfig.makeDefault()
        XCTAssertEqual(c.panelColumns, 2)
        c.panelColumns = 14
        XCTAssertEqual(c.panelColumns, 9)
        c.panelColumns = 0
        XCTAssertEqual(c.panelColumns, 1)
        c.panelColumns = 4
        XCTAssertEqual(try JSONDecoder().decode(LauncherConfig.self, from: JSONEncoder().encode(c)).panelColumns, 4)
        let old = #"{"version": 4, "categories": []}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(LauncherConfig.self, from: old).panelColumns, 2)
    }
}
