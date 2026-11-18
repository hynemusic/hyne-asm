import XCTest
@testable import HMLauncherCore

private func fixtureText() throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/menuconfig.ini")
    return try String(contentsOf: url, encoding: .utf8)
}

final class LESMenuParserTests: XCTestCase {
    override func setUp() { Loc.language = .de }

    func testParsesCategoriesAndPairs() {
        let text = """
        ; comment
        /Effects

        Valhalla Room
        ValhallaRoom vst3
        --
        Utility
        Utility
        //RX10
        RX 10 De-ess
        "RX 10 De-ess"
        ..
        EQ EIGHT
        Eight
        /Instruments
        Serum 2
        "Serum 2" vst3
        /nocategory
        Sampler
        Sampler
        Readme
        readme
        ;V DONT REMOVE THIS
        End
        """
        let cats = LESMenuParser.parse(text)
        XCTAssertEqual(cats.map(\.name), ["Effects", "RX10", "Instruments", "Sonstiges"])
        XCTAssertEqual(cats[0].items.map(\.display), ["Valhalla Room", "Utility", "EQ EIGHT"])
        XCTAssertEqual(cats[0].items[0].query, "ValhallaRoom vst3")
        XCTAssertEqual(cats[1].items.map(\.query), ["\"RX 10 De-ess\""])
        XCTAssertEqual(cats[3].items.map(\.display), ["Sampler"])
        XCTAssertEqual(cats.map(\.parent), [nil, 0, nil, nil])
    }

    func testParsesRealLESFile() throws {
        let cats = LESMenuParser.parse(try fixtureText())
        XCTAssertEqual(cats.map(\.name), ["Effects", "RX10", "UAD", "Soundtoys & Brainworx", "Instruments", "EQ", "presets n Racks", "Sonstiges"])
        XCTAssertEqual(cats.first { $0.name == "RX10" }?.items.count, 10)
        XCTAssertEqual(cats.map(\.parent), [nil, 0, 0, 0, nil, 4, nil, nil])
        XCTAssertEqual(cats.first { $0.name == "Instruments" }?.items.first?.display, "AnalogLab")
        XCTAssertEqual(cats.last?.items.map(\.display), ["Sampler", "Drum Rack", "Granulator II"])
        XCTAssertFalse(cats.flatMap(\.items).contains { $0.display == "End" || $0.query == "End" })
    }

    func testWindowsLineEndings() {
        let cats = LESMenuParser.parse("/A\r\nUtility\r\nUtility\r\n")
        XCTAssertEqual(cats.first?.items.first?.query, "Utility")
    }
}

final class LESQueryTests: XCTestCase {
    func testParsesHintsQuotesAndExtensions() {
        XCTAssertEqual(LESQuery("ValhallaRoom vst3"), LESQuery(text: "valhallaroom", format: .vst3, isPreset: false))
        XCTAssertEqual(LESQuery("\"CLA-76 Stereo\" vst3"), LESQuery(text: "cla-76 stereo", format: .vst3, isPreset: false))
        XCTAssertEqual(LESQuery("NS1 (s) au"), LESQuery(text: "ns1 (s)", format: .au, isPreset: false))
        XCTAssertEqual(LESQuery("Visco vst"), LESQuery(text: "visco", format: .vst2, isPreset: false))
        XCTAssertEqual(LESQuery("prophet-5  V vst3"), LESQuery(text: "prophet-5 v", format: .vst3, isPreset: false))
        XCTAssertEqual(LESQuery("Swiss Army Meter.amxd"), LESQuery(text: "swiss army meter", format: .maxForLive, isPreset: false))
        XCTAssertEqual(LESQuery("\"Granulator II\" amxd"), LESQuery(text: "granulator ii", format: .maxForLive, isPreset: false))
        XCTAssertEqual(LESQuery("ott.adv"), LESQuery(text: "ott", format: nil, isPreset: true))
        XCTAssertEqual(LESQuery("Utility"), LESQuery(text: "utility", format: nil, isPreset: false))
    }
}

final class LESMatcherTests: XCTestCase {
    let catalog: [PluginItem] = [
        item("ValhallaRoom", uri: "vr-au", path: ["AUv2", "Valhalla DSP, LLC"]),
        item("ValhallaRoom", uri: "vr-vst", path: ["VST", "Local"]),
        item("ValhallaRoom", uri: "vr-v3", path: ["VST3", "Valhalla DSP, LLC"]),
        item("CLA-76 (s)", uri: "cla-au", path: ["AUv2", "Waves"]),
        item("CLA-76 Stereo", uri: "cla-v3", path: ["VST3", "Waves"]),
        item("NS1 (s)", uri: "ns1-au", path: ["AUv2", "Waves"]),
        item("NS1 Stereo", uri: "ns1-v3", path: ["VST3", "Waves"]),
        item("EQ Eight", uri: "eq8", source: .audioEffects),
        item("Utility", uri: "util", source: .audioEffects),
        item("Limiter", uri: "lim-live", source: .audioEffects),
        item("Limiter", uri: "lim-plugin", path: ["VST3", "Someone"]),
        item("Oxford Inflator", uri: "oxi", path: ["VST3", "Sonnox"]),
        item("UAD Oxford Inflator", uri: "uoxi", path: ["VST3", "Universal Audio"]),
        item("UAD Oxford Limiter", uri: "uoxl", path: ["VST3", "Universal Audio"]),
        item("OTT", uri: "ott-v3", path: ["VST3", "Xfer Records"]),
        item("Swiss Army Meter", uri: "sam", source: .maxForLive, path: ["Max Audio Effect"]),
        item("Kickstart 2", uri: "ks", path: ["VST3", "Nicky Romero"]),
        item("Soothe2", uri: "s2", path: ["VST3", "oeksound"]),
    ]

