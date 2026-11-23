import XCTest
@testable import HMLauncherCore

final class PluginWindowsTests: XCTestCase {
    private func button(_ path: String, open: Bool = false) -> PluginWindowButton {
        PluginWindowButton(identifier: path + PluginWindowPlanner.buttonSuffix, isOpen: open)
    }

    func testDevicePath() {
        XCTAssertEqual(PluginWindowPlanner.devicePath(of: "TrackView.Device[0].Device[1].TitleBar.PluginEdit"), "TrackView.Device[0].Device[1]")
        XCTAssertEqual(PluginWindowPlanner.devicePath(of: "TrackView.Device[2]"), "TrackView.Device[2]")
        XCTAssertNil(PluginWindowPlanner.devicePath(of: "TrackView"))
        XCTAssertNil(PluginWindowPlanner.devicePath(of: "Arrangement.Track[3]"))
        XCTAssertNil(PluginWindowPlanner.devicePath(of: nil))
    }




    func testToPressOpensClosedOrTogglesAllClosed() {
        let open = button("TrackView.Device[0]", open: true), closed = button("TrackView.Device[1]")
        XCTAssertEqual(PluginWindowPlanner.toPress([open, closed]), [closed])
        XCTAssertEqual(PluginWindowPlanner.toPress([open]), [open])
        XCTAssertEqual(PluginWindowPlanner.toPress([]), [])
    }



    func testSettingsAreLeftOutOfOlderConfigs() throws {
        var config = LauncherConfig.makeDefault()
        XCTAssertNil(config.pluginWindows)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(config), as: UTF8.self).contains("pluginWindows"))
        config.pluginWindows = PluginWindowSettings()
        config.pluginWindows?.openAll = [KeyCombo(keyCode: 35, modifiers: [.cmd, .ctrl])]
        config.pluginWindows?.xyClick = false
        let back = try JSONDecoder().decode(LauncherConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(back.pluginWindows, config.pluginWindows)
    }

    func testPluginWindowShortcutsShowAsOwners() {
        var config = LauncherConfig.makeDefault()
        let combo = KeyCombo(keyCode: 35, modifiers: [.cmd, .ctrl])
        config.pluginWindowSettings.openAll = [combo]
        XCTAssertEqual(config.shortcutOwner(of: combo), Loc.t("Alle Plugin-Fenster der Spur öffnen", "Open all plugin windows of the track"))
        XCTAssertTrue(config.isOpenPluginWindowsShortcut(keyCode: 35, modifiers: [.cmd, .ctrl]))
        XCTAssertFalse(config.isOpenPluginWindowsShortcut(keyCode: 35, modifiers: [.cmd]))
    }


    func testXYButton() {
        XCTAssertEqual(PluginWindowPlanner.xyButton(for: "TrackView.Device[3].PluginXyControl"), "TrackView.Device[3].TitleBar.PluginEdit")
        XCTAssertEqual(PluginWindowPlanner.xyButton(for: "TrackView.Device[0].Device[1].PluginXyControl.Slider"),
                       "TrackView.Device[0].Device[1].TitleBar.PluginEdit")
        XCTAssertNil(PluginWindowPlanner.xyButton(for: "TrackView.Device[3]"), "the device outside the field (gain, mix)")
        XCTAssertNil(PluginWindowPlanner.xyButton(for: "TrackView.Device[3].PluginXyControlX"))
        XCTAssertNil(PluginWindowPlanner.xyButton(for: "TrackView.Device[3].TitleBar.device_title"))
        XCTAssertNil(PluginWindowPlanner.xyButton(for: nil))
    }

    func testSelectionFollowsClicksAndShiftRanges() {
        var t = DeviceSelectionTracker()
        t.click(on: "TrackView.Device[1].TitleBar.device_title", extend: false)
        XCTAssertEqual(t.selection, ["TrackView.Device[1]"])
        t.click(on: "TrackView.Device[3].TitleBar.device_title", extend: true)
        XCTAssertEqual(t.selection, ["TrackView.Device[1]", "TrackView.Device[2]", "TrackView.Device[3]"])
        XCTAssertEqual(t.devices(forClickOn: "TrackView.Device[2]"), t.selection)
        XCTAssertEqual(t.devices(forClickOn: "TrackView.Device[5]"), ["TrackView.Device[5]"], "outside the selection: just that one")
        // ⇧-click backwards from the same anchor.
        t.click(on: "TrackView.Device[0]", extend: true)
        XCTAssertEqual(t.selection, ["TrackView.Device[0]", "TrackView.Device[1]"])
        t.click(on: "ArrangementView", extend: false)
        XCTAssertEqual(t.selection, [])
        XCTAssertEqual(t.devices(forClickOn: "TrackView.Device[0]"), ["TrackView.Device[0]"])
    }

    func testShiftWithoutAnchorOrAcrossChainsSelectsOne() {
        var t = DeviceSelectionTracker()
        t.click(on: "TrackView.Device[2]", extend: true)
        XCTAssertEqual(t.selection, ["TrackView.Device[2]"])
        t.click(on: "TrackView.Device[0].Device[1]", extend: true)
        XCTAssertEqual(t.selection, ["TrackView.Device[0].Device[1]"], "inside a rack is another chain")
        t.click(on: "TrackView.Device[0].Device[3].PluginXyControl", extend: true)
        XCTAssertEqual(t.selection, ["TrackView.Device[0].Device[1]", "TrackView.Device[0].Device[2]", "TrackView.Device[0].Device[3]"])
    }
}
