import XCTest
@testable import HMLauncherCore

final class MenuVersionStoreTests: XCTestCase {
    func sampleConfig() -> LauncherConfig {
        var c = LauncherConfig.makeDefault()
        c.addEntry(item("Utility", source: .audioEffects), to: c.favoritesID)
        c.addEntry(item("Serum"), to: c.categories[1].id)
        return c
    }

    func testSaveListLoadDelete() throws {
        let store = MenuVersionStore(directory: tempDir())
        let v = try store.save(name: "Vor LES-Import", categories: sampleConfig().categories, isAutomatic: true)
        XCTAssertEqual(v.name, "Vor LES-Import")
        XCTAssertEqual(v.entryCount, 2)
        XCTAssertEqual(v.categoryCount, 3)
        XCTAssertTrue(v.isAutomatic)
        XCTAssertEqual(try store.list().map(\.id), [v.id])
        XCTAssertEqual(try store.load(v.id).categories.flatMap(\.entries).map(\.name), ["Utility", "Serum"])
        try store.delete(v.id)
        XCTAssertTrue(try store.list().isEmpty)
    }

    func testListIsNewestFirst() throws {
        let store = MenuVersionStore(directory: tempDir())
        let a = try store.save(name: "A", categories: [], isAutomatic: false, date: Date(timeIntervalSince1970: 100))
        let b = try store.save(name: "B", categories: [], isAutomatic: false, date: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(try store.list().map(\.id), [b.id, a.id])
    }

    func testAutomaticVersionsArePrunedManualKept() throws {
        let store = MenuVersionStore(directory: tempDir(), maxAutomatic: 3)
        let manual = try store.save(name: "Mine", categories: [], isAutomatic: false, date: Date(timeIntervalSince1970: 1))
        for i in 0..<5 { _ = try store.save(name: "auto \(i)", categories: [], isAutomatic: true, date: Date(timeIntervalSince1970: Double(10 + i))) }
        let list = try store.list()
        XCTAssertEqual(list.filter(\.isAutomatic).map(\.name), ["auto 4", "auto 3", "auto 2"])
        XCTAssertTrue(list.contains { $0.id == manual.id })
    }

    func testExportImportRoundTrip() throws {
        let url = tempDir().appendingPathComponent("Mein Menü.hmlmenu")
        try MenuDocument(name: "Mein Menü", categories: sampleConfig().categories).write(to: url)
        let doc = try MenuDocument.read(from: url)
        XCTAssertEqual(doc.name, "Mein Menü")
        XCTAssertEqual(doc.categories.flatMap(\.entries).map(\.name), ["Utility", "Serum"])
    }

    func testImportRejectsOtherFiles() throws {
        let url = tempDir().appendingPathComponent("x.hmlmenu")
        try "{\"hello\": 1}".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try MenuDocument.read(from: url))
    }

    func testRestoreMenuKeepsShortcutsAndEnsuresFavorites() {
        var c = sampleConfig()
        c.shortcuts.closeAll = []
        c.restoreMenu([Category(name: "Only")])
        XCTAssertEqual(c.categories.map(\.name), ["Favorites", "Only"])
        XCTAssertTrue(c.categories[0].isFavorites)
        XCTAssertEqual(c.shortcuts.closeAll, [])
    }
}
