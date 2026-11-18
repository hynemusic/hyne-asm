import XCTest
@testable import HMLauncherCore

final class DigitKeysTests: XCTestCase {
    func testNumberRowAndKeypadByPosition() {
        XCTAssertEqual(DigitKeys.digit(forKeyCode: 18), 1)
        XCTAssertEqual(DigitKeys.digit(forKeyCode: 25), 9)
        XCTAssertEqual(DigitKeys.digit(forKeyCode: 29), 0)
        XCTAssertEqual(DigitKeys.digit(forKeyCode: 83), 1)   // keypad 1
        XCTAssertEqual(DigitKeys.digit(forKeyCode: 92), 9)   // keypad 9
        XCTAssertNil(DigitKeys.digit(forKeyCode: 0))          // A
    }
}
