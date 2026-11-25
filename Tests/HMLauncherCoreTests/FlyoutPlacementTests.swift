import XCTest
@testable import HMLauncherCore

final class FlyoutPlacementTests: XCTestCase {
    // Panel 1000…1400 with two columns: left pad 1010…1200, right pad 1210…1390. List 280 wide, screen 0…3000.
    private func x(_ padMin: Double, _ padMax: Double, screen: (Double, Double) = (0, 3000)) -> Double {
        FlyoutPlacement.x(padMinX: padMin, padMaxX: padMax, panelMinX: 1000, panelMaxX: 1400,
                          width: 280, screenMinX: screen.0, screenMaxX: screen.1)
    }

    func testLeftColumnOpensLeftRightColumnOpensRight() {
        XCTAssertEqual(x(1010, 1200), 1010 - 2 - 280)
        XCTAssertEqual(x(1210, 1390), 1392)
    }

    func testCentredPadOpensRight() {
        XCTAssertEqual(x(1010, 1390), 1392)
    }

    func testNoRoomUsesTheOtherSide() {
        XCTAssertEqual(x(1010, 1200, screen: (900, 3000)), 1202) // left column at the screen's left edge
        XCTAssertEqual(x(1210, 1390, screen: (0, 1500)), 1210 - 2 - 280) // right column at the screen's right edge
    }

    func testNoRoomEitherSideStaysOnScreen() {
        XCTAssertEqual(x(1010, 1390, screen: (900, 1500)), 1500 - 280)
        XCTAssertEqual(x(1010, 1200, screen: (1000, 1250)), 1000)
    }
}
