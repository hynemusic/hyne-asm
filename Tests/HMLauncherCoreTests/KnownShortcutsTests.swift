import XCTest
@testable import HMLauncherCore

final class KnownShortcutsTests: XCTestCase {
    /// US layout for the letters these tests use; German swaps Y and Z.
    let us: [Character: UInt16] = ["d": 2, "z": 6, "y": 16, "s": 1, "w": 13, "m": 46]
    let de: [Character: UInt16] = ["d": 2, "z": 16, "y": 6, "s": 1, "w": 13, "m": 46]

    func testFindsLiveAndMacConflicts() {
        let cmdD = KeyCombo(keyCode: 2, modifiers: [.cmd])
        XCTAssertEqual(KnownShortcuts.conflicts(with: cmdD) { us[$0] }.map(\.app), [.live])
        let cmdM = KeyCombo(keyCode: 46, modifiers: [.cmd])
        XCTAssertEqual(Set(KnownShortcuts.conflicts(with: cmdM) { us[$0] }.map(\.app)), [.live, .macOS])
        let cmdSpace = KeyCombo(keyCode: 49, modifiers: [.cmd])
        XCTAssertEqual(KnownShortcuts.conflicts(with: cmdSpace) { _ in nil }.first?.app, .macOS)
    }

    func testModifiersMustMatchExactly() {
        XCTAssertTrue(KnownShortcuts.conflicts(with: KeyCombo(keyCode: 2, modifiers: [.cmd, .ctrl, .alt])) { us[$0] }.isEmpty)
    }

    func testFollowsKeyboardLayout() {
        let physicalZ = KeyCombo(keyCode: 6, modifiers: [.cmd])   // "Z" on US, "Y" on German
        XCTAssertFalse(KnownShortcuts.conflicts(with: physicalZ) { us[$0] }.isEmpty)
        XCTAssertTrue(KnownShortcuts.conflicts(with: physicalZ) { de[$0] }.isEmpty)
        XCTAssertFalse(KnownShortcuts.conflicts(with: KeyCombo(keyCode: 16, modifiers: [.cmd])) { de[$0] }.isEmpty)
    }

    func testNoDuplicatesPerApp() {
        for list in [KnownShortcuts.live, KnownShortcuts.macOS] {
            let keys = list.map { "\($0.key)|\($0.modifiers.rawValue)" }
            XCTAssertEqual(keys.count, Set(keys).count)
        }
    }
}

final class HyneShortcutListTests: XCTestCase {
    func testEveryCombinationHasItsOwnID() {
        let list = KnownShortcuts.hyne(.makeDefault())   // close all has ⌘⌃W and ⌘Esc
        XCTAssertEqual(list.count, Set(list.map(\.id)).count)
        XCTAssertEqual(list.filter { $0.title == list[1].title }.count, 2)
    }
}
