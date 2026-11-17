import XCTest
@testable import HMLauncherCore

/// Runs only with HM_LIVE_TEST=1 and ASMbridge selected in a running Live.
final class LiveIntegrationTests: XCTestCase {
    func testHelloAndListAgainstRunningLive() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HM_LIVE_TEST"] == "1", "set HM_LIVE_TEST=1")
        let client = BridgeClient(requestTimeout: 10)
        await client.start()
        let connected = await waitUntil(5) { await client.isConnected }
        XCTAssertTrue(connected)
        let hello = try await client.hello()
        XCTAssertTrue(hello.liveVersion.hasPrefix("12."), hello.liveVersion)
        let items = try await client.listItems()
        XCTAssertTrue(items.contains { $0.name == "EQ Eight" && $0.source == .audioEffects })
        XCTAssertFalse(items.contains { $0.uri.contains(":FileId_") && $0.source != .maxForLive })
        print("LIVE: \(hello.liveVersion), \(items.count) items")
        await client.stop()
    }
}
