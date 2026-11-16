import Foundation

public extension LauncherConfig {
    var favoritesID: UUID { categories.first(where: \.isFavorites)!.id }

    private func index(of categoryID: UUID) -> Int? { categories.firstIndex { $0.id == categoryID } }

    mutating func addEntry(_ item: PluginItem, to categoryID: UUID) {
        guard let c = index(of: categoryID), !categories[c].entries.contains(where: { $0.uri == item.uri }) else { return }
        let icon = existingIcon(forName: item.name, source: item.source) ?? IconGuesser.guess(item)
        categories[c].entries.append(Entry(item: item, iconID: icon))
    }

    mutating func removeEntry(_ entryID: UUID, from categoryID: UUID) {
        guard let c = index(of: categoryID) else { return }
        categories[c].entries.removeAll { $0.id == entryID }
    }

    mutating func moveEntry(in categoryID: UUID, from: Int, to: Int) {
        guard let c = index(of: categoryID), categories[c].entries.indices.contains(from),
              (0..<categories[c].entries.count).contains(to) else { return }
        let e = categories[c].entries.remove(at: from)
        categories[c].entries.insert(e, at: to)
    }

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

    /// Icons are per plugin: every entry with the same name and source (e.g. Pro-L 2 VST3 and AU) changes too.
    mutating func setIcon(_ iconID: String, entry: UUID, in categoryID: UUID) {
        guard let c = index(of: categoryID), let target = categories[c].entries.first(where: { $0.id == entry }) else { return }
        for ci in categories.indices {
            for ei in categories[ci].entries.indices where Self.samePlugin(categories[ci].entries[ei], target) {
                categories[ci].entries[ei].iconID = iconID
            }
        }
    }

    private func existingIcon(forName name: String, source: ItemSource) -> String? {
        categories.lazy.flatMap(\.entries).first { $0.name == name && $0.source == source }?.iconID
    }

    private static func samePlugin(_ a: Entry, _ b: Entry) -> Bool {
        a.uri == b.uri || (a.name == b.name && a.source == b.source)
    }

    mutating func setDisplayName(_ name: String?, entry: UUID, in categoryID: UUID) {
        let trimmed = name?.trimmingCharacters(in: .whitespaces)
        updateEntry(entry, in: categoryID) { $0.displayName = (trimmed?.isEmpty ?? true) ? nil : trimmed }
    }

    private mutating func updateEntry(_ id: UUID, in categoryID: UUID, _ change: (inout Entry) -> Void) {
        guard let c = index(of: categoryID), let e = categories[c].entries.firstIndex(where: { $0.id == id }) else { return }
        change(&categories[c].entries[e])
    }
}

public extension LauncherConfig {
    /// The Favorites entry for this panel row, matched by the entry's resolved uri (VST3 and AU stay distinct).
    func favoriteEntry(for row: PanelRow, items: [PluginItem]) -> Entry? {
        categories.first(where: \.isFavorites)?.entries.first {
            $0.uri == row.uri || EntryResolver.resolve($0, in: items)?.uri == row.uri
        }
    }
}
