import AppKit
import XCTest
@testable import HMLauncherCore

final class IconCatalogTests: XCTestCase {
    func testEverySymbolExists() {
        for icon in IconCatalog.all {
            XCTAssertNotNil(NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: nil), icon.symbolName)
        }
    }

    func testIdsAreUniqueAndOldIdsStillExist() {
        let ids = IconCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for old in ["generic", "eq", "compressor", "limiter", "reverb", "delay", "synth", "sampler", "drums",
                    "utility", "saturation", "filter", "modulation", "meter", "pitch", "vocal"] {
            XCTAssertTrue(ids.contains(old), old)
        }
    }
}
