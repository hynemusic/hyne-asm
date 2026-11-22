import XCTest
import CoreGraphics
@testable import HMLauncherCore

/// Shared-fixture handlers for remote commands, the bridge protocol, the window guards and onboarding
/// (spec/fixtures/README.md). The C# side (windows/HyneAsm.Core.Tests/Fixtures.Remote.cs) reads the same inputs the same way.
extension SharedFixtureTests {
    // MARK: Remote commands

    /// A model value as fixture JSON, through its Codable form.
    static func encoded<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    /// `"panel"`, `{"insert": name}`, `{"action": LiveAction}`, `{"profile": name}` …
    static func commandJSON(_ c: RemoteCommand?) throws -> JSONValue {
        guard let c else { return .null }
        switch c {
        case .insert(let name): return .object(["insert": .string(name)])
        case .action(let a): return .object(["action": try encoded(a)])
        case .quickSearch: return .string("quickSearch")
        case .panel: return .string("panel")
        case .profile(let name): return .object(["profile": .string(name)])
        case .nextProfile: return .string("nextProfile")
        case .closePluginWindows: return .string("closePluginWindows")
        }
    }

    static func command(_ v: JSONValue?) throws -> RemoteCommand {
        switch v {
        case .string("quickSearch")?: return .quickSearch
        case .string("panel")?: return .panel
        case .string("nextProfile")?: return .nextProfile
        case .string("closePluginWindows")?: return .closePluginWindows
        default: break
        }
        if case .string(let n)? = v?["insert"] { return .insert(name: n) }
        if case .string(let n)? = v?["profile"] { return .profile(name: n) }
        if let a = v?["action"] { return .action(try decode(LiveAction.self, a)) }
        throw FixtureError(description: "unknown command \(String(describing: v))")
    }

    /// URL text → the command it triggers (null: none, or not a URL).
    static func remoteParse(_ input: JSONValue) throws -> JSONValue {
        guard let url = URL(string: try string(input)) else { return .string("invalid url") }
        return try commandJSON(RemoteCommand(url: url))
    }

    /// `{command, http, token?}` → the link and what it parses back to.
    static func remoteLink(_ input: JSONValue) throws -> JSONValue {
        guard case .bool(let http)? = input["http"] else { throw FixtureError(description: "needs http") }
        let token: String? = { if case .string(let t)? = input["token"] { return t } else { return nil } }()
        let link = try command(input["command"]).link(http: http, token: token)
        return .object(["link": .string(link.absoluteString), "parsed": try commandJSON(RemoteCommand(url: link))])
    }

    /// `{raw, token}` → `{complete, outcome}`; outcome is `{"run": command}`, "refused", "badRequest" or "unknown".
    static func remoteRequest(_ input: JSONValue) throws -> JSONValue {
        let raw = try string(input["raw"])
        let outcome: JSONValue
        switch RemoteRequest.handle(raw, token: try string(input["token"])) {
        case .run(let c): outcome = .object(["run": try commandJSON(c)])
        case .refused: outcome = .string("refused")
        case .badRequest: outcome = .string("badRequest")
        case .unknown: outcome = .string("unknown")
        }
        return .object(["complete": .bool(RemoteRequest.isComplete(raw)), "outcome": outcome])
    }

    // MARK: Bridge protocol

    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: T
        init(_ value: T) { _value = value }
        var value: T {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }

    /// Runs async work from a synchronous fixture handler (the test thread is not part of the async pool).
    static func blocking(_ body: @escaping () async throws -> JSONValue) throws -> JSONValue {
        let done = DispatchSemaphore(value: 0)
        let result = Box<Result<JSONValue, Error>?>(nil)
        Task.detached {
            do { result.value = .success(try await body()) } catch { result.value = .failure(error) }
            done.signal()
        }
        done.wait()
        return try result.value!.get()
    }

    /// `{call, args, reply}` → `{request, result}` or `{request, error}`. The call runs against a local fake bridge;
    /// `request` is the JSON object the client sent, without its `id`. `reply`: an object (sent back with the request's
    /// id), a string (sent verbatim with "{id}" replaced; may hold several lines) or null (no reply).
    /// Timeouts are 0.5 s here (the defaults are asserted in the unit tests).
    static func bridgeProtocol(_ input: JSONValue) throws -> JSONValue {
        let server = FakeBridgeServer()
        try server.start()
        defer { server.stop() }
        let seen = Box<JSONValue>(.null)
        let reply = input["reply"] ?? .null
        server.respondLine = { req in
            if var sent = try? JSONDecoder().decode(JSONValue.self, from: JSONSerialization.data(withJSONObject: req)),
               case .object(var o) = sent {
                o["id"] = nil
                sent = .object(o)
                seen.value = sent
            }
            let id = "\(req["id"] ?? "")"
            switch reply {
            case .null: return nil
            case .string(let raw): return raw.replacingOccurrences(of: "{id}", with: id)
            case .object(var o):
                o["id"] = nil
                let rest = JSONValue.object(o).compact().dropFirst()
                return "{\"id\":\(id)" + (o.isEmpty ? "" : ",") + rest + "\n"
            default: return nil
            }
        }
        let port = server.port
        let call = try string(input["call"])
        let args = input["args"] ?? .object([:])
        return try blocking {
            let client = BridgeClient(port: port, requestTimeout: 0.5, loadTimeout: 0.5, reconnectInterval: 0.3)
            await client.start()
            guard await waitUntil(3, { await client.isConnected }) else { throw FixtureError(description: "bridge: no connection") }
            var out: [String: JSONValue] = [:]
            do {
                switch call {
                case "hello":
                    let h = try await client.hello()
                    out["result"] = .object(["scriptVersion": .string(h.scriptVersion), "liveVersion": .string(h.liveVersion),
                                             "capabilities": try encoded(h.capabilities)])
                case "list":
                    let refresh: Bool = { if case .bool(let b)? = args["refresh"] { return b } else { return false } }()
                    out["result"] = try encoded(try await client.listItems(refresh: refresh))
                case "load":
                    let options = try decode(InsertOptions.self, args["options"])
                    try await client.load(uris: try strings(args["uris"]), options: options)
                    out["result"] = .string("done")
                case "load_uri":
                    try await client.load(uri: try string(args["uri"]))
                    out["result"] = .string("done")
                case "run":
                    try await client.run(try decode(LiveAction.self, args["action"]))
                    out["result"] = .string("done")
                default:
                    throw FixtureError(description: "bridge: unknown call \(call)")
                }
            } catch let e as BridgeError {
                switch e {
                case .notConnected: out["error"] = .string("notConnected")
                case .timeout: out["error"] = .string("timeout")
                case .remote(let m): out["error"] = .string("remote: \(m)")
                }
            } catch is DecodingError {
                out["error"] = .string("decoding")
            }
            await client.stop()
            out["request"] = seen.value
            return .object(out)
        }
    }

