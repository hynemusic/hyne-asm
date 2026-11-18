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

    /// The link that triggers this command (for "Copy Stream Deck Link").
    public func link(http: Bool) -> URL {
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
