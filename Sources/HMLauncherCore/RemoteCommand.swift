import Foundation

/// A command from outside the app: a Stream Deck button, Apple Shortcuts, a script.
/// Arrives as `hyneasm://<command>?…` or, with the Stream Deck connection on, `http://127.0.0.1:47821/<command>?…`.
public enum RemoteCommand: Equatable, Sendable {
    case insert(name: String)
    case action(LiveAction)
    case quickSearch
    case panel
    case profile(name: String)
    case nextProfile
    case closePluginWindows

    public static let scheme = "hyneasm"
    public static let httpPort: UInt16 = 47821

    public init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path: [String]
        switch parts.scheme {
        case Self.scheme:
            path = ([parts.host ?? ""] + parts.path.split(separator: "/").map(String.init)).filter { !$0.isEmpty }
        case "http":
            guard parts.host == "127.0.0.1" || parts.host == "localhost" else { return nil }
            path = parts.path.split(separator: "/").map(String.init)
        default:
            return nil
        }
        var query: [String: String] = [:]
        for item in parts.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let name = query["name"].map { $0.trimmingCharacters(in: .whitespaces) }

        switch path.first?.lowercased() {
        case "insert":
            guard let name, !name.isEmpty else { return nil }
            self = .insert(name: name)
        case "action":
            guard let raw = name, let kind = LiveActionKind(rawValue: raw) else { return nil }
            self = .action(LiveAction(kind: kind, value: query["value"].flatMap(Double.init), value2: query["value2"].flatMap(Int.init)))
        case "quicksearch", "quick-search":
            self = .quickSearch
        case "panel":
            self = .panel
        case "profile":
            if path.count > 1, path[1].lowercased() == "next" { self = .nextProfile; return }
            guard let name, !name.isEmpty else { return nil }
            self = .profile(name: name)
        case "close-plugin-windows":
            self = .closePluginWindows
        default:
            return nil
        }
    }

    /// The link that triggers this command (for "Copy Stream Deck Link"). HTTP links carry the install's token.
    public func link(http: Bool, token: String? = nil) -> URL {
        var c = URLComponents()
        let path: String
        var query: [URLQueryItem] = []
        switch self {
        case .insert(let name): path = "insert"; query = [URLQueryItem(name: "name", value: name)]
        case .action(let a):
            path = "action"
            query = [URLQueryItem(name: "name", value: a.kind.rawValue)]
            if let v = a.value { query.append(URLQueryItem(name: "value", value: v.rounded() == v ? String(Int(v)) : String(v))) }
            if let v = a.value2 { query.append(URLQueryItem(name: "value2", value: String(v))) }
        case .quickSearch: path = "quicksearch"
        case .panel: path = "panel"
        case .profile(let name): path = "profile"; query = [URLQueryItem(name: "name", value: name)]
        case .nextProfile: path = "profile/next"
        case .closePluginWindows: path = "close-plugin-windows"
        }
        if http {
            c.scheme = "http"; c.host = "127.0.0.1"; c.port = Int(Self.httpPort); c.path = "/" + path
        } else {
            c.scheme = Self.scheme
            let segments = path.split(separator: "/")
            c.host = String(segments[0])
            c.path = segments.dropFirst().map { "/" + $0 }.joined()
        }
        if http, let token { query.append(URLQueryItem(name: "token", value: token)) }
        c.queryItems = query.isEmpty ? nil : query
        return c.url!
    }
}

/// Finds what an "insert by name" means: a menu entry with that title (chains and actions included) first,
/// else the installed plugin, device or preset with that name.
public enum RemoteTarget {
    public static func row(named name: String, config: LauncherConfig, index: SearchIndex) -> PanelRow? {
        let wanted = name.lowercased()
        for category in config.categories {
            for e in category.entries {
                for entry in e.isFolder ? (e.children ?? []) : [e] where entry.title.lowercased() == wanted {
                    if let special = PanelRow.special(entry, index: index, colorID: nil) { return special }
                    if let resolved = index.resolver.resolve(entry), let row = index.globalRow(forKey: index.usageKey[resolved.uri] ?? "") {
                        return row
                    }
                }
            }
        }
        return index.globalRows.first { $0.title.lowercased() == wanted }
    }
}

/// One request to the local Stream Deck endpoint, checked before anything runs:
/// GET only, the install's token must match, and nothing a browser sends for a web page (Origin, Referer,
/// Sec-Fetch-Site) — so a site open in the user's browser can't fire commands at 127.0.0.1.
public enum RemoteRequest {
    public enum Outcome: Equatable, Sendable {
        case run(RemoteCommand)
        case refused, badRequest, unknown
    }

    /// The request line and headers have arrived.
    public static func isComplete(_ raw: String) -> Bool { raw.contains("\r\n\r\n") }

    public static func handle(_ raw: String, token: String) -> Outcome {
        let lines = raw.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let url = URL(string: "http://127.0.0.1:\(RemoteCommand.httpPort)" + parts[1]) else { return .badRequest }
        let headers = lines.dropFirst().compactMap { line -> String? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return line[..<colon].lowercased()
        }
        if headers.contains(where: { ["origin", "referer", "sec-fetch-site", "sec-fetch-mode"].contains($0) }) { return .refused }
        let sent = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "token" }?.value
        guard let sent, !token.isEmpty, sent == token else { return .refused }
        guard let command = RemoteCommand(url: url) else { return .unknown }
        return .run(command)
    }
}

public extension LauncherConfig {
    static func newToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(20).description
    }
}