    // MARK: Guards and onboarding

    static func double(_ v: JSONValue?) throws -> Double {
        guard case .number(let n)? = v else { throw FixtureError(description: "expected a number, got \(String(describing: v))") }
        return n
    }

    /// `[x, y, width, height]`
    static func rect(_ v: JSONValue?) throws -> CGRect {
        let n = try numbers(v)
        guard n.count == 4 else { throw FixtureError(description: "a rect is [x, y, width, height]") }
        return CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
    }

    static func rectJSON(_ r: CGRect) -> JSONValue {
        .array([r.origin.x, r.origin.y, r.size.width, r.size.height].map { .number(Double($0)) })
    }

    /// `{screen: [{frame, layer, title}], probes: [{frame?, title?, isAXMain}]}` → `{main: [titles], isMain: [Bool]}`.
    static func guardsMainWindow(_ input: JSONValue) throws -> JSONValue {
        let screen = try list(input["screen"]).map {
            MainWindowGuard.ScreenWindow(frame: try rect($0["frame"]), layer: try int($0["layer"]), title: try string($0["title"]))
        }
        let main = MainWindowGuard.mainWindows(screen).map { JSONValue.object(["title": .string($0.title), "frame": rectJSON($0.frame)]) }
        let verdicts = try list(input["probes"]).map { p -> JSONValue in
            let frame = isNull(p["frame"]) ? nil : try rect(p["frame"])
            let title: String? = isNull(p["title"]) ? nil : try string(p["title"])
            guard case .bool(let ax)? = p["isAXMain"] else { throw FixtureError(description: "probe needs isAXMain") }
            return .bool(MainWindowGuard.isMain(frame: frame, title: title, isAXMain: ax, screen: screen))
        }
        return .object(["main": .array(main), "isMain": .array(verdicts)])
    }

    /// `{size: [w, h], below: rect, visible: rect}` → the tooltip frame.
    static func guardsTooltip(_ input: JSONValue) throws -> JSONValue {
        let size = try numbers(input["size"])
        guard size.count == 2 else { throw FixtureError(description: "size is [width, height]") }
        return rectJSON(TooltipPlacement.frame(size: CGSize(width: size[0], height: size[1]), below: try rect(input["below"]),
                                               visible: try rect(input["visible"])))
    }

    /// `{status, configExisted, done}` → steps done and whether the welcome window shows; or
    /// `{starter: items, config?}` → `{added, again, categories: [{name, titles}]}` (a second call adds nothing).
    static func onboardingSteps(_ input: JSONValue) throws -> JSONValue {
        if let starter = input["starter"] {
            let items = try decode([PluginItem].self, starter)
            var config = isNull(input["config"]) ? LauncherConfig.makeDefault() : try decode(LauncherConfig.self, input["config"])
            let added = config.addStarterSet(from: items)
            let again = config.addStarterSet(from: items)
            let categories = config.categories.map { c -> JSONValue in
                .object(["name": .string(c.name), "titles": .array(c.entries.map { .string($0.title) }),
                         "icons": .array(c.entries.map { .string($0.iconID) })])
            }
            return .object(["added": .number(Double(added)), "again": .number(Double(again)), "categories": .array(categories)])
        }
        var s = OnboardingStatus()
        let st = input["status"]
        func flag(_ key: String) -> Bool { if case .bool(let b)? = st?[key] { return b } else { return false } }
        s.permission = flag("permission")
        s.scriptInstalled = flag("scriptInstalled")
        s.connected = flag("connected")
        s.panelOpened = flag("panelOpened")
        s.menuChosen = flag("menuChosen")
        guard case .bool(let existed)? = input["configExisted"], case .bool(let done)? = input["done"] else {
            throw FixtureError(description: "needs configExisted and done")
        }
        let names: [OnboardingStep: String] = [.welcome: "welcome", .permission: "permission", .connect: "connect",
                                               .menu: "menu", .tryIt: "tryIt"]
        return .object([
            "steps": .array(OnboardingStep.allCases.map { .string(names[$0]!) }),
            "done": .array(OnboardingStep.allCases.filter(s.isDone).map { .string(names[$0]!) }),
            "showOnLaunch": .bool(Onboarding.showOnLaunch(configExisted: existed, done: done)),
        ])
    }
}

extension JSONValue {
    /// One-line JSON (for the fake bridge's replies).
    func compact() -> String {
        String(decoding: (try? JSONEncoder().encode(self)) ?? Data("null".utf8), as: UTF8.self)
    }
}
