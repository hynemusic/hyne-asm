import XCTest
@testable import HMLauncherCore

final class EntryResolverTests: XCTestCase {
    private func entry(for i: PluginItem) -> Entry {
        var c = LauncherConfig.makeDefault()
        c.addEntry(i, to: c.favoritesID)
        return c.categories[0].entries[0]
    }

    func testResolvesByUri() {
        let i = item("Pro-L 2", uri: "u:1")
        XCTAssertEqual(EntryResolver.resolve(entry(for: i), in: [item("X"), i]), i)
    }

    func testResolvesByNameWhenUriChanged() {
        let old = item("Pro-L 2", uri: "u:old", path: ["VST3", "FabFilter"])
        let new = item("Pro-L 2", uri: "u:new", path: ["VST3", "FabFilter"])
        XCTAssertEqual(EntryResolver.resolve(entry(for: old), in: [new]), new)
    }

    func testNameFallbackRequiresSameSource() {
        let old = item("Utility", uri: "u:old", source: .audioEffects)
        let other = item("Utility", uri: "u:new", source: .plugins)
        XCTAssertNil(EntryResolver.resolve(entry(for: old), in: [other]))
    }

    func testNameFallbackPrefersSamePath() {
        let old = item("Pro-L 2", uri: "u:old", path: ["AUv2", "FabFilter"])
        let vst3 = item("Pro-L 2", uri: "u:v3", path: ["VST3", "FabFilter"])
        let au = item("Pro-L 2", uri: "u:au", path: ["AUv2", "FabFilter"])
        XCTAssertEqual(EntryResolver.resolve(entry(for: old), in: [vst3, au]), au)
    }

    func testUnresolvableEntryReturnsNil() {
        XCTAssertNil(EntryResolver.resolve(entry(for: item("Gone")), in: [item("Other")]))
    }
}
