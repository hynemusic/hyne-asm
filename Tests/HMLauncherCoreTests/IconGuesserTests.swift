import XCTest
@testable import HMLauncherCore

final class IconGuesserTests: XCTestCase {
    private func guess(_ name: String, _ source: ItemSource = .plugins) -> String {
        IconGuesser.guess(item(name, source: source))
    }

    func testPluginNames() {
        XCTAssertEqual(guess("Kickstart 2"), "drums")
        XCTAssertEqual(guess("Pro-L 2"), "limiter")
        XCTAssertEqual(guess("FabFilter Pro-Q 3"), "eq")
        XCTAssertEqual(guess("FabFilter Pro-C 2"), "compressor")
        XCTAssertEqual(guess("CLA-76"), "compressor")
        XCTAssertEqual(guess("OTT"), "compressor")
        XCTAssertEqual(guess("L2 Ultramaximizer"), "limiter")
        XCTAssertEqual(guess("ValhallaVintageVerb"), "reverb")
        XCTAssertEqual(guess("EchoBoy"), "delay")
        XCTAssertEqual(guess("Decapitator"), "saturation")
        XCTAssertEqual(guess("Serum"), "synth")
        XCTAssertEqual(guess("ANA 2"), "synth")
        XCTAssertEqual(guess("Kontakt 7"), "sampler")
        XCTAssertEqual(guess("Auto-Tune Pro"), "pitch")
        XCTAssertEqual(guess("Ozone Imager"), "stereo")
    }

    func testLiveDevices() {
        XCTAssertEqual(guess("EQ Eight", .audioEffects), "eq")
        XCTAssertEqual(guess("Glue Compressor", .audioEffects), "compressor")
        XCTAssertEqual(guess("Multiband Dynamics", .audioEffects), "compressor")
        XCTAssertEqual(guess("Limiter", .audioEffects), "limiter")
        XCTAssertEqual(guess("Saturator", .audioEffects), "saturation")
        XCTAssertEqual(guess("Utility", .audioEffects), "utility")
        XCTAssertEqual(guess("Hybrid Reverb", .audioEffects), "reverb")
        XCTAssertEqual(guess("Auto Filter", .audioEffects), "filter")
        XCTAssertEqual(guess("Drum Rack", .instruments), "drums")
        XCTAssertEqual(guess("Simpler", .instruments), "sampler")
        XCTAssertEqual(guess("Arpeggiator", .midiEffects), "arp")
    }

    func testFallbacksBySource() {
        XCTAssertEqual(guess("Drift", .instruments), "synth")
        XCTAssertEqual(guess("Zzyzx", .instruments), "synth")
        XCTAssertEqual(guess("Zzyzx", .midiEffects), "midi")
        XCTAssertEqual(guess("Zzyzx", .audioEffects), IconCatalog.defaultID)
        XCTAssertEqual(guess("Zzyzx"), IconCatalog.defaultID)
    }

    func testShortKeywordsNeedWholeWords() {
        XCTAssertEqual(guess("Sequencer Thing"), IconCatalog.defaultID) // "eq" inside a word is no EQ
    }

    func testEveryGuessIsAKnownIcon() {
        let ids = Set(IconCatalog.all.map(\.id))
        for id in IconGuesser.ruleIconIDs { XCTAssertTrue(ids.contains(id), id) }
    }
}

final class IconSyncTests: XCTestCase {
    let prol = item("Pro-L 2", uri: "u:v3", path: ["VST3", "FabFilter"])
    let prolAU = item("Pro-L 2", uri: "u:au", path: ["AUv2", "FabFilter"])

    func testAddEntryGuessesIcon() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(item("Kickstart 2"), to: c.favoritesID)
        XCTAssertEqual(c.categories[0].entries[0].iconID, "drums")
    }

    func testAddEntryReusesIconChosenElsewhere() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(prol, to: c.favoritesID)
        c.setIcon("star", entry: c.categories[0].entries[0].id, in: c.favoritesID)
        c.addEntry(prolAU, to: c.categories[2].id)
        XCTAssertEqual(c.categories[2].entries[0].iconID, "star")
    }

    func testSetIconSyncsSamePluginAcrossCategoriesOnly() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(prol, to: c.favoritesID)
        c.addEntry(prol, to: c.categories[2].id)
        c.addEntry(item("Utility", source: .audioEffects), to: c.categories[2].id)
        c.setIcon("heart", entry: c.categories[0].entries[0].id, in: c.favoritesID)
        XCTAssertEqual(c.categories[2].entries[0].iconID, "heart")
        XCTAssertEqual(c.categories[2].entries[1].iconID, "utility")
    }

    func testMigrationGuessesOnlyGenericIcons() throws {
        let url = tempDir().appendingPathComponent("config.json")
        var old = LauncherConfig.makeDefault()
        old.version = 2
        old.addEntry(item("Glue Compressor", source: .audioEffects), to: old.favoritesID)
        old.addEntry(item("EQ Eight", source: .audioEffects), to: old.favoritesID)
        old.categories[0].entries[0].iconID = IconCatalog.defaultID
        old.categories[0].entries[1].iconID = "heart"
        try ConfigStore(url: url).save(old)
        let loaded = ConfigStore(url: url).load()
        XCTAssertEqual(loaded.version, 3)
        XCTAssertEqual(loaded.categories[0].entries.map(\.iconID), ["compressor", "heart"])
    }
}
