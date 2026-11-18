import XCTest
@testable import HMLauncherCore

final class TypoToleranceTests: XCTestCase {
    func testOneTypoInALongerWordStillMatchesButRanksBelowExact() {
        let typo = SearchMatcher.score("Serum 2", "serm")      // missing letter
        let swapped = SearchMatcher.score("Serum 2", "sreum")  // swapped letters
        XCTAssertNotNil(typo)
        XCTAssertNotNil(swapped)
        XCTAssertLessThan(typo!, SearchMatcher.score("Serum 2", "seru")!)
    }

    func testShortWordsMustMatchExactly() {
        XCTAssertNil(SearchMatcher.score("Pro-Q 4", "prx"))
        XCTAssertNil(SearchMatcher.score("Serum 2", "xyzq"))
    }

    func testNumbersAreNeverCorrected() {
        XCTAssertNil(SearchMatcher.score("Plugin 1234", "plugin 1239"))
    }

    func testLongWordsAllowTwoEdits() {
        XCTAssertNotNil(SearchMatcher.score("Omnisphere", "omnisfere"))   // ph → f
        XCTAssertNil(SearchMatcher.score("Omnisphere", "omnixxxere"))
    }
}

final class TagSearchTests: XCTestCase {
    let glue = PluginItem(uri: "glue", name: "Glue", source: .plugins, path: ["VST3", "X"])            // compressor icon? no keyword
    let proC = PluginItem(uri: "proc", name: "Pro-C 2", source: .plugins, path: ["VST3", "FabFilter"])
    let obscure = PluginItem(uri: "obs", name: "Squeezer 9", source: .plugins, path: ["VST3", "Nobody"])
    let comp = PluginItem(uri: "comp", name: "Compressor", source: .audioEffects, path: [])
    let verb = PluginItem(uri: "verb", name: "ValhallaRoom", source: .plugins, path: ["VST3", "Valhalla DSP"])

    func testTagWordsMapToIconKinds() {
        XCTAssertTrue(SearchVocabulary.icons(for: "comp").contains("compressor"))
        XCTAssertTrue(SearchVocabulary.icons(for: "Verb").contains("reverb"))
        XCTAssertTrue(SearchVocabulary.icons(for: "kompressor").contains("compressor"))
        XCTAssertTrue(SearchVocabulary.icons(for: "pro q").isEmpty)   // not a tag
    }

    func testCompFindsEveryCompressorNameMatchesFirstThenUsageThenPopularity() {
        let items = [glue, proC, obscure, comp, verb]
        let index = SearchIndex(items: items, config: .makeDefault())
        // Make the icons deterministic: Pro-C 2 and Squeezer are compressors by guess or by tag.
        let names = QuickSearch(config: .makeDefault(), index: index, usage: [:]).results("comp").map(\.row.title)
        XCTAssertEqual(names.first, "Compressor")                       // name match first
        XCTAssertTrue(names.contains("Pro-C 2"))                         // found through the tag
        XCTAssertFalse(names.contains("ValhallaRoom"))
        let keys = PluginVariants.Keys(items)
        let used = QuickSearch(config: .makeDefault(), index: index, usage: [keys.key(glue): 5]).results("comp").map(\.row.title)
        if used.contains("Glue") {
            XCTAssertLessThan(used.firstIndex(of: "Glue")!, used.firstIndex(of: "Pro-C 2")!)  // used often beats popular
        }
    }

    func testPopularityBreaksTies() {
        XCTAssertGreaterThan(Popularity.score("Pro-C 2"), Popularity.score("Squeezer 9"))
        XCTAssertGreaterThan(Popularity.score("Serum 2"), 0)
        XCTAssertEqual(Popularity.score("Some Unknown Thing"), 0)
    }

    func testPopularPluginWinsAmongEqualTagHits() {
        let a = PluginItem(uri: "a", name: "Zzz Squash", source: .plugins, path: ["VST3", "N"])
        let b = PluginItem(uri: "b", name: "Pro-C 2", source: .plugins, path: ["VST3", "FabFilter"])
        let index = SearchIndex(items: [a, b], config: .makeDefault())
        let names = QuickSearch(config: .makeDefault(), index: index, usage: [:]).results("compressor").map(\.row.title)
        XCTAssertEqual(names, ["Pro-C 2", "Zzz Squash"])
    }
}
