import XCTest
@testable import HMLauncherCore

final class EntryKindsTests: XCTestCase {
    let proQ = item("Pro-Q 4", uri: "pq", path: ["VST3", "FabFilter"])
    let proC = item("Pro-C 2", uri: "pc", path: ["VST3", "FabFilter"])
    let proL = item("Pro-L 2", uri: "pl", path: ["VST3", "FabFilter"])

    func testLiveActionTitles() {
        XCTAssertEqual(LiveAction(kind: .setTempo, value: 128).title, Loc.t("Tempo 128", "Tempo 128"))
        XCTAssertEqual(LiveAction(kind: .setTempo, value: 87.5).title, "Tempo 87.5")
        XCTAssertEqual(LiveAction(kind: .setTimeSignature, value: 7, value2: 8).title.hasSuffix("7/8"), true)
        XCTAssertFalse(LiveActionKind.newMidiTrack.takesValue)
        XCTAssertTrue(LiveActionKind.setTempo.takesValue)
    }

    func testChainAndActionEntriesRoundTripAndOldEntriesStillDecode() throws {
        let chain = Entry(chainNamed: "Vocal Basic", steps: [proQ, proC, proL])
        let action = Entry(action: LiveAction(kind: .setTempo, value: 174))
        let data = try JSONEncoder().encode([chain, action])
        let back = try JSONDecoder().decode([Entry].self, from: data)
        XCTAssertEqual(back[0].chain?.map(\.name), ["Pro-Q 4", "Pro-C 2", "Pro-L 2"])
        XCTAssertEqual(back[1].action, LiveAction(kind: .setTempo, value: 174))
        XCTAssertEqual(back[1].title, "Tempo 174")
        XCTAssertFalse(back[0].isFolder)

        let plain = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(Entry(item: proQ)))
        XCTAssertNil(plain.chain)
        XCTAssertNil(plain.action)
    }

    func testPanelRowsCarryChainsAndActions() {
        var c = LauncherConfig.makeDefault()
        c.categories[0].entries = [Entry(chainNamed: "Vocal", steps: [proQ, proC]),
                                   Entry(chainNamed: "Broken", steps: [proQ, item("Gone", uri: "gone")]),
                                   Entry(action: LiveAction(kind: .newMidiTrack))]
        let rows = PanelState(config: c, items: [proQ, proC, proL]).rows
        XCTAssertEqual(rows[0].chain, ["pq", "pc"])
        XCTAssertTrue(rows[0].isAvailable)
        XCTAssertFalse(rows[1].isAvailable)                 // a step is no longer installed
        XCTAssertEqual(rows[2].action, LiveAction(kind: .newMidiTrack))
        XCTAssertTrue(rows[2].isAvailable)
        XCTAssertEqual(rows[0].usageKey, "chain|vocal")
        XCTAssertTrue(rows[2].usageKey.hasPrefix("action|"))
    }

    func testQuickSearchFindsChainsAndActions() {
        var c = LauncherConfig.makeDefault()
        c.categories[0].entries = [Entry(chainNamed: "Vocal Basic", steps: [proQ]), Entry(action: LiveAction(kind: .setTempo, value: 128))]
        let names = QuickSearch(config: c, items: [proQ], usage: [:]).results("tempo").map(\.row.title)
        XCTAssertEqual(names.first, "Tempo 128")
        XCTAssertEqual(QuickSearch(config: c, items: [proQ], usage: [:]).results("vocal b").first?.row.chain, ["pq"])
    }

    func testInsertOptionsDefaultAndOldConfigs() throws {
        XCTAssertEqual(LauncherConfig.makeDefault().insert, InsertOptions(position: .end, allSelectedTracks: true))
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LauncherConfig.makeDefault())) as! [String: Any]
        old["insert"] = nil
        let decoded = try JSONDecoder().decode(LauncherConfig.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(decoded.insert, .default)
    }

    func testUsageKindForChainsAndActions() {
        XCTAssertEqual(UsageKind(key: "chain|vocal"), .custom)
        XCTAssertEqual(UsageKind(key: "action|tempo 128"), .custom)
    }
}

final class EntryKindsEditingTests: XCTestCase {
    let proQ = item("Pro-Q 4", uri: "pq", path: ["VST3", "FabFilter"])

    func testAddChainAndActionsWithDifferentValues() {
        var c = LauncherConfig.makeDefault()
        let fx = c.categories[2].id
        let chainID = c.addChain(named: "Vocal", steps: [proQ], to: fx)
        c.addAction(LiveAction(kind: .setTempo, value: 128), to: fx)
        c.addAction(LiveAction(kind: .setTempo, value: 174), to: fx)
        c.addAction(LiveAction(kind: .setTempo, value: 128), to: fx)   // same one twice: ignored
        let entries = c.categories[2].entries
        XCTAssertEqual(entries.map(\.title), ["Vocal", "Tempo 128", "Tempo 174"])
        XCTAssertEqual(entries[0].id, chainID)
    }

    func testUpdateChain() {
        var c = LauncherConfig.makeDefault()
        let fx = c.categories[2].id
        let id = c.addChain(named: "Vocal", steps: [proQ], to: fx)
        c.updateChain(id, in: fx, name: "Vocal 2", steps: [proQ, proQ])
        XCTAssertEqual(c.categories[2].entries[0].title, "Vocal 2")
        XCTAssertEqual(c.categories[2].entries[0].chain?.count, 2)
    }

    func testChangingAnActionsValueRenamesItUnlessRenamedByHand() throws {
        var c = LauncherConfig.makeDefault()
        let fav = c.favoritesID
        c.addAction(LiveAction(kind: .setTempo, value: 120), to: fav)
        let id = try XCTUnwrap(c.categories[0].entries.last?.id)
        c.updateAction(id, in: fav, to: LiveAction(kind: .setTempo, value: 128))
        var e = try XCTUnwrap(c.categories[0].entries.last)
        XCTAssertEqual(e.action?.value, 128)
        XCTAssertEqual(e.title, LiveAction(kind: .setTempo, value: 128).title)

        c.setDisplayName("Fast", entry: id, in: fav)
        c.updateAction(id, in: fav, to: LiveAction(kind: .setTempo, value: 174))
        e = try XCTUnwrap(c.categories[0].entries.last)
        XCTAssertEqual(e.action?.value, 174)
        XCTAssertEqual(e.title, "Fast")
    }
}
