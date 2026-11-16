import XCTest
@testable import HMLauncherCore

final class FavoritesAndPerformanceTests: XCTestCase {
    let vst3 = item("Pro-L 2", uri: "u:v3", path: ["VST3", "FabFilter"])
    let au = item("Pro-L 2", uri: "u:au", path: ["AUv2", "FabFilter"])

    private func row(_ i: PluginItem) -> PanelRow {
        PanelRow(uri: i.uri, name: i.name, source: i.source, path: i.path, iconID: IconCatalog.defaultID, title: i.name, isAvailable: true)
    }

    func testFavoriteEntryDistinguishesFormatsOfSamePlugin() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(vst3, to: c.favoritesID)
        XCTAssertNotNil(c.favoriteEntry(for: row(vst3), items: [vst3, au]))
        XCTAssertNil(c.favoriteEntry(for: row(au), items: [vst3, au]))
    }

    func testFavoriteEntryMatchesStaleUriViaResolver() {
        var c = LauncherConfig.makeDefault()
        c.addEntry(item("Pro-L 2", uri: "u:old", path: ["VST3", "FabFilter"]), to: c.favoritesID)
        XCTAssertNotNil(c.favoriteEntry(for: row(vst3), items: [vst3, au]))
    }

    func testAllTabRowsStayFastWithLargeCatalog() {
        let items = (0..<20000).map { item("Plugin \(20000 - $0)", uri: "u:\($0)") }
        var s = PanelState(config: .makeDefault(), items: items)
        s.selectTab(s.tabs.count - 1)
        let start = Date()
        for _ in 0..<50 { _ = s.rows }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        XCTAssertEqual(s.rows.first?.name, "Plugin 1")
    }
}
