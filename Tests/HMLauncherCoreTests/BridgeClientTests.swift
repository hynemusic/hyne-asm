import XCTest
@testable import HMLauncherCore

final class BridgeClientTests: XCTestCase {
    var server: FakeBridgeServer!
    var client: BridgeClient!

    override func setUp() async throws {
        server = FakeBridgeServer()
        try server.start()
        client = BridgeClient(port: server.port, requestTimeout: 1, reconnectInterval: 0.3)
        await client.start()
        let connected = await waitUntil { await self.client.isConnected }
        XCTAssertTrue(connected)
    }

    override func tearDown() async throws {
        await client.stop()
        server.stop()
    }

    func testHelloDecodesVersions() async throws {
        server.respond = { ok($0, ["script_version": "1", "live_version": "12.4.16"]) }
        let hello = try await client.hello()
        XCTAssertEqual(hello.scriptVersion, "1")
        XCTAssertEqual(hello.liveVersion, "12.4.16")
    }

    func testLoadSuccess() async throws {
        var seen: [String: Any] = [:]
        server.respond = { seen = $0; return ok($0) }
        try await client.load(uri: "query:AudioFx#EQ%20Eight")
        XCTAssertEqual(seen["cmd"] as? String, "load")
        XCTAssertEqual(seen["uri"] as? String, "query:AudioFx#EQ%20Eight")
    }

    func testLoadRemoteErrorThrowsRemote() async {
        server.respond = { ["id": $0["id"]!, "ok": false, "result": NSNull(), "error": "not_found"] }
        do { try await client.load(uri: "x"); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? BridgeError, .remote("not_found")) }
    }

    func testRequestWhileDisconnectedThrowsNotConnected() async {
        let lonely = BridgeClient(port: 1, requestTimeout: 5)
        let start = Date()
        do { _ = try await lonely.hello(); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? BridgeError, .notConnected) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    func testSlowLoadUsesLoadTimeoutNotRequestTimeout() async throws {
        let slow = BridgeClient(port: server.port, requestTimeout: 0.5, loadTimeout: 3)
        await slow.start()
        _ = await waitUntil { await slow.isConnected }
        server.replyDelay = 1.2
        server.respond = { ok($0) }
        try await slow.load(uri: "query:M4L#Heavy")
        await slow.stop()
    }

    func testTimeoutWhenServerSilent() async {
        server.respond = { _ in nil }
        do { _ = try await client.hello(); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? BridgeError, .timeout) }
    }

    func testReadsLargeResponseSplitAcrossChunks() async throws {
        server.chunkSize = 1024
        let items = (0..<3000).map { ["uri": "u:\($0)", "name": "Plugin \($0)", "source": "plugins", "path": ["VST3", "Vendor"]] as [String: Any] }
        server.respond = { ok($0, ["items": items]) }
        let result = try await client.listItems()
        XCTAssertEqual(result.count, 3000)
        XCTAssertEqual(result[2999], PluginItem(uri: "u:2999", name: "Plugin 2999", source: .plugins, path: ["VST3", "Vendor"]))
    }

    func testResponsesMatchedById() async throws {
        server.reverseOrder = true
        server.respond = { req in
            req["cmd"] as? String == "hello"
                ? ok(req, ["script_version": "1", "live_version": "12"])
                : ok(req, ["items": [] as [Any]])
        }
        async let hello = client.hello()
        async let items = client.listItems()
        let (h, i) = try await (hello, items)
        XCTAssertEqual(h.liveVersion, "12")
        XCTAssertEqual(i, [])
    }

    func testReconnectsAfterServerRestart() async throws {
        let states = StateLog()
        await client.setConnectionHandler { states.append($0) }
        let port = server.port
        server.stop()
        let dropped = await waitUntil { await !self.client.isConnected }
        XCTAssertTrue(dropped)
        server = FakeBridgeServer()
        try server.start(port: port)
        let back = await waitUntil(1.3) { await self.client.isConnected }
        XCTAssertTrue(back)
        XCTAssertEqual(states.values.prefix(2), [false, true])
    }
}

final class StateLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Bool] = []
    var values: [Bool] { lock.withLock { _values } }
    func append(_ v: Bool) { lock.withLock { _values.append(v) } }
}
