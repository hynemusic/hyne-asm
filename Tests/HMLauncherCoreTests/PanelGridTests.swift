import XCTest
@testable import HMLauncherCore

final class PanelGridTests: XCTestCase {
    func testUpToTenIsOneColumn() {
        XCTAssertEqual(PanelGrid.blocks(0..<4), [[[0, 1, 2, 3], []]])
        XCTAssertEqual(PanelGrid.rows(4), 4)
    }

    func testFillsLeftColumnThenRight() {
        let b = PanelGrid.blocks(0..<13)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b[0][0], Array(0..<10))
        XCTAssertEqual(b[0][1], [10, 11, 12])
        XCTAssertEqual(PanelGrid.rows(13), 10)
    }

    func testMoreThanTwentyContinuesBelow() {
        let b = PanelGrid.blocks(0..<25)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b[1][0], [20, 21, 22, 23, 24])
        XCTAssertEqual(b[1][1], [])
        XCTAssertEqual(PanelGrid.rows(25), 15)
        XCTAssertEqual(PanelGrid.rows(40), 20)
    }

    func testRangeOffsetsAreKept() {
        XCTAssertEqual(PanelGrid.blocks(3..<6), [[[3, 4, 5], []]])
    }
}
