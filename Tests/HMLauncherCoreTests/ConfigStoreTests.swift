import XCTest
@testable import HMLauncherCore

final class ConfigStoreTests: XCTestCase {
    func testRoundTripSaveLoad() throws {
        let url = tempDir().appendingPathComponent("config.json")
        var c = LauncherConfig.makeDefault()
        c.addEntry(item("Pro-L 2"), to: c.favoritesID)
        try ConfigStore(url: url).save(c)
        let loaded = ConfigStore(url: url).load()
        XCTAssertEqual(loaded.categories.map(\.id), c.categories.map(\.id))
        XCTAssertEqual(loaded.categories[0].entries, c.categories[0].entries)
    }

    func testMissingConfigReturnsDefault() {
        let url = tempDir().appendingPathComponent("config.json")
        XCTAssertEqual(ConfigStore(url: url).load().categories.map(\.name), ["Favorites", "Instruments", "Effects"])
    }

    func testCorruptConfigIsBackedUpAndDefaultReturned() throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("config.json")
        try "{not json".write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(url: url).load()
        XCTAssertEqual(loaded.categories.count, 3)
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("config.corrupt-") && $0.hasSuffix(".json") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(backups[0]), encoding: .utf8), "{not json")
    }

    func testVersion1ConfigMigratesCloseAllToCmdCtrlW() throws {
        let url = tempDir().appendingPathComponent("config.json")
        var old = LauncherConfig.makeDefault()
        old.version = 1
        old.shortcuts.closeAll = [KeyCombo(keyCode: 13, modifiers: [.cmd, .alt]), KeyCombo(keyCode: 53, modifiers: [.cmd])]
        try ConfigStore(url: url).save(old)
        let loaded = ConfigStore(url: url).load()
        XCTAssertEqual(loaded.version, 2)
        XCTAssertEqual(loaded.shortcuts.closeAll, [KeyCombo(keyCode: 13, modifiers: [.cmd, .ctrl]), KeyCombo(keyCode: 53, modifiers: [.cmd])])
    }

    func testVersion2ConfigKeepsUserShortcuts() throws {
        let url = tempDir().appendingPathComponent("config.json")
        var c = LauncherConfig.makeDefault()
        c.shortcuts.closeAll = [KeyCombo(keyCode: 13, modifiers: [.cmd, .alt])]
        try ConfigStore(url: url).save(c)
        XCTAssertEqual(ConfigStore(url: url).load().shortcuts.closeAll, [KeyCombo(keyCode: 13, modifiers: [.cmd, .alt])])
    }

    func testSaveCreatesMissingDirectory() throws {
        let url = tempDir().appendingPathComponent("sub/config.json")
        try ConfigStore(url: url).save(.makeDefault())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
