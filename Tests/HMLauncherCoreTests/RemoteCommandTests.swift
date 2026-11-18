import XCTest
@testable import HMLauncherCore

final class RemoteCommandTests: XCTestCase {
    func testParsesSchemeAndHTTPForms() {
        XCTAssertEqual(RemoteCommand(url: URL(string: "hyneasm://insert?name=Serum%202")!), .insert(name: "Serum 2"))
        XCTAssertEqual(RemoteCommand(url: URL(string: "http://127.0.0.1:47821/insert?name=Pro-Q%204")!), .insert(name: "Pro-Q 4"))
        XCTAssertEqual(RemoteCommand(url: URL(string: "hyneasm://quicksearch")!), .quickSearch)
        XCTAssertEqual(RemoteCommand(url: URL(string: "hyneasm://panel")!), .panel)
        XCTAssertEqual(RemoteCommand(url: URL(string: "hyneasm://profile?name=Mixing")!), .profile(name: "Mixing"))
        XCTAssertEqual(RemoteCommand(url: URL(string: "hyneasm://profile/next")!), .nextProfile)
        XCTAssertEqual(RemoteCommand(url: URL(string: "hyneasm://close-plugin-windows")!), .closePluginWindows)
        XCTAssertEqual(RemoteCommand(url: URL(string: "http://127.0.0.1:47821/action?name=set_tempo&value=128")!),
                       .action(LiveAction(kind: .setTempo, value: 128)))
        XCTAssertEqual(RemoteCommand(url: URL(string: "hyneasm://action?name=set_time_signature&value=7&value2=8")!),
                       .action(LiveAction(kind: .setTimeSignature, value: 7, value2: 8)))
    }

    func testRejectsUnknownOrIncomplete() {
        XCTAssertNil(RemoteCommand(url: URL(string: "hyneasm://insert")!))
        XCTAssertNil(RemoteCommand(url: URL(string: "hyneasm://dance")!))
        XCTAssertNil(RemoteCommand(url: URL(string: "hyneasm://action?name=launch_rocket")!))
        XCTAssertNil(RemoteCommand(url: URL(string: "https://example.com/insert?name=x")!))
    }

    func testLinksRoundTrip() {
        let link = RemoteCommand.insert(name: "Vocal Basic").link(http: true)
        XCTAssertEqual(link.absoluteString, "http://127.0.0.1:47821/insert?name=Vocal%20Basic")
        XCTAssertEqual(RemoteCommand(url: link), .insert(name: "Vocal Basic"))
        XCTAssertEqual(RemoteCommand(url: RemoteCommand.action(LiveAction(kind: .setTempo, value: 174)).link(http: false)),
                       .action(LiveAction(kind: .setTempo, value: 174)))
    }

    func testResolvesNamesEntriesFirstThenPlugins() {
        let serum = item("Serum 2", uri: "s")
        var c = LauncherConfig.makeDefault()
        c.categories[0].entries = [Entry(chainNamed: "Vocal Basic", steps: [serum])]
        let index = SearchIndex(items: [serum, item("Serum FX", uri: "fx")], config: c)
        XCTAssertEqual(RemoteTarget.row(named: "vocal basic", config: c, index: index)?.chain, ["s"])
        XCTAssertEqual(RemoteTarget.row(named: "Serum 2", config: c, index: index)?.uri, "s")
        XCTAssertEqual(RemoteTarget.row(named: "serum fx", config: c, index: index)?.uri, "fx")
        XCTAssertNil(RemoteTarget.row(named: "Nothing Like This", config: c, index: index))
    }

    func testStreamDeckSettingDefaultsOff() throws {
        XCTAssertFalse(LauncherConfig.makeDefault().streamDeckEnabled)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LauncherConfig.makeDefault())) as! [String: Any]
        old["streamDeckEnabled"] = nil
        XCTAssertFalse(try JSONDecoder().decode(LauncherConfig.self, from: JSONSerialization.data(withJSONObject: old)).streamDeckEnabled)
    }
}
