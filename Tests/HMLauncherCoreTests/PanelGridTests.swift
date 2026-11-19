import XCTest
@testable import HMLauncherCore

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
    func testDisplayOrderMovesOneEntry() {
        XCTAssertEqual(PanelGrid.order(count: 5, moving: 1, to: 3), [0, 2, 3, 1, 4])
        XCTAssertEqual(PanelGrid.order(count: 5, moving: 4, to: 0), [4, 0, 1, 2, 3])
        XCTAssertEqual(PanelGrid.order(count: 3, moving: 1, to: 1), [0, 1, 2])
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
