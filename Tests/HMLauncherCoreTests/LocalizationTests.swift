import XCTest
@testable import HMLauncherCore

final class LocalizationTests: XCTestCase {
    override func tearDown() { Loc.language = .de }

    func testTranslatePicksCurrentLanguage() {
        Loc.language = .de
        XCTAssertEqual(Loc.t("Einstellungen …", "Settings …"), "Einstellungen …")
        Loc.language = .en
        XCTAssertEqual(Loc.t("Einstellungen …", "Settings …"), "Settings …")
    }

    func testSystemLanguageResolution() {
        XCTAssertEqual(Language.resolve(nil, preferred: ["de-DE", "en-US"]), .de)
        XCTAssertEqual(Language.resolve(nil, preferred: ["en-GB"]), .en)
        XCTAssertEqual(Language.resolve(nil, preferred: ["fr-FR"]), .en)
        XCTAssertEqual(Language.resolve(.de, preferred: ["en-GB"]), .de)
    }

    func testCoreLabelsFollowLanguage() {
        Loc.language = .en
        XCTAssertEqual(PanelKeyAction.close.label, "Close panel")
        XCTAssertEqual(PluginGrouping.otherVST2, "Other VST2")
        XCTAssertEqual(IconCatalog.all.first { $0.id == "saturation" }?.label, "Saturation")
        Loc.language = .de
        XCTAssertEqual(PanelKeyAction.close.label, "Panel schließen")
        XCTAssertEqual(IconCatalog.all.first { $0.id == "saturation" }?.label, "Sättigung")
    }

    func testLanguageIsStoredAndOptional() throws {
        var c = LauncherConfig.makeDefault()
        XCTAssertNil(c.language)
        c.language = .en
        XCTAssertEqual(try JSONDecoder().decode(LauncherConfig.self, from: JSONEncoder().encode(c)).language, .en)
    }

    func testNumbersFollowTheUILanguageNotTheSystemRegion() {
        let saved = Loc.language
        defer { Loc.language = saved }
        Loc.language = .en
        XCTAssertEqual(Loc.number(1455), "1,455")
        XCTAssertTrue(Loc.locale.identifier.hasPrefix("en"))
        Loc.language = .de
        XCTAssertEqual(Loc.number(1455), "1.455")
        XCTAssertTrue(Loc.locale.identifier.hasPrefix("de"))
    }
}
