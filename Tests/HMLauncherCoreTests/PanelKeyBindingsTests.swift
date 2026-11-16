import XCTest
@testable import HMLauncherCore

final class PanelKeyBindingsTests: XCTestCase {
    func testDefaultBindings() {
        let b = PanelKeyBindings.default
        XCTAssertEqual(b.key(for: KeyCombo(keyCode: 123, modifiers: [])), .left)
        XCTAssertEqual(b.key(for: KeyCombo(keyCode: 124, modifiers: [])), .right)
        XCTAssertEqual(b.key(for: KeyCombo(keyCode: 48, modifiers: [])), .right)
        XCTAssertEqual(b.key(for: KeyCombo(keyCode: 126, modifiers: [])), .up)
        XCTAssertEqual(b.key(for: KeyCombo(keyCode: 125, modifiers: [])), .down)
        XCTAssertEqual(b.key(for: KeyCombo(keyCode: 36, modifiers: [])), .returnKey)
        XCTAssertEqual(b.key(for: KeyCombo(keyCode: 76, modifiers: [])), .returnKey)
        XCTAssertEqual(b.key(for: KeyCombo(keyCode: 53, modifiers: [])), .escape)
        XCTAssertNil(b.key(for: KeyCombo(keyCode: 123, modifiers: [.shift])))
        XCTAssertNil(b.key(for: KeyCombo(keyCode: 0, modifiers: [])))
    }

    func testCustomBindingReplacesDefault() {
        var b = PanelKeyBindings.default
        b[.close] = [KeyCombo(keyCode: 12, modifiers: [.ctrl])]
        XCTAssertEqual(b.key(for: KeyCombo(keyCode: 12, modifiers: [.ctrl])), .escape)
        XCTAssertNil(b.key(for: KeyCombo(keyCode: 53, modifiers: [])))
    }

    func testEveryActionHasLabelAndDefault() {
        for action in PanelKeyAction.allCases {
            XCTAssertFalse(action.label.isEmpty)
            XCTAssertFalse(PanelKeyBindings.default[action].isEmpty, "\(action)")
        }
    }

    func testOldConfigWithoutPanelKeysDecodesWithDefaults() throws {
        var c = LauncherConfig.makeDefault()
        c.addEntry(item("EQ Eight"), to: c.favoritesID)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as! [String: Any]
        json.removeValue(forKey: "panelKeys")
        let decoded = try JSONDecoder().decode(LauncherConfig.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.panelKeys, .default)
        XCTAssertEqual(decoded.categories[0].entries.count, 1)
    }

    func testPanelKeysRoundTrip() throws {
        var c = LauncherConfig.makeDefault()
        c.panelKeys[.down] = [KeyCombo(keyCode: 38, modifiers: [])]
        let decoded = try JSONDecoder().decode(LauncherConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(decoded.panelKeys[.down], [KeyCombo(keyCode: 38, modifiers: [])])
    }
}
