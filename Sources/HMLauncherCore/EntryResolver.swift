public enum EntryResolver {
    /// 1. same uri; 2. same name + source, preferring the same browser path; 3. nil.
    public static func resolve(_ entry: Entry, in items: [PluginItem]) -> PluginItem? {
        if let exact = items.first(where: { $0.uri == entry.uri }) { return exact }
        let candidates = items.filter { $0.name == entry.name && $0.source == entry.source }
        return candidates.first(where: { $0.path == entry.path }) ?? candidates.first
    }
}
