public enum EntryResolver {
    /// 1. same uri; 2. same name + source, preferring the same browser path; 3. nil.
    public static func resolve(_ entry: Entry, in items: [PluginItem]) -> PluginItem? {
        if let exact = items.first(where: { $0.uri == entry.uri }) { return exact }
        let candidates = items.filter { $0.name == entry.name && $0.source == entry.source }
        return candidates.first(where: { $0.path == entry.path }) ?? candidates.first
    }

    /// Same rules as `resolve(_:in:)`, with dictionary lookups — build once per plugin list, then resolve
    /// entries in O(1). Views resolve every row on every redraw, so the linear version made typing lag.
    public struct Index: Sendable {
        private struct Key: Hashable { let name: String; let source: ItemSource }
        private let byURI: [String: PluginItem]
        private let byName: [Key: [PluginItem]]

        public init(_ items: [PluginItem]) {
            var uri: [String: PluginItem] = [:]
            var name: [Key: [PluginItem]] = [:]
            for item in items {
                if uri[item.uri] == nil { uri[item.uri] = item }
                name[Key(name: item.name, source: item.source), default: []].append(item)
            }
            byURI = uri
            byName = name
        }

        public func resolve(_ entry: Entry) -> PluginItem? {
            if let exact = byURI[entry.uri] { return exact }
            let candidates = byName[Key(name: entry.name, source: entry.source)] ?? []
            return candidates.first(where: { $0.path == entry.path }) ?? candidates.first
        }
    }
}
