import XCTest
@testable import HMLauncherCore

final class TextInputTests: XCTestCase {
    private func typed(_ s: String) -> TextInput {
        var t = TextInput()
        for c in s { _ = t.apply(c.isNumber ? .digit(c.wholeNumberValue!) : .character(c)) }
        return t
    }

    func testDeleteWordLikeMacOS() {
        var t = typed("pro q 4")
        _ = t.apply(.deleteWord); XCTAssertEqual(t.text, "pro q ")
        _ = t.apply(.deleteWord); XCTAssertEqual(t.text, "pro ")
        _ = t.apply(.deleteWord); XCTAssertEqual(t.text, "")
        _ = t.apply(.deleteWord); XCTAssertEqual(t.text, "")
    }

    func testSelectAllThenTypeReplacesAndBackspaceClears() {
        var t = typed("serum")
        _ = t.apply(.selectAll)
        XCTAssertTrue(t.isAllSelected)
        _ = t.apply(.character("v"))
        XCTAssertEqual(t.text, "v")
        XCTAssertFalse(t.isAllSelected)

        t = typed("serum")
        _ = t.apply(.selectAll)
        _ = t.apply(.backspace)
        XCTAssertEqual(t.text, "")
    }

    func testSelectAllOnEmptyDoesNothingAndDeleteToStart() {
        var t = TextInput()
        _ = t.apply(.selectAll)
        XCTAssertFalse(t.isAllSelected)
        t = typed("pro q 4")
        _ = t.apply(.deleteToStart)
        XCTAssertEqual(t.text, "")
        XCTAssertFalse(t.apply(.down))
    }

    func testQuickSearchAndPanelUseIt() {
        let items = [item("Serum 2", uri: "s"), item("Pro-Q 4", uri: "p")]
        var q = QuickSearchState(search: QuickSearch(config: .makeDefault(), items: items, usage: [:]))
        for c in "serum" { _ = q.handle(.character(c)) }
        _ = q.handle(.selectAll)
        XCTAssertTrue(q.isQuerySelected)
        for c in "pro" { _ = q.handle(.character(c)) }
        XCTAssertEqual(q.query, "pro")
        XCTAssertEqual(q.results.first?.row.title, "Pro-Q 4")

        var p = PanelState(config: .makeDefault(), items: items)
        for c in "pro q" { _ = p.handle(.character(c)) }
        _ = p.handle(.deleteWord)
        XCTAssertEqual(p.filter, "pro ")
        _ = p.handle(.selectAll)
        XCTAssertTrue(p.isFilterSelected)
        _ = p.handle(.down)                     // moving ends the selection
        XCTAssertFalse(p.isFilterSelected)
        _ = p.handle(.deleteToStart)
        XCTAssertEqual(p.filter, "")
    }
}
