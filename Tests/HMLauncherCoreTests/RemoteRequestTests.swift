import XCTest
@testable import HMLauncherCore

final class RemoteRequestTests: XCTestCase {
    let token = "abc123"

    func testValidRequestWithToken() {
        let raw = "GET /insert?name=Serum%202&token=abc123 HTTP/1.1\r\nHost: 127.0.0.1:47821\r\n\r\n"
        XCTAssertEqual(RemoteRequest.handle(raw, token: token), .run(.insert(name: "Serum 2")))
    }

    func testMissingOrWrongTokenIsRefused() {
        XCTAssertEqual(RemoteRequest.handle("GET /quicksearch HTTP/1.1\r\n\r\n", token: token), .refused)
        XCTAssertEqual(RemoteRequest.handle("GET /quicksearch?token=nope HTTP/1.1\r\n\r\n", token: token), .refused)
    }

    func testBrowserRequestsAreRefusedEvenWithToken() {
        let fromPage = "GET /action?name=undo&token=abc123 HTTP/1.1\r\nOrigin: https://evil.example\r\n\r\n"
        XCTAssertEqual(RemoteRequest.handle(fromPage, token: token), .refused)
        let fetchMeta = "GET /action?name=undo&token=abc123 HTTP/1.1\r\nSec-Fetch-Site: cross-site\r\n\r\n"
        XCTAssertEqual(RemoteRequest.handle(fetchMeta, token: token), .refused)
        let referer = "GET /action?name=undo&token=abc123 HTTP/1.1\r\nReferer: https://x.example/\r\n\r\n"
        XCTAssertEqual(RemoteRequest.handle(referer, token: token), .refused)
    }

    func testBadAndUnknown() {
        XCTAssertEqual(RemoteRequest.handle("POST /panel?token=abc123 HTTP/1.1\r\n\r\n", token: token), .badRequest)
        XCTAssertEqual(RemoteRequest.handle("garbage", token: token), .badRequest)
        XCTAssertEqual(RemoteRequest.handle("GET /dance?token=abc123 HTTP/1.1\r\n\r\n", token: token), .unknown)
    }

    func testCompleteness() {
        XCTAssertFalse(RemoteRequest.isComplete("GET /panel?tok"))
        XCTAssertTrue(RemoteRequest.isComplete("GET /panel HTTP/1.1\r\nHost: x\r\n\r\n"))
    }

    func testLinksCarryTheToken() {
        let link = RemoteCommand.quickSearch.link(http: true, token: token).absoluteString
        XCTAssertEqual(link, "http://127.0.0.1:47821/quicksearch?token=abc123")
        XCTAssertEqual(RemoteCommand(url: URL(string: link)!), .quickSearch)
    }

    func testConfigHasAStableTokenAndOldConfigsGetOne() throws {
        let c = LauncherConfig.makeDefault()
        XCTAssertGreaterThanOrEqual(c.streamDeckToken.count, 16)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as! [String: Any]
        old["streamDeckToken"] = nil
        XCTAssertFalse(try JSONDecoder().decode(LauncherConfig.self, from: JSONSerialization.data(withJSONObject: old)).streamDeckToken.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(LauncherConfig.self, from: JSONEncoder().encode(c)).streamDeckToken, c.streamDeckToken)
    }
}
