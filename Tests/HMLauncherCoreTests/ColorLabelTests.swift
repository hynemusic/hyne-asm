import XCTest
@testable import HMLauncherCore

final class ColorLabelTests: XCTestCase {
    let eq8 = item("EQ Eight", uri: "eq8", source: .audioEffects)
    let drift = item("Drift", uri: "drift", source: .instruments)
    let proQ = item("Pro-Q 4", uri: "pq-v3", path: ["VST3", "FabFilter"])
    let proQau = item("Pro-Q 4", uri: "pq-au", path: ["AUv2", "FabFilter"])
    let serum = item("Serum 2", uri: "serum", path: ["VST3", "Xfer Records"])

    func makeConfig() -> LauncherConfig {
        var c = LauncherConfig.makeDefault()
        for i in [eq8, drift, proQ, serum] { c.addEntry(i, to: c.favoritesID) }
        c.addEntry(proQau, to: c.categories[2].id)
        return c
    }

    private func entry(_ c: LauncherConfig, _ name: String, in cat: Int = 0) -> Entry {
        c.categories[cat].entries.first { $0.name == name }!
    }

    func testNoColorByDefault() {
        let c = makeConfig()
        XCTAssertNil(c.colorID(for: entry(c, "EQ Eight")))
    }

    func testSetColorSyncsAcrossCategoriesAndFormats() {
        var c = makeConfig()
        c.setColor("blue", entry: entry(c, "Pro-Q 4").id, in: c.favoritesID)
        XCTAssertEqual(c.colorID(for: entry(c, "Pro-Q 4")), "blue")
        XCTAssertEqual(c.colorID(for: entry(c, "Pro-Q 4", in: 2)), "blue")
        XCTAssertNil(c.colorID(for: entry(c, "Serum 2")))
    }

    func testLiveDeviceRuleColorsAllLiveDevicesIncludingLaterOnes() {
        var c = makeConfig()
        c.setColorRule("orange", for: .liveDevices)
        XCTAssertEqual(c.colorID(for: entry(c, "EQ Eight")), "orange")
        XCTAssertEqual(c.colorID(for: entry(c, "Drift")), "orange")
        XCTAssertNil(c.colorID(for: entry(c, "Serum 2")))
        XCTAssertEqual(c.colorID(for: item("Utility", source: .audioEffects)), "orange")
    }

    func testVendorRule() {
        var c = makeConfig()
        c.setColorRule("purple", for: .vendor("FabFilter"))
        XCTAssertEqual(c.colorID(for: entry(c, "Pro-Q 4")), "purple")
        XCTAssertEqual(c.colorID(for: proQau), "purple")
        XCTAssertNil(c.colorID(for: entry(c, "Serum 2")))
        XCTAssertEqual(ColorRule.forItem(proQ), [.vendor("FabFilter")])
        XCTAssertEqual(ColorRule.forItem(eq8), [.liveDevices])
    }

    func testOwnColorBeatsRuleAndNoneClearsIt() {
        var c = makeConfig()
        c.setColorRule("orange", for: .liveDevices)
        let eq = entry(c, "EQ Eight").id
        c.setColor("green", entry: eq, in: c.favoritesID)
        XCTAssertEqual(c.colorID(for: entry(c, "EQ Eight")), "green")
        c.setColor(ColorPalette.noneID, entry: eq, in: c.favoritesID)
        XCTAssertNil(c.colorID(for: entry(c, "EQ Eight")))   // explicitly no color, despite the rule
        c.setColor(nil, entry: eq, in: c.favoritesID)
        XCTAssertEqual(c.colorID(for: entry(c, "EQ Eight")), "orange") // back to the rule
        c.setColorRule(nil, for: .liveDevices)
        XCTAssertNil(c.colorID(for: entry(c, "EQ Eight")))
    }

    func testOldConfigDecodesWithoutColors() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LauncherConfig.makeDefault())) as! [String: Any]
        json.removeValue(forKey: "colorRules")
        let c = try JSONDecoder().decode(LauncherConfig.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(c.colorRules.isEmpty)
    }

    func testPanelRowsCarryColors() {
        var c = makeConfig()
        c.setColorRule("orange", for: .liveDevices)
        c.setColor("blue", entry: entry(c, "Serum 2").id, in: c.favoritesID)
        var s = PanelState(config: c, items: [eq8, drift, proQ, serum, item("Utility", uri: "util", source: .audioEffects)])
        XCTAssertEqual(s.rows.map(\.colorID), ["orange", "orange", nil, "blue"])
        for ch in "util" { _ = s.handle(.character(ch)) }
        XCTAssertEqual(s.rows.first?.colorID, "orange") // search hit from all plugins follows the rule
    }

    func testPaletteHasNineColors() {
        XCTAssertEqual(ColorPalette.all.count, 9)
        XCTAssertNil(ColorPalette.color(ColorPalette.noneID))
        XCTAssertNotNil(ColorPalette.color("blue"))
    }
}
