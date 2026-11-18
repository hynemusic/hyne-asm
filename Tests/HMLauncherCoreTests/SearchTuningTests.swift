import XCTest
@testable import HMLauncherCore

final class SearchTuningTests: XCTestCase {
    let serum = item("Serum 2", uri: "serum", path: ["VST3", "Xfer Records"])
    let serato = item("Serato Sample", uri: "serato", path: ["VST3", "Serato"])
    let sermon = item("Sermon Delay", uri: "sermon", path: ["VST3", "X"])
    let valhalla = item("ValhallaRoom", uri: "vroom", path: ["VST3", "Valhalla DSP"])
    var items: [PluginItem] { [serum, serato, sermon, valhalla] }
    var keys: PluginVariants.Keys { PluginVariants.Keys(items) }

    func testRuleLookupUsesLongestPrefix() {
        let rules = [SearchRule(query: "se"), SearchRule(query: "Ser ")]
        XCTAssertEqual(SearchTuning.rule(for: "serum", in: rules)?.query, "ser")
        XCTAssertEqual(SearchTuning.rule(for: "sa", in: rules)?.query, nil)
        XCTAssertNil(SearchTuning.rule(for: "  ", in: rules))
    }

    func testApplyPinsHidesAndInjects() {
        let rule = SearchRule(query: "x", pinned: ["c", "z", "a"], hidden: ["b"])
        let out = SearchTuning.apply(["a", "b", "c", "d"], key: { $0 }, rule: rule) { $0 == "z" ? "z" : nil }
        XCTAssertEqual(out, ["c", "z", "a", "d"])
    }

    func testQuickSearchFollowsRules() {
        var c = LauncherConfig.makeDefault()
        let base = QuickSearch(config: c, items: items, usage: [:]).results("ser").map(\.row.title)
        XCTAssertEqual(Set(base), ["Serum 2", "Serato Sample", "Sermon Delay"])

        c.pinSearchResult(keys.key(sermon), for: "ser")
        c.hideSearchResult(keys.key(serato), for: "ser")
        let shaped = QuickSearch(config: c, items: items, usage: [:]).results("seR").map(\.row.title)
        XCTAssertEqual(shaped, ["Sermon Delay", "Serum 2"])
        // Longer searches keep the rule while the result still matches …
        XCTAssertEqual(QuickSearch(config: c, items: items, usage: [:]).results("serm").map(\.row.title), ["Sermon Delay"])

        // … and a pinned plugin shows up even when its name doesn't match.
        c.pinSearchResult(keys.key(valhalla), for: "verb")
        XCTAssertEqual(QuickSearch(config: c, items: items, usage: [:]).results("verb").first?.row.title, "ValhallaRoom")
    }

