import XCTest
@testable import HMLauncherCore

final class DoubleRightClickDetectorTests: XCTestCase {
    func testSingleClickPassesThrough() {
        var d = DoubleRightClickDetector(interval: 0.4)
        XCTAssertEqual(d.rightMouseDown(at: 10), .passThrough)
    }

    func testSecondClickWithinIntervalOpens() {
        var d = DoubleRightClickDetector(interval: 0.4)
        _ = d.rightMouseDown(at: 10)
        XCTAssertEqual(d.rightMouseDown(at: 10.3), .openPanel)
    }

    func testSecondClickAfterIntervalIsNewFirst() {
        var d = DoubleRightClickDetector(interval: 0.4)
        _ = d.rightMouseDown(at: 10)
        XCTAssertEqual(d.rightMouseDown(at: 10.5), .passThrough)
        XCTAssertEqual(d.rightMouseDown(at: 10.7), .openPanel)
    }

    func testTripleClickOpensOnlyOnce() {
        var d = DoubleRightClickDetector(interval: 0.4)
        let verdicts = [10, 10.1, 10.2].map { d.rightMouseDown(at: $0) }
        XCTAssertEqual(verdicts, [.passThrough, .openPanel, .passThrough])
    }
}
