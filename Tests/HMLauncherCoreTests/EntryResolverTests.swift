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

final class EntryResolverIndexTests: XCTestCase {
    func testIndexMatchesLinearResolve() {
        let items = [
            item("Pro-L 2", uri: "u:v3", path: ["VST3", "FabFilter"]),
            item("Pro-L 2", uri: "u:au", path: ["AUv2", "FabFilter"]),
            item("Utility", uri: "u:util", source: .audioEffects),
            item("Utility", uri: "u:plug"),
        ]
        var c = LauncherConfig.makeDefault()
        let probes = [
            item("Pro-L 2", uri: "u:v3", path: ["VST3", "FabFilter"]),        // by uri
            item("Pro-L 2", uri: "u:gone", path: ["AUv2", "FabFilter"]),      // name fallback, same path
            item("Pro-L 2", uri: "u:gone2", path: ["VST", "Local"]),          // name fallback, first candidate
            item("Utility", uri: "u:x", source: .audioEffects),               // same name, other source
            item("Nope", uri: "u:nope"),
        ]
        for p in probes { c.addEntry(p, to: c.favoritesID) }
        let index = EntryResolver.Index(items)
        for e in c.categories[0].entries {
            XCTAssertEqual(index.resolve(e), EntryResolver.resolve(e, in: items), e.uri)
        }
    }

    func testIndexIsFastForLargeCatalogs() {
        let items = (0..<5000).map { item("P\($0)", uri: "u:\($0)") }
        var c = LauncherConfig.makeDefault()
        for i in stride(from: 0, to: 5000, by: 40) { c.addEntry(items[i], to: c.favoritesID) }
        let index = EntryResolver.Index(items)
        let start = Date()
        for _ in 0..<20 { for e in c.categories[0].entries { _ = index.resolve(e) } }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05)
    }
}