    func testPanelFollowsRules() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(serum, to: c.favoritesID)
        c.pinSearchResult(keys.key(sermon), for: "ser")
        c.hideSearchResult(keys.key(serum), for: "ser")
        var p = PanelState(config: c, items: items)
        for ch in "ser" { _ = p.handle(.character(ch)) }
        // Serum is hidden even though it is in Favorites; the pinned one leads the "all plugins" part.
        XCTAssertEqual(p.rows.map(\.title), ["Sermon Delay", "Serato Sample"])
        XCTAssertTrue(p.rows.allSatisfy(\.isGlobal))
    }

    func testEditingCreatesMovesAndDropsRules() {
        var c = LauncherConfig.makeDefault()
        c.pinSearchResult("a", for: "Ser")
        c.pinSearchResult("b", for: "ser")
        c.movePinnedSearchResult("b", by: -1, for: "ser")
        XCTAssertEqual(c.searchRule(exactly: "ser")?.pinned, ["b", "a"])
        c.hideSearchResult("a", for: "ser")       // hiding unpins
        XCTAssertEqual(c.searchRule(exactly: "ser")?.pinned, ["b"])
        XCTAssertEqual(c.searchRule(exactly: "ser")?.hidden, ["a"])
        c.unhideSearchResult("a", for: "ser")
        c.unpinSearchResult("b", for: "ser")
        XCTAssertTrue(c.searchRules.isEmpty)      // empty rules disappear
    }

    func testLongerSearchInheritsShorterRule() {
        var c = LauncherConfig.makeDefault()
        c.pinSearchResult("a", for: "ser")
        c.hideSearchResult("h", for: "ser")
        c.pinSearchResult("b", for: "serum")
        XCTAssertEqual(c.searchRule(exactly: "serum")?.pinned, ["a", "b"])
        XCTAssertEqual(c.searchRule(exactly: "serum")?.hidden, ["h"])
        XCTAssertEqual(c.searchRule(exactly: "ser")?.pinned, ["a"])
    }

    func testConfigRoundTripAndOldFiles() throws {
        var c = LauncherConfig.makeDefault()
        c.pinSearchResult("plugins|serum 2", for: "ser")
        c.setItemShortcut(KeyCombo(keyCode: 1, modifiers: [.ctrl, .alt]), for: serum)
        let back = try JSONDecoder().decode(LauncherConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.searchRules, c.searchRules)
        XCTAssertEqual(back.itemShortcuts, c.itemShortcuts)
        XCTAssertEqual(back.theme, .original)
        var themed = c; themed.theme = .retro
        XCTAssertEqual(try JSONDecoder().decode(LauncherConfig.self, from: JSONEncoder().encode(themed)).theme, .retro)

        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LauncherConfig.makeDefault())) as! [String: Any]
        old["searchRules"] = nil; old["itemShortcuts"] = nil
        let decoded = try JSONDecoder().decode(LauncherConfig.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertTrue(decoded.searchRules.isEmpty && decoded.itemShortcuts.isEmpty)
        XCTAssertEqual(decoded.theme, .original)
    }
}

final class ItemShortcutTests: XCTestCase {
    let serum = item("Serum 2", uri: "serum", path: ["VST3", "Xfer Records"])
    let eq = item("EQ Eight", uri: "eq8", source: .audioEffects)
    let ctrlAltS = KeyCombo(keyCode: 1, modifiers: [.ctrl, .alt])

    func testAssignReplaceRemoveAndMatch() {
        var c = LauncherConfig.makeDefault()
        c.setItemShortcut(ctrlAltS, for: serum)
        c.setItemShortcut(KeyCombo(keyCode: 2, modifiers: [.ctrl, .alt]), for: serum) // one per item
        XCTAssertEqual(c.itemShortcuts.count, 1)
        XCTAssertEqual(c.itemShortcut(for: serum)?.combo.keyCode, 2)
        XCTAssertEqual(ShortcutMatcher.itemShortcut(keyCode: 2, modifiers: [.ctrl, .alt], in: c.itemShortcuts)?.uri, "serum")
        XCTAssertNil(ShortcutMatcher.itemShortcut(keyCode: 2, modifiers: [.ctrl], in: c.itemShortcuts))
        c.setItemShortcut(nil, for: serum)
        XCTAssertTrue(c.itemShortcuts.isEmpty)
    }

    func testOwnerReportsConflicts() {
        var c = LauncherConfig.makeDefault()
        XCTAssertNotNil(c.shortcutOwner(of: KeyCombo(keyCode: 13, modifiers: [.cmd])))   // ⌘W: close focused
        c.setItemShortcut(ctrlAltS, for: serum)
        XCTAssertEqual(c.shortcutOwner(of: ctrlAltS), "Serum 2")
        XCTAssertNil(c.shortcutOwner(of: ctrlAltS, ignoring: c.itemShortcuts[0].id))
        XCTAssertNil(c.shortcutOwner(of: KeyCombo(keyCode: 3, modifiers: [.ctrl, .alt])))
    }

    func testUsageRemove() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = UsageStore(url: url)
        store.replaceAll(["plugins|a": 2, "plugins|b": 1])
        store.remove("plugins|a")
        XCTAssertEqual(UsageStore(url: url).counts, ["plugins|b": 1])
        try? FileManager.default.removeItem(at: url)
    }
}
