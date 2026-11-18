import XCTest
@testable import HMLauncherCore

final class PresetTests: XCTestCase {
    let glue = PluginItem(uri: "u:glue", name: "My Glue", source: .userLibrary, path: ["Presets", "Audio Effects", "Audio Effect Rack"], format: "adg")
    let glue2 = PluginItem(uri: "u:glue2", name: "My Glue", source: .userLibrary, path: ["Presets", "Old"], format: "adg")
    let lead = PluginItem(uri: "u:lead", name: "Lead", source: .userFolders, path: ["My Racks"], format: "vstpreset")
    let kit = PluginItem(uri: "u:kit", name: "Kit 1", source: .userLibrary, path: ["Presets", "Instruments", "Drum Rack"], format: "adg")
    let eq = PluginItem(uri: "u:eq", name: "EQ Eight", source: .audioEffects, path: [])

    func testGroupsPresetsByFolderBeforeLiveDevices() {
        let titles = PluginGrouping.groups([eq, glue, lead, kit], search: "").map(\.title)
        XCTAssertEqual(titles, ["Presets · Audio Effects", "Presets · Instruments", "Presets · My Racks", "Live · Audio Effects"])
    }

    func testSearchFindsPresets() {
        let groups = PluginGrouping.groups([eq, glue, lead], search: "glue")
        XCTAssertEqual(groups.flatMap(\.items).map(\.uri), ["u:glue"])
    }

    func testBadgeLabels() {
        XCTAssertEqual(PluginGrouping.formatLabel(glue), "Rack")
        XCTAssertEqual(PluginGrouping.formatLabel(lead), "VST3")
    }

    func testSameNamedPresetsInDifferentFoldersStaySeparate() {
        XCTAssertEqual(PluginVariants.collapse([glue, glue2]).count, 2)
    }

    func testIconFallbacks() {
        XCTAssertEqual(IconGuesser.guess(kit), "drums")
        XCTAssertEqual(IconGuesser.guess(PluginItem(uri: "u", name: "Thing", source: .userLibrary, path: ["Presets", "Audio Effects"], format: "adg")), "rack")
        XCTAssertEqual(IconGuesser.guess(glue), "compressor") // name hint wins
    }

    func testPresetFileDetection() {
        XCTAssertTrue(PresetFormat.isPresetFile(URL(fileURLWithPath: "/x/A.ADG")))
        XCTAssertTrue(PresetFormat.isPresetFile(URL(fileURLWithPath: "/x/A.vstpreset")))
        XCTAssertFalse(PresetFormat.isPresetFile(URL(fileURLWithPath: "/x/A.wav")))
    }

    func testPresetsHaveNoColorRule() {
        XCTAssertEqual(ColorRule.forItem(glue), [])
    }
}

final class PresetImportTests: XCTestCase {
    let lib = URL(fileURLWithPath: "/Users/me/Music/Ableton/User Library")

    func testMatchesFileInUserLibraryByFolders() {
        let a = PluginItem(uri: "u:a", name: "Bus", source: .userLibrary, path: ["Presets", "Audio Effects"], format: "adg")
        let b = PluginItem(uri: "u:b", name: "Bus", source: .userLibrary, path: ["Presets", "Old"], format: "adg")
        let file = lib.appendingPathComponent("Presets/Audio Effects/Bus.adg")
        XCTAssertEqual(PresetImport.match(file, in: [b, a], library: lib)?.uri, "u:a")
    }

    func testMatchesPlacesFolderAndPrefersLongestPath() {
        let root = PluginItem(uri: "u:root", name: "Bus", source: .userLibrary, path: [], format: "adg")
        let place = PluginItem(uri: "u:place", name: "Bus", source: .userFolders, path: ["My Racks", "Mix"], format: "adg")
        let file = URL(fileURLWithPath: "/Volumes/Data/My Racks/Mix/Bus.adg")
        XCTAssertEqual(PresetImport.match(file, in: [root, place], library: lib)?.uri, "u:place")
        // A same-named file elsewhere is not the User Library's root preset.
        XCTAssertNil(PresetImport.match(URL(fileURLWithPath: "/Users/me/Downloads/Bus.adg"), in: [root], library: lib))
        XCTAssertEqual(PresetImport.match(lib.appendingPathComponent("Bus.adg"), in: [root], library: lib)?.uri, "u:root")
    }

    func testNoMatchForOtherTypeOrUnknownFile() {
        let a = PluginItem(uri: "u:a", name: "Bus", source: .userLibrary, path: [], format: "adv")
        XCTAssertNil(PresetImport.match(URL(fileURLWithPath: "/tmp/Bus.adg"), in: [a]))
        XCTAssertNil(PresetImport.match(URL(fileURLWithPath: "/tmp/Other.adv"), in: [a]))
    }

    func testIsInsideAndCopyDestination() throws {
        XCTAssertTrue(PresetImport.isInside(lib.appendingPathComponent("Presets/X.adg"), lib))
        XCTAssertFalse(PresetImport.isInside(URL(fileURLWithPath: "/Users/me/Downloads/X.adg"), lib))

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = tmp.appendingPathComponent("Presets/HYNE ASM")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = URL(fileURLWithPath: "/Users/me/Downloads/Bus.adg")
        XCTAssertEqual(PresetImport.copyDestination(for: file, library: tmp).lastPathComponent, "Bus.adg")
        try Data().write(to: folder.appendingPathComponent("Bus.adg"))
        XCTAssertEqual(PresetImport.copyDestination(for: file, library: tmp).lastPathComponent, "Bus 2.adg")
        try? FileManager.default.removeItem(at: tmp)
    }
}
