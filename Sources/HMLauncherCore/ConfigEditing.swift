import Foundation

public extension LauncherConfig {
    var favoritesID: UUID { categories.first(where: \.isFavorites)!.id }

    private func index(of categoryID: UUID) -> Int? { categories.firstIndex { $0.id == categoryID } }

    // MARK: Entries (top level or inside a folder)

    /// Adds a plugin to the category, or into one of its folders. Ignored if that container already holds it.
    /// The icon is the one this plugin already has elsewhere, else a guess from its name.
    mutating func addEntry(_ item: PluginItem, to categoryID: UUID, folder: UUID? = nil) {
        let icon = existingIcon(forName: item.name, source: item.source) ?? IconGuesser.guess(item)
        withContainer(categoryID, folder) { list in
            guard !list.contains(where: { !$0.isFolder && $0.uri == item.uri }) else { return }
            list.append(Entry(item: item, iconID: icon))
        }
    }

    @discardableResult
    mutating func addFolder(named name: String, to categoryID: UUID) -> UUID {
        let folder = Entry(folderNamed: name)
        withContainer(categoryID, nil) { $0.append(folder) }
        return folder.id
    }

    /// Removes a plugin or a whole folder, wherever it sits in the category.
    mutating func removeEntry(_ entryID: UUID, from categoryID: UUID) {
        guard let c = index(of: categoryID) else { return }
        categories[c].entries.removeAll { $0.id == entryID }
        for i in categories[c].entries.indices where categories[c].entries[i].isFolder {
            categories[c].entries[i].children?.removeAll { $0.id == entryID }
        }
    }

    /// Reorders within the category, or within one folder of it.
    mutating func moveEntry(in categoryID: UUID, folder: UUID? = nil, from: Int, to: Int) {
        withContainer(categoryID, folder) { list in
            guard list.indices.contains(from), (0..<list.count).contains(to) else { return }
            list.insert(list.remove(at: from), at: to)
        }
    }

    /// Moves a plugin into a folder (appended) or, with `nil`, out to the end of the category. Folders never nest.
    mutating func moveEntry(_ entryID: UUID, toFolder folderID: UUID?, in categoryID: UUID) {
        guard let entry = findEntry(entryID, in: categoryID), !entry.isFolder else { return }
        if let folderID, findEntry(folderID, in: categoryID)?.isFolder != true { return }
        removeEntry(entryID, from: categoryID)
        withContainer(categoryID, folderID) { $0.append(entry) }
    }

    mutating func renameFolder(_ folderID: UUID, in categoryID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        updateEntry(folderID, in: categoryID) { if $0.isFolder { $0.name = trimmed } }
    }

    /// Replaces the folder by its plugins, at the folder's position.
    mutating func dissolveFolder(_ folderID: UUID, in categoryID: UUID) {
        guard let c = index(of: categoryID),
              let f = categories[c].entries.firstIndex(where: { $0.id == folderID && $0.isFolder }) else { return }
        let children = categories[c].entries[f].children ?? []
        categories[c].entries.replaceSubrange(f...f, with: children)
    }

    func findEntry(_ id: UUID, in categoryID: UUID) -> Entry? {
        guard let c = index(of: categoryID) else { return nil }
        for e in categories[c].entries {
            if e.id == id { return e }
            if let hit = e.children?.first(where: { $0.id == id }) { return hit }
        }
        return nil
    }

    // MARK: Categories

    @discardableResult
    mutating func addCategory(named name: String) -> UUID {
        let c = Category(name: name)
        categories.append(c)
        return c.id
    }

    mutating func renameCategory(_ id: UUID, to name: String) {
        guard let c = index(of: id) else { return }
        categories[c].name = name
    }

    mutating func deleteCategory(_ id: UUID) {
        categories.removeAll { $0.id == id && !$0.isFavorites }
    }

