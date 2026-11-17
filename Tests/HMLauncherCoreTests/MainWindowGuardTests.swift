import XCTest
@testable import HMLauncherCore

final class MainWindowGuardTests: XCTestCase {
    // Real layout seen from Live 12: floating Serum window on layer 3, main window "Untitled" on layer 0.
    let screen = [
        MainWindowGuard.ScreenWindow(frame: CGRect(x: 54, y: 84, width: 1190, height: 759), layer: 3, title: "Serum 2/inst1"),
        MainWindowGuard.ScreenWindow(frame: CGRect(x: 0, y: 940, width: 500, height: 500), layer: 0, title: ""),
        MainWindowGuard.ScreenWindow(frame: CGRect(x: 0, y: 30, width: 2560, height: 1410), layer: 0, title: "Untitled"),
        MainWindowGuard.ScreenWindow(frame: CGRect(x: -2056, y: 111, width: 2056, height: 39), layer: 0, title: ""),
    ]

    func testMainWindowWithSetNameIsProtected() {
        XCTAssertTrue(MainWindowGuard.isMain(frame: CGRect(x: 0, y: 30, width: 2560, height: 1410), title: "Untitled", isAXMain: false, screen: screen))
    }

    func testFloatingPluginWindowIsNotProtected() {
        XCTAssertFalse(MainWindowGuard.isMain(frame: CGRect(x: 54, y: 84, width: 1190, height: 759), title: "Serum 2/inst1", isAXMain: false, screen: screen))
    }

    func testAXMainAndOldStyleTitleAreProtected() {
        XCTAssertTrue(MainWindowGuard.isMain(frame: nil, title: "x", isAXMain: true, screen: []))
        XCTAssertTrue(MainWindowGuard.isMain(frame: nil, title: "Song - Ableton Live 12 Suite", isAXMain: false, screen: []))
    }

    func testSecondLiveWindowWithSameSetNameIsProtected() {
        var s = screen
        s.append(.init(frame: CGRect(x: 2560, y: 0, width: 1920, height: 1080), layer: 0, title: "Untitled"))
        XCTAssertTrue(MainWindowGuard.isMain(frame: CGRect(x: 2560, y: 0, width: 1920, height: 1080), title: "Untitled", isAXMain: false, screen: s))
    }
}