    private func match(_ display: String, _ query: String) -> LESMatch {
        LESMatcher(items: catalog).match(display: display, query: query)
    }

    func testExactWithFormatHint() {
        XCTAssertEqual(match("Valhalla Room", "ValhallaRoom vst3").item?.uri, "vr-v3")
        XCTAssertEqual(match("NS1", "NS1 (s) au").item?.uri, "ns1-au")
        XCTAssertEqual(match("CLA", "\"CLA-76 Stereo\" vst3").item?.uri, "cla-v3")
        XCTAssertEqual(match("Valhalla Room", "ValhallaRoom vst3").status, .found)
    }

    func testDisplayNameHelpsFuzzyQuery() {
        let m = match("EQ EIGHT", "Eight")
        XCTAssertEqual(m.item?.uri, "eq8")
        XCTAssertEqual(m.status, .found)
    }

    func testNoHintPrefersLiveDevice() {
        XCTAssertEqual(match("Limiter", "Limiter").item?.uri, "lim-live")
    }

    func testPrefixBeatsContains() {
        let m = match("Oxford Inflator", "Oxford vst3")
        XCTAssertEqual(m.item?.uri, "oxi")
        XCTAssertEqual(m.status, .found)
    }

    func testAmbiguousIsUncertainWithAlternatives() {
        let m = match("Ox", "Oxford")
        XCTAssertEqual(m.status, .found) // prefix "Oxford Inflator" is unique best
        let n = match("Inflator", "Inflator")
        XCTAssertEqual(n.status, .uncertain)
        XCTAssertEqual(Set(n.alternatives.map(\.uri)), ["oxi", "uoxi"])
    }

    func testPresetIsNotFoundButSuggestsByDisplayName() {
        let m = match("OTT", "ott.adv")
        XCTAssertEqual(m.status, .uncertain)
        XCTAssertEqual(m.item?.uri, "ott-v3")
        XCTAssertTrue(m.isPreset)
    }

    func testMaxForLiveExtension() {
        XCTAssertEqual(match("Swiss Army Meter", "Swiss Army Meter.amxd").item?.uri, "sam")
    }

    func testUniqueContainedNameIsFound() {
        let m = LESMatcher(items: [item("ValhallaSupermassive", uri: "sm", path: ["VST3", "Valhalla"])]).match(display: "Valhalla Supermassive", query: "Supermassive vst3")
        XCTAssertEqual(m.status, .found)
    }

    func testSpacesAndPunctuationDoNotMatter() {
        let items = [item("UADx Lexicon 224 Digital Reverb", uri: "lex", path: ["VST3", "UA"]), item("Decent Sampler", uri: "ds", path: ["VST3", "Decent"])]
        let matcher = LESMatcher(items: items)
        XCTAssertEqual(matcher.match(display: "Lexicon", query: "UADx Lexicon224 Digital Reverb vst3").item?.uri, "lex")
        XCTAssertEqual(matcher.match(display: "DecentSampler", query: "\"DecentSampler\" vst3").status, .found)
    }

    func testNothingFound() {
        let m = match("WIDE", "\"WIDE THAT SHIT\"")
        XCTAssertEqual(m.status, .notFound)
        XCTAssertNil(m.item)
    }

    func testDifferentButCloseNameIsUncertain() {
        let m = match("Soothe3", "Soothe3")
        XCTAssertNotEqual(m.status, .found)
    }
}

final class ImportDraftTests: XCTestCase {
    override func setUp() { Loc.language = .de }

    let catalog: [PluginItem] = [
        item("Utility", uri: "util", source: .audioEffects),
        item("Fresh Air", uri: "fa", path: ["VST3", "Slate"]),
        item("Kickstart 2", uri: "ks", path: ["VST3", "Nicky Romero"]),
        item("Prophet-5 V", uri: "p5", path: ["VST3", "Arturia"]),
    ]

    let text = """
    /Effects
    Fresh Air
    "Fresh Air"
    Fresh Air
    Fresh Air vst3
    Kickstart
    Kickstart 2 vst3
    WIDE
    "WIDE THAT SHIT"
    //Tools
    Utility
    Utility
    ..
    /Instruments
    PROPHET V5
    prophet-5  V vst3
    """

