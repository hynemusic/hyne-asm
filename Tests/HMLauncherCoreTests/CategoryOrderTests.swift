import XCTest
@testable import HMLauncherCore

final class CategoryOrderTests: XCTestCase {
    private func config() -> (LauncherConfig, [UUID]) {
        var c = LauncherConfig.makeDefault()
        c.categories = [c.categories.first { $0.isFavorites }!]
        let ids = ["A", "B", "C"].map { c.addCategory(named: $0) }
        return (c, ids)
    }
    private func names(_ c: LauncherConfig) -> [String] { c.categories.dropFirst().map(\.name) }

    func testMoveBeforeAnotherAndToEnd() {
        var (c, ids) = config()
        c.moveCategory(ids[2], before: ids[0])
        XCTAssertEqual(names(c), ["C", "A", "B"])
        c.moveCategory(ids[2], before: nil)
        XCTAssertEqual(names(c), ["A", "B", "C"])
    }

    func testFavoritesStaysFirst() {
        var (c, ids) = config()
        let fav = c.favoritesID
        c.moveCategory(ids[1], before: fav)
        XCTAssertEqual(c.categories.first?.id, fav)
        XCTAssertEqual(names(c), ["B", "A", "C"])
        c.moveCategory(fav, before: nil)
        XCTAssertEqual(c.categories.first?.id, fav)
    }

    func testDropOnItselfChangesNothing() {
        var (c, ids) = config()
        c.moveCategory(ids[1], before: ids[1])
        XCTAssertEqual(names(c), ["A", "B", "C"])
    }
}