    /// Favorites always stays at index 0.
    mutating func moveCategory(from: Int, to: Int) {
        guard categories.indices.contains(from), from != 0, (0..<categories.count).contains(to) else { return }
        let c = categories.remove(at: from)
        categories.insert(c, at: max(1, to))
    }

    /// Drag & drop: moves a category in front of `anchor` (nil = to the end). Favorites never moves and stays first.
    mutating func moveCategory(_ id: UUID, before anchor: UUID?) {
        guard id != anchor, let from = index(of: id), !categories[from].isFavorites else { return }
        let c = categories.remove(at: from)
        let to = anchor.flatMap(index(of:)) ?? categories.count
        categories.insert(c, at: max(1, to))
    }

    // MARK: Icons & names

    /// Icons are per plugin: every entry with the same name and source (e.g. Pro-L 2 VST3 and AU) changes too,
    /// also inside folders. A folder's icon only changes that folder.
    mutating func setIcon(_ iconID: String, entry: UUID, in categoryID: UUID) {
        guard let target = findEntry(entry, in: categoryID) else { return }
        if target.isFolder {
            updateEntry(entry, in: categoryID) { $0.iconID = iconID }
            return
        }
        for ci in categories.indices {
            for ei in categories[ci].entries.indices {
                if !categories[ci].entries[ei].isFolder, Self.samePlugin(categories[ci].entries[ei], target) {
                    categories[ci].entries[ei].iconID = iconID
                }
                for ki in (categories[ci].entries[ei].children ?? []).indices
                where Self.samePlugin(categories[ci].entries[ei].children![ki], target) {
                    categories[ci].entries[ei].children![ki].iconID = iconID
                }
            }
        }
    }

    mutating func setDisplayName(_ name: String?, entry: UUID, in categoryID: UUID) {
        let trimmed = name?.trimmingCharacters(in: .whitespaces)
        updateEntry(entry, in: categoryID) { $0.displayName = (trimmed?.isEmpty ?? true) ? nil : trimmed }
    }

    /// Every plugin entry, including those inside folders.
    var allPluginEntries: [Entry] {
        categories.flatMap { $0.entries.flatMap { $0.children ?? [$0] } }
    }

    // MARK: Helpers

    private func existingIcon(forName name: String, source: ItemSource) -> String? {
        allPluginEntries.first { $0.name == name && $0.source == source }?.iconID
    }

    private static func samePlugin(_ a: Entry, _ b: Entry) -> Bool {
        a.uri == b.uri || (a.name == b.name && a.source == b.source)
    }

    private mutating func withContainer(_ categoryID: UUID, _ folderID: UUID?, _ change: (inout [Entry]) -> Void) {
        guard let c = index(of: categoryID) else { return }
        if let folderID {
            guard let f = categories[c].entries.firstIndex(where: { $0.id == folderID && $0.isFolder }) else { return }
            change(&categories[c].entries[f].children!)
        } else {
            change(&categories[c].entries)
        }
    }

    private mutating func updateEntry(_ id: UUID, in categoryID: UUID, _ change: (inout Entry) -> Void) {
        guard let c = index(of: categoryID) else { return }
        for i in categories[c].entries.indices {
            if categories[c].entries[i].id == id { change(&categories[c].entries[i]); return }
            if let k = categories[c].entries[i].children?.firstIndex(where: { $0.id == id }) {
                change(&categories[c].entries[i].children![k]); return
            }
        }
    }
}

public extension LauncherConfig {
    /// The Favorites entry for this panel row, matched by the entry's resolved uri (VST3 and AU stay distinct).
    func favoriteEntry(for row: PanelRow, items: [PluginItem]) -> Entry? {
        guard row.folderID == nil else { return nil }
        return categories.first(where: \.isFavorites)?.entries.flatMap { $0.children ?? [$0] }.first {
            $0.uri == row.uri || EntryResolver.resolve($0, in: items)?.uri == row.uri
        }
    }
}
