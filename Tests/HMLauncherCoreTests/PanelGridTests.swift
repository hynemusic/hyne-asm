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
