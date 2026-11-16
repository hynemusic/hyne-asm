import XCTest
@testable import HMLauncherCore

final class SearchMatcherTests: XCTestCase {
    func testLooseSpellingsFindProQ4() {
        for q in ["pro-q 4", "pro q 4", "proq4", "pro 4", "pro-q", "PRO Q", "q 4"] {
            XCTAssertNotNil(SearchMatcher.score("Pro-Q 4", q), q)
        }
    }

    func testAllWordsMustBePresent() {
        XCTAssertNil(SearchMatcher.score("Pro-L 2", "pro 4"))
        XCTAssertNil(SearchMatcher.score("Pro-Q 3", "pro q 4"))
        XCTAssertNil(SearchMatcher.score("Serum", "pro"))
    }

    func testBetterMatchesScoreHigher() {
        let prefix = SearchMatcher.score("Pro-Q 4", "pro-q")!
        let words = SearchMatcher.score("FabFilter Pro-Q 4", "pro q 4")!
        let inside = SearchMatcher.score("UAD Pro Channel 4", "pro 4")!
        XCTAssertGreaterThan(prefix, words)
        XCTAssertGreaterThanOrEqual(words, inside)
        XCTAssertGreaterThan(SearchMatcher.score("EQ Eight", "eq")!, SearchMatcher.score("Channel EQ", "eq")!)
    }

    func testWordPrefixesMatchButNotRandomLetters() {
        XCTAssertNotNil(SearchMatcher.score("ValhallaVintageVerb", "valhalla vin"))
        XCTAssertNotNil(SearchMatcher.score("Glue Compressor", "glu comp"))
        XCTAssertNil(SearchMatcher.score("Glue Compressor", "xyz"))
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertNotNil(SearchMatcher.score("Anything", ""))
        XCTAssertNotNil(SearchMatcher.score("Anything", "  "))
    }
}

final class UsageRankingTests: XCTestCase {
    let proQ4 = item("Pro-Q 4", uri: "pq4", path: ["VST3", "FabFilter"])
    let proQ3 = item("Pro-Q 3", uri: "pq3", path: ["VST3", "FabFilter"])
    let proL = item("Pro-L 2", uri: "pl2", path: ["VST3", "FabFilter"])
    let proC = item("Pro-C 2", uri: "pc2", path: ["VST3", "FabFilter"])

    private func type(_ s: inout PanelState, _ text: String) { for ch in text { _ = s.handle(.character(ch)) } }

    func testSmartFilterInPanel() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(proQ4, to: c.favoritesID)
        var s = PanelState(config: c, items: [proQ4, proQ3, proL])
        type(&s, "pro q 4")
        XCTAssertEqual(s.rows.map(\.uri), ["pq4"])
    }

    func testUsageBreaksTiesInSearch() {
        let keys = PluginVariants.Keys([proQ3, proL, proC])
        var s = PanelState(config: .makeDefault(), items: [proQ3, proL, proC], usage: [keys.key(proC): 5, keys.key(proL): 2])
        type(&s, "pro")
        XCTAssertEqual(s.rows.map(\.uri), ["pc2", "pl2", "pq3"])
        XCTAssertEqual(s.handle(.returnKey), .insert(s.rows[0]))
    }

    func testMatchQualityBeatsUsage() {
        let keys = PluginVariants.Keys([proQ3, proL])
        var s = PanelState(config: .makeDefault(), items: [proQ3, proL], usage: [keys.key(proQ3): 50])
        type(&s, "pro-l")
        XCTAssertEqual(s.rows.first?.uri, "pl2")
    }

    func testCategoryOrderUntouchedWithoutSearch() {
        var c = LauncherConfig.makeDefault()
        for i in [proQ3, proL, proC] { c.addEntry(i, to: c.favoritesID) }
        let keys = PluginVariants.Keys([proQ3, proL, proC])
        let s = PanelState(config: c, items: [proQ3, proL, proC], usage: [keys.key(proC): 9])
        XCTAssertEqual(s.rows.map(\.uri), ["pq3", "pl2", "pc2"])
    }

    func testRowsCarryUsageKeySharedAcrossFormats() {
        let au = item("Pro-Q 4", uri: "pq4-au", path: ["AUv2", "FabFilter"])
        var c = LauncherConfig.makeDefault()
        c.addEntry(au, to: c.favoritesID)
        let s = PanelState(config: c, items: [proQ4, au])
        XCTAssertEqual(s.rows[0].usageKey, PluginVariants.Keys([proQ4, au]).key(proQ4))
    }
}

final class UsageStoreTests: XCTestCase {
    func testRecordPersistAndLoad() throws {
        let url = tempDir().appendingPathComponent("usage.json")
        let store = UsageStore(url: url)
        store.record("plugins|pro-q 4")
        store.record("plugins|pro-q 4")
        store.record("plugins|serum")
        XCTAssertEqual(store.counts["plugins|pro-q 4"], 2)
        XCTAssertEqual(UsageStore(url: url).counts, ["plugins|pro-q 4": 2, "plugins|serum": 1])
    }

    func testMissingOrBrokenFileStartsEmpty() throws {
        let url = tempDir().appendingPathComponent("usage.json")
        XCTAssertEqual(UsageStore(url: url).counts, [:])
        try "nope".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(UsageStore(url: url).counts, [:])
    }
}
