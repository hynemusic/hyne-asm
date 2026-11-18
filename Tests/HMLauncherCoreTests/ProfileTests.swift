import XCTest
@testable import HMLauncherCore

final class ProfileTests: XCTestCase {
    let serum = item("Serum 2", uri: "s")
    let eq = item("EQ Eight", uri: "eq", source: .audioEffects)

    func testOldConfigGetsOneActiveProfile() throws {
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LauncherConfig.makeDefault())) as! [String: Any]
        old["profiles"] = nil; old["activeProfileID"] = nil
        let c = try JSONDecoder().decode(LauncherConfig.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(c.profiles.count, 1)
        XCTAssertEqual(c.activeProfile.id, c.profiles[0].id)
    }

    func testSwitchingSavesTheCurrentMenuAndLoadsTheOther() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(serum, to: c.favoritesID)
        let mixing = c.addProfile(named: "Mixing", copyingCurrent: false)
        c.switchProfile(to: mixing)
        XCTAssertEqual(c.activeProfile.name, "Mixing")
        XCTAssertTrue(c.categories.first(where: \.isFavorites)!.entries.isEmpty)   // fresh menu with Favorites
        c.addEntry(eq, to: c.favoritesID)
        c.switchProfile(to: c.profiles[0].id)
        XCTAssertEqual(c.categories.first(where: \.isFavorites)!.entries.map(\.name), ["Serum 2"])
        c.switchProfile(to: mixing)
        XCTAssertEqual(c.categories.first(where: \.isFavorites)!.entries.map(\.name), ["EQ Eight"])
    }

    func testCopyGetsNewIDsAndNextCyclesRenameDelete() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(serum, to: c.favoritesID)
        let copy = c.addProfile(named: "Live Show", copyingCurrent: true)
        let copied = c.profiles.first { $0.id == copy }!
        XCTAssertEqual(copied.categories.first?.entries.map(\.name), ["Serum 2"])
        XCTAssertNotEqual(copied.categories.first?.id, c.categories.first?.id)

        let first = c.activeProfile.id
        c.switchToNextProfile()
        XCTAssertEqual(c.activeProfile.id, copy)
        c.switchToNextProfile()
        XCTAssertEqual(c.activeProfile.id, first)

        c.renameProfile(copy, to: "Stage")
        XCTAssertEqual(c.profiles.first { $0.id == copy }?.name, "Stage")
        c.deleteProfile(first)                       // the active one can't be deleted
        XCTAssertEqual(c.profiles.count, 2)
        c.deleteProfile(copy)
        XCTAssertEqual(c.profiles.map(\.id), [first])
        c.deleteProfile(first)                       // nor the last one
        XCTAssertEqual(c.profiles.count, 1)
    }

    func testRoundTrip() throws {
        var c = LauncherConfig.makeDefault()
        let id = c.addProfile(named: "Mixing", copyingCurrent: false)
        let back = try JSONDecoder().decode(LauncherConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.profiles.map(\.name), c.profiles.map(\.name))
        XCTAssertEqual(back.profiles.last?.id, id)
        XCTAssertEqual(back.activeProfile.id, c.activeProfile.id)
    }

    func testNextProfileShortcut() {
        var s = ShortcutSettings.default
        s.nextProfile = [KeyCombo(keyCode: 35, modifiers: [.ctrl, .alt])]
        XCTAssertEqual(ShortcutMatcher(settings: s).match(keyCode: 35, modifiers: [.ctrl, .alt]), .nextProfile)
    }
}
