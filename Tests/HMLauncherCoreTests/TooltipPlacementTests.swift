import XCTest
import CoreGraphics
@testable import HMLauncherCore

final class TooltipPlacementTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 100, height: 20)

    func testCenteredBelowTheControl() {
        let f = TooltipPlacement.frame(size: size, below: CGRect(x: 450, y: 400, width: 20, height: 20), visible: screen)
        XCTAssertEqual(f, CGRect(x: 410, y: 374, width: 100, height: 20))
    }

    func testRightEdgeStaysOnScreen() {   // the panel's gear sits at the top-right corner
        let f = TooltipPlacement.frame(size: size, below: CGRect(x: 985, y: 760, width: 14, height: 14), visible: screen)
        XCTAssertEqual(f.maxX, 996)
        XCTAssertTrue(screen.contains(f))
    }

    func testFlipsAboveAtTheBottomEdge() {
        let f = TooltipPlacement.frame(size: size, below: CGRect(x: 450, y: 5, width: 20, height: 20), visible: screen)
        XCTAssertEqual(f.minY, 31)
    }
}