    func testDraftDedupesMatchedRowsPerCategory() {
        let d = ImportDraft.make(text: text, items: catalog)
        XCTAssertEqual(d.categories.map(\.name), ["Effects", "Tools", "Instruments"])
        XCTAssertEqual(d.categories[0].rows.map(\.display), ["Fresh Air", "Kickstart", "WIDE"])
        XCTAssertEqual(d.counts, ImportDraft.Counts(found: 4, uncertain: 0, notFound: 1))
    }

    func testReplaceKeepsFavoritesAndUsesLESDisplayNames() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(catalog[0], to: c.favoritesID)
        c.addCategory(named: "Old")
        c.apply(ImportDraft.make(text: text, items: catalog), mode: .replace)
        XCTAssertEqual(c.categories.map(\.name), ["Favorites", "Effects", "Instruments"])
        XCTAssertEqual(c.categories[0].entries.map(\.name), ["Utility"])
        let effects = c.categories[1].entries
        XCTAssertEqual(effects.map(\.title), ["Fresh Air", "Kickstart", "Tools"]) // WIDE skipped, //Tools is a folder
        XCTAssertEqual(effects[1].name, "Kickstart 2")
        XCTAssertEqual(effects[1].iconID, "sidechain")
        XCTAssertTrue(effects[2].isFolder)
        XCTAssertEqual(effects[2].children?.map(\.name), ["Utility"])
        XCTAssertEqual(c.categories[2].entries[0].title, "PROPHET V5")
        XCTAssertNil(effects[0].displayName) // same as plugin name → no override
    }

    func testAddMergesSameNamedCategories() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(catalog[0], to: c.categories[2].id) // "Effects" already has Utility
        c.apply(ImportDraft.make(text: text, items: catalog), mode: .add)
        c.apply(ImportDraft.make(text: text, items: catalog), mode: .add) // twice: folder is reused, no duplicates
        XCTAssertEqual(c.categories.map(\.name), ["Favorites", "Instruments", "Effects"])
        XCTAssertEqual(c.categories[2].entries.map(\.name), ["Utility", "Fresh Air", "Kickstart 2", "Tools"])
        XCTAssertEqual(c.categories[2].entries[3].children?.map(\.name), ["Utility"])
        XCTAssertEqual(c.categories[1].entries.map(\.name), ["Prophet-5 V"])
    }

    func testDraftEditing() {
        var d = ImportDraft.make(text: text, items: catalog)
        let effects = d.categories[0].id, tools = d.categories[1].id
        d.removeRow(d.categories[0].rows[2].id, from: effects)
        d.moveRow(in: effects, from: 1, to: 0)
        XCTAssertEqual(d.categories[0].rows.map(\.display), ["Kickstart", "Fresh Air"])
        d.mergeCategory(tools, into: effects)
        XCTAssertEqual(d.categories.map(\.name), ["Effects", "Instruments"])
        XCTAssertEqual(d.categories[0].rows.last?.display, "Utility")
        d.renameCategory(effects, to: "FX")
        XCTAssertEqual(d.categories[0].name, "FX")
        let wideless = d.categories[0].rows[0].id
        d.setMatch(catalog[0], for: wideless, in: effects)
        XCTAssertEqual(d.categories[0].rows[0].match.item?.uri, "util")
        XCTAssertEqual(d.categories[0].rows[0].match.status, .found)
        d.removeCategory(effects)
        XCTAssertEqual(d.categories.map(\.name), ["Instruments"])
    }

    func testSubfolderParentsAndPromotion() {
        var d = ImportDraft.make(text: text, items: catalog)
        let effects = d.categories[0].id, tools = d.categories[1].id
        XCTAssertEqual(d.categories.map(\.parentID), [nil, effects, nil])
        d.setParent(tools, to: nil)
        var c = LauncherConfig.makeDefault()
        c.apply(d, mode: .replace)
        XCTAssertEqual(c.categories.map(\.name), ["Favorites", "Effects", "Tools", "Instruments"])
        d.setParent(tools, to: d.categories[2].id)
        XCTAssertEqual(d.categories[1].parentID, d.categories[2].id)
        d.setParent(effects, to: tools) // a category that is itself a folder's target cannot become a folder… only leaves can
        XCTAssertNil(d.categories[0].parentID)
    }

    func testRemovingParentRemovesItsFolders() {
        var d = ImportDraft.make(text: text, items: catalog)
        d.removeCategory(d.categories[0].id)
        XCTAssertEqual(d.categories.map(\.name), ["Instruments"])
    }

    func testRealFileProducesMostlyMatches() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/menuconfig.ini")
        let d = ImportDraft.make(text: try String(contentsOf: url, encoding: .utf8), items: catalog)
        XCTAssertGreaterThan(d.categories.flatMap(\.rows).count, 100)
    }
}
