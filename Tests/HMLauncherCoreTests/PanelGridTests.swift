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

final class PanelSizeTests: XCTestCase {
    func testDefaultsAndLimits() throws {
        var c = LauncherConfig.makeDefault()
        XCTAssertEqual(c.panelSize, PanelSize.default)
        XCTAssertEqual(PanelSize.default.columnWidth, 316)
        XCTAssertEqual(PanelSize.default.itemHeight, 42)
        c.panelSize = PanelSize(columnWidth: 2000, itemHeight: 5)
        XCTAssertEqual(c.panelSize.columnWidth, PanelSize.widthRange.upperBound)
        XCTAssertEqual(c.panelSize.itemHeight, PanelSize.heightRange.lowerBound)
        c.panelSize = PanelSize(columnWidth: 400, itemHeight: 52)
        let back = try JSONDecoder().decode(LauncherConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.panelSize, PanelSize(columnWidth: 400, itemHeight: 52))
        let old = #"{"version": 4, "categories": []}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(LauncherConfig.self, from: old).panelSize, .default)
    }
}

final class PanelGridDragTests: XCTestCase {
    // Columns 100 pt apart, rows 50 pt apart.
    func slot(_ x: Double, _ y: Double, count: Int = 30, columns: Int = 2) -> Int {
        PanelGrid.index(atX: x, y: y, columns: columns, columnStride: 100, rowStride: 50, count: count)
    }

    func testPositionMapsToTheSlotUnderIt() {
        XCTAssertEqual(slot(10, 10), 0)
        XCTAssertEqual(slot(10, 120), 2)
        XCTAssertEqual(slot(150, 10), 9)        // second column starts at 9
        XCTAssertEqual(slot(150, 440), 17)
        XCTAssertEqual(slot(10, 440), 8)
        XCTAssertEqual(slot(10, 470), 18)       // next block below
    }

    func testOutsideIsClamped() {
        XCTAssertEqual(slot(-20, -20), 0)
        XCTAssertEqual(slot(900, 10), 9)        // right of the last column
        XCTAssertEqual(slot(150, 100, count: 5), 4) // empty slot → last entry
    }

    func testDisplayOrderMovesOneEntry() {
        XCTAssertEqual(PanelGrid.order(count: 5, moving: 1, to: 3), [0, 2, 3, 1, 4])
        XCTAssertEqual(PanelGrid.order(count: 5, moving: 4, to: 0), [4, 0, 1, 2, 3])
        XCTAssertEqual(PanelGrid.order(count: 3, moving: 1, to: 1), [0, 1, 2])
    }
}

final class PanelPadTests: XCTestCase {
    func testPadRowsPerBlock() {
        XCTAssertEqual(PanelGrid.padRows(inBlock: 0), 0)
        XCTAssertEqual(PanelGrid.padRows(inBlock: 1), 1)
        XCTAssertEqual(PanelGrid.padRows(inBlock: 4), 2)
        XCTAssertEqual(PanelGrid.padRows(inBlock: 9), 3)
    }

    func testPadRowsFollowBlocks() {
        XCTAssertEqual(PanelGrid.padRows(4, columns: 2), 2)
        XCTAssertEqual(PanelGrid.padRows(12, columns: 2), 3)     // 9 + 3 side by side
        XCTAssertEqual(PanelGrid.padRows(23, columns: 2), 5)     // one full block row + 5 below
        XCTAssertEqual(PanelGrid.padRows(25, columns: 1), 9)     // 9 + 9 + 7 stacked
        XCTAssertEqual(PanelGrid.blockRows(23, columns: 2), 2)
        XCTAssertEqual(PanelGrid.blockRows(0, columns: 2), 0)
    }

    func testPadIndexUnderPoint() {
        // pads 100 + 6 wide, 66 + 6 tall, blocks 318 + 12 wide, 3 rows + 12 tall
        func idx(_ x: Double, _ y: Double, count: Int = 30) -> Int {
            PanelGrid.padIndex(atX: x, y: y, columns: 2, blockStride: 330, padStride: 106,
                               blockRowStride: 228, padRowStride: 72, count: count)
        }
        XCTAssertEqual(idx(10, 10), 0)
        XCTAssertEqual(idx(220, 10), 2)
        XCTAssertEqual(idx(10, 80), 3)
        XCTAssertEqual(idx(220, 150), 8)
        XCTAssertEqual(idx(340, 10), 9)
        XCTAssertEqual(idx(10, 240), 18)
        XCTAssertEqual(idx(900, 900, count: 12), 11)            // clamped
    }

    func testPadPosition() {
        XCTAssertTrue(PanelGrid.padPosition(of: 4, columns: 2) == (0, 1, 1))
        XCTAssertTrue(PanelGrid.padPosition(of: 11, columns: 2) == (1, 0, 2))
        XCTAssertTrue(PanelGrid.padPosition(of: 19, columns: 2) == (0, 0, 1))
    }
}

final class PanelPageTests: XCTestCase {
    func testGridFillsRowByRowListColumnByColumn() {
        let grid = PanelPage(columns: 3, rows: 2, columnMajor: false)
        XCTAssertEqual(grid.slot(row: 1, column: 0), 3)
        XCTAssertTrue(grid.position(of: 4) == (1, 1))
        let list = PanelPage(columns: 2, rows: 9, columnMajor: true)
        XCTAssertEqual(list.slot(row: 0, column: 1), 9)
        XCTAssertTrue(list.position(of: 10) == (1, 1))
        XCTAssertTrue(list.position(of: 18 + 3) == (3, 0))   // next page
    }

    func testStyleAndListSizeDecodeAndClamp() throws {
        var c = LauncherConfig.makeDefault()
        XCTAssertEqual(c.panelStyle, .grid)
        XCTAssertEqual(c.panelPage.size, 9)
        c.panelStyle = .list
        c.panelList.rows = 12
        c.panelList.columns = 0
        XCTAssertEqual(c.panelList, PanelListSize(columns: 1, rows: 9))
        let back = try JSONDecoder().decode(LauncherConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.panelStyle, .list)
        XCTAssertEqual(back.panelPage, PanelPage(columns: 1, rows: 9, columnMajor: true))
    }
}
