import XCTest
@testable import HMLauncherCore

final class SeenStoreTests: XCTestCase {
    let a = item("Alpha", uri: "a"), b = item("Beta", uri: "b"), c = item("Gamma", uri: "c")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func store() -> SeenStore {
        SeenStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
    }

    func testFirstRunMarksEverythingKnownLaterItemsAreNew() {
        let s = store()
        s.update(with: [a, b], now: now)
        XCTAssertTrue(NewItems.uris(items: [a, b], seen: s, config: .makeDefault(), usage: [:], now: now).isEmpty)
        s.update(with: [a, b, c], now: now)
        XCTAssertEqual(NewItems.uris(items: [a, b, c], seen: s, config: .makeDefault(), usage: [:], now: now), ["c"])
        // persisted
        let reread = SeenStore(url: s.url)
        XCTAssertEqual(NewItems.uris(items: [a, b, c], seen: reread, config: .makeDefault(), usage: [:], now: now), ["c"])
    }

    func testNewEndsAfter14DaysOrWhenFiledOrInserted() {
        let s = store()
        s.update(with: [a], now: now)
        s.update(with: [a, c], now: now)
        let later = now.addingTimeInterval(15 * 86_400)
        XCTAssertTrue(NewItems.uris(items: [a, c], seen: s, config: .makeDefault(), usage: [:], now: later).isEmpty)

        var filed = LauncherConfig.makeDefault()
        filed.addEntry(c, to: filed.favoritesID)
        XCTAssertTrue(NewItems.uris(items: [a, c], seen: s, config: filed, usage: [:], now: now).isEmpty)

        let key = PluginVariants.Keys([a, c]).key(c)
        XCTAssertTrue(NewItems.uris(items: [a, c], seen: s, config: .makeDefault(), usage: [key: 1], now: now).isEmpty)
    }

    func testSearchIndexMarksNewRows() {
        let index = SearchIndex(items: [a, c], config: .makeDefault(), newURIs: ["c"])
        XCTAssertEqual(index.globalRows.filter(\.isNew).map(\.title), ["Gamma"])
    }
}

final class RarelyUsedTests: XCTestCase {
    let proQ = item("Pro-Q 4", uri: "pq", path: ["VST3", "FabFilter"])
    let proC = item("Pro-C 2", uri: "pc", path: ["VST3", "FabFilter"])
    let proL = item("Pro-L 2", uri: "pl", path: ["VST3", "FabFilter"])

    func testListsEntriesInsertedAtMostOnceIncludingFolderChildrenExceptKept() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(proQ, to: c.favoritesID)
        let fx = c.categories[2].id
        let folder = c.addFolder(named: "Dyn", to: fx)
        c.addEntry(proC, to: fx, folder: folder)
        c.addEntry(proL, to: fx)
        let keys = PluginVariants.Keys([proQ, proC, proL])
        let usage = [keys.key(proQ): 9, keys.key(proC): 1]
        let index = SearchIndex(items: [proQ, proC, proL], config: c)

        var rare = RarelyUsed.entries(config: c, index: index, usage: usage)
        XCTAssertEqual(rare.map(\.entry.name), ["Pro-L 2", "Pro-C 2"])   // 0 before 1
        XCTAssertEqual(rare.map(\.count), [0, 1])
        XCTAssertEqual(rare[1].place, "Effects / Dyn")

        c.keepEntry(rare[0].entry.id)
        rare = RarelyUsed.entries(config: c, index: index, usage: usage)
        XCTAssertEqual(rare.map(\.entry.name), ["Pro-C 2"])
    }

    func testRemovingFromAFolder() {
        var c = LauncherConfig.makeDefault()
        let fx = c.categories[2].id
        let folder = c.addFolder(named: "Dyn", to: fx)
        c.addEntry(proC, to: fx, folder: folder)
        let id = c.categories[2].entries[0].children![0].id
        c.removeEntry(id, from: fx)
        XCTAssertEqual(c.categories[2].entries[0].children?.count, 0)
    }

    func testSettingDefaultsAndOldConfigs() throws {
        XCTAssertTrue(LauncherConfig.makeDefault().showRarelyUsed)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LauncherConfig.makeDefault())) as! [String: Any]
        old["showRarelyUsed"] = nil; old["keptEntries"] = nil
        let decoded = try JSONDecoder().decode(LauncherConfig.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertTrue(decoded.showRarelyUsed)
        XCTAssertTrue(decoded.keptEntries.isEmpty)
    }
}
