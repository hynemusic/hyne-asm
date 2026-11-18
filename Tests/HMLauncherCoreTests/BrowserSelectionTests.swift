import XCTest
@testable import HMLauncherCore

final class BrowserSelectionTests: XCTestCase {
    let glue = item("Glue", uri: "g", source: .userLibrary)
    let bus = item("Bus", uri: "b", source: .userLibrary)
    let proQ = item("Pro-Q 4", uri: "pq", path: ["VST3", "FabFilter"])
    let proL = item("Pro-L 2", uri: "pl", path: ["VST3", "FabFilter"])

    private func entries(_ c: LauncherConfig, _ id: UUID) -> [Entry] { c.categories.first { $0.id == id }!.entries }

    func testFoldersBecomeFoldersAndItemsGoLoose() {
        var c = LauncherConfig.makeDefault()
        let fx = c.categories[2].id
        let sel = BrowserSelection(folders: [.init(title: "Demo Chains", items: [glue, bus])], items: [proQ, glue])
        XCTAssertEqual(sel.pluginCount, 3)
        c.add(sel, to: fx)
        let e = entries(c, fx)
        XCTAssertEqual(e.map(\.title), ["Demo Chains", "Pro-Q 4"]) // Glue is already in the folder
        XCTAssertEqual(e[0].children?.map(\.name), ["Glue", "Bus"])
    }

    func testExistingFolderIsReusedAndDuplicatesSkipped() {
        var c = LauncherConfig.makeDefault()
        let fx = c.categories[2].id
        c.add(BrowserSelection(folders: [.init(title: "FabFilter", items: [proQ])]), to: fx)
        c.add(BrowserSelection(folders: [.init(title: "FabFilter", items: [proQ, proL])]), to: fx)
        let e = entries(c, fx)
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].children?.map(\.name), ["Pro-Q 4", "Pro-L 2"])
    }

    func testLooseAndIntoExistingFolder() {
        var c = LauncherConfig.makeDefault()
        let fx = c.categories[2].id
        let sel = BrowserSelection(folders: [.init(title: "FabFilter", items: [proQ, proL])], items: [glue])
        c.add(sel, to: fx, asFolders: false)
        XCTAssertEqual(entries(c, fx).map(\.name), ["Pro-Q 4", "Pro-L 2", "Glue"])

        let target = c.addFolder(named: "Mine", to: c.favoritesID)
        c.add(sel, to: c.favoritesID, folder: target)
        XCTAssertEqual(entries(c, c.favoritesID).first?.children?.map(\.name), ["Pro-Q 4", "Pro-L 2", "Glue"])
    }

    func testLiveActionsJoinTheSelection() {
        var c = LauncherConfig.makeDefault()
        let fx = c.categories[2].id
        let sel = BrowserSelection(items: [proQ], actions: [LiveAction(kind: .tapTempo), LiveAction(kind: .setTempo)])
        XCTAssertEqual(sel.pluginCount, 3)
        XCTAssertFalse(sel.isEmpty)
        c.add(sel, to: fx)
        c.add(sel, to: fx) // nothing twice
        XCTAssertEqual(entries(c, fx).map(\.title), ["Pro-Q 4", LiveAction(kind: .tapTempo).title, LiveAction(kind: .setTempo).title])
    }

    func testLiveActionsGoIntoATargetFolder() {
        var c = LauncherConfig.makeDefault()
        let folder = c.addFolder(named: "Transport", to: c.favoritesID)
        c.add(BrowserSelection(actions: [LiveAction(kind: .toggleMetronome)]), to: c.favoritesID, folder: folder)
        XCTAssertEqual(entries(c, c.favoritesID).first?.children?.map(\.title), [LiveAction(kind: .toggleMetronome).title])
        XCTAssertTrue(BrowserSelection(actions: [LiveAction(kind: .toggleMetronome)]).folders.isEmpty)
    }
}
