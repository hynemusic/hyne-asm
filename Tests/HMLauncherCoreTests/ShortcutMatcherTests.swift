import XCTest
@testable import HMLauncherCore

final class ShortcutMatcherTests: XCTestCase {
    func testDefaultShortcuts() {
        let m = ShortcutMatcher(settings: .default)
        XCTAssertEqual(m.match(keyCode: 13, modifiers: [.cmd]), .closeFocused)
        XCTAssertEqual(m.match(keyCode: 13, modifiers: [.cmd, .alt]), .closeAll)
        XCTAssertEqual(m.match(keyCode: 53, modifiers: [.cmd]), .closeAll)
        XCTAssertNil(m.match(keyCode: 13, modifiers: [.cmd, .shift]))
        XCTAssertNil(m.match(keyCode: 13, modifiers: []))
    }

    func testDisabledShortcutsMatchNothing() {
        let m = ShortcutMatcher(settings: ShortcutSettings(closeFocused: nil, closeAll: []))
        XCTAssertNil(m.match(keyCode: 13, modifiers: [.cmd]))
        XCTAssertNil(m.match(keyCode: 53, modifiers: [.cmd]))
    }
}
