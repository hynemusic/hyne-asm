import Foundation

/// Entries copied (⌘C) or cut (⌘X) in the settings, put back with ⌘V.
public struct EntryClipboard: Equatable, Sendable {
    public var entries: [Entry]
    public var sourceCategory: UUID
    /// Cut entries move on the next paste (then the clipboard turns into a copy, so pasting again duplicates).
    public var isCut: Bool

    public init(entries: [Entry], sourceCategory: UUID, isCut: Bool) {
        self.entries = entries; self.sourceCategory = sourceCategory; self.isCut = isCut
    }
}

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

    /// Moves entries (plugins, folders with their plugins) to the end of another category, keeping list order,
    /// icons and display names. A plugin the target already has is only removed from the source.
    mutating func moveEntries(_ ids: [UUID], toCategory targetID: UUID, from sourceID: UUID) {
        guard targetID != sourceID, let t = categories.firstIndex(where: { $0.id == targetID }) else { return }
        let wanted = Set(ids)
        let source = categories.first { $0.id == sourceID }?.entries ?? []
        // A selected folder carries its plugins; don't move those a second time.
        let carried = Set(source.filter { $0.isFolder && wanted.contains($0.id) }.flatMap { $0.children ?? [] }.map(\.id))
        let moving = orderedEntryIDs(in: sourceID).filter { wanted.contains($0) && !carried.contains($0) }
            .compactMap { findEntry($0, in: sourceID) }
        for e in moving {
            removeEntry(e.id, from: sourceID)
            let existing = Set(categories[t].entries.flatMap { $0.children ?? [$0] }.filter { !$0.isFolder }.map(\.uri))
            if e.isFolder || !existing.contains(e.uri) { categories[t].entries.append(e) }
        }
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

    // MARK: Copy, cut, paste

    /// The selected entries for ⌘C / ⌘X, in list order. A selected folder carries its plugins, so they aren't taken twice.
    func clipboard(_ ids: Set<UUID>, in categoryID: UUID, cut: Bool) -> EntryClipboard? {
        guard let category = categories.first(where: { $0.id == categoryID }) else { return nil }
        var out: [Entry] = []
        for e in category.entries {
            if ids.contains(e.id) { out.append(e); continue }
            out += (e.children ?? []).filter { ids.contains($0.id) }
        }
        return out.isEmpty ? nil : EntryClipboard(entries: out, sourceCategory: categoryID, isCut: cut)
    }

    /// ⌘V: the clipboard's entries go into the category's top level or into a folder, in front of `anchor`
    /// (an entry of that container; at its end when nil or gone). Cut entries move (ids kept); copied ones are
    /// added as new entries. Into a folder, a folder gives its plugins (folders don't nest). A plugin the
    /// container already holds is skipped. Returns the ids of the pasted entries.
    @discardableResult
    mutating func paste(_ clip: EntryClipboard, into categoryID: UUID, folder: UUID?, before anchor: UUID?) -> [UUID] {
        guard categories.contains(where: { $0.id == categoryID }) else { return [] }
        if let folder {
            guard findEntry(folder, in: categoryID)?.isFolder == true else { return [] }
            if clip.isCut, clip.entries.contains(where: { $0.id == folder }) { return [] } // a folder into itself
        }
        var items = clip.entries
        if folder != nil { items = items.flatMap { $0.isFolder ? ($0.children ?? []) : [$0] } }
        if clip.isCut {
            for e in clip.entries { removeEntry(e.id, from: clip.sourceCategory) }
        } else {
            items = items.map(Self.freshCopy)
        }
        let container = folder.flatMap { findEntry($0, in: categoryID)?.children }
            ?? categories.first { $0.id == categoryID }?.entries ?? []
        var taken = Set(container.filter(Self.isPlainPlugin).map(\.uri))
        items = items.filter { !Self.isPlainPlugin($0) || taken.insert($0.uri).inserted }
        insert(items, into: folder, before: anchor, in: categoryID)
        return items.map(\.id)
    }

    private static func isPlainPlugin(_ e: Entry) -> Bool {
        !e.isFolder && e.chain == nil && e.action == nil && !e.uri.isEmpty
    }

    /// The same entry (and a folder's plugins) with new ids.
    private static func freshCopy(_ e: Entry) -> Entry {
        var copy = e
        copy.id = UUID()
        copy.children = e.children?.map { child in var c = child; c.id = UUID(); return c }
        return copy
    }
}
