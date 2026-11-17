import XCTest
@testable import HMLauncherCore

final class LegacyFolderTests: XCTestCase {
    func testMovesOldFolderOnceAndKeepsNewOne() throws {
        let fm = FileManager.default
        let support = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let old = support.appendingPathComponent("HM Launcher")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: old.appendingPathComponent("config.json"))

        ConfigStore.moveLegacyFolder(in: support)
        let new = support.appendingPathComponent("HYNE ASM")
        XCTAssertTrue(fm.fileExists(atPath: new.appendingPathComponent("config.json").path))
        XCTAssertFalse(fm.fileExists(atPath: old.path))

        // A stray old folder never overwrites the new one.
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        ConfigStore.moveLegacyFolder(in: support)
        XCTAssertTrue(fm.fileExists(atPath: old.path))
        XCTAssertTrue(fm.fileExists(atPath: new.appendingPathComponent("config.json").path))
        try? fm.removeItem(at: support)
    }
}
