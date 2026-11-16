import Foundation

public extension LauncherConfig {
    /// Every entry id of the category in list order: top level, each folder followed by its plugins.
    func orderedEntryIDs(in categoryID: UUID) -> [UUID] {
        (categories.first { $0.id == categoryID }?.entries ?? []).flatMap { e in [e.id] + (e.children ?? []).map(\.id) }
    }

    /// Moves several entries together (kept in list order) into the category's top level or into a folder,
    /// in front of `anchor` (an entry of that container) or at its end. Folders never go into folders.
    mutating func moveEntries(_ ids: [UUID], toFolder folderID: UUID?, before anchor: UUID?, in categoryID: UUID) {
        let order = orderedEntryIDs(in: categoryID)
        let wanted = Set(ids)
        let moving = order.filter(wanted.contains).compactMap { findEntry($0, in: categoryID) }
            .filter { folderID == nil || !$0.isFolder }
            .filter { $0.id != folderID }
        guard !moving.isEmpty else { return }
        if let folderID, findEntry(folderID, in: categoryID)?.isFolder != true { return }
        for e in moving { removeEntry(e.id, from: categoryID) }
        insert(moving, into: folderID, before: anchor, in: categoryID)
    }

    /// Puts the selected plugins (from anywhere in the category, folders ignored) into a new folder placed
    /// where the first of them was. Returns the folder, or nil when no plugin was selected.
    @discardableResult
    mutating func groupEntries(_ ids: [UUID], in categoryID: UUID, named name: String) -> UUID? {
        guard let c = categories.firstIndex(where: { $0.id == categoryID }) else { return nil }
        let wanted = Set(ids)
        let plugins = orderedEntryIDs(in: categoryID).filter(wanted.contains)
            .compactMap { findEntry($0, in: categoryID) }.filter { !$0.isFolder }
        guard let first = plugins.first else { return nil }
        // The folder goes where the first plugin sits at top level (or in front of the folder holding it).
        let moved = Set(plugins.map(\.id))
        let slot = categories[c].entries.firstIndex { $0.id == first.id || $0.children?.contains { $0.id == first.id } == true } ?? 0
        let anchor = categories[c].entries[slot...].first { !moved.contains($0.id) }?.id
        for p in plugins { removeEntry(p.id, from: categoryID) }
        var folder = Entry(folderNamed: name)
        folder.children = plugins
        insert([folder], into: nil, before: anchor, in: categoryID)
        return folder.id
    }

    private mutating func insert(_ entries: [Entry], into folderID: UUID?, before anchor: UUID?, in categoryID: UUID) {
        guard let c = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        if let folderID {
            guard let f = categories[c].entries.firstIndex(where: { $0.id == folderID }) else { return }
            var list = categories[c].entries[f].children ?? []
            list.insert(contentsOf: entries, at: anchor.flatMap { a in list.firstIndex { $0.id == a } } ?? list.count)
            categories[c].entries[f].children = list
        } else {
            let list = categories[c].entries
            categories[c].entries.insert(contentsOf: entries, at: anchor.flatMap { a in list.firstIndex { $0.id == a } } ?? list.count)
        }
    }
}
