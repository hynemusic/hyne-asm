import Foundation

public extension LauncherConfig {
    var favoritesID: UUID { categories.first(where: \.isFavorites)!.id }

    private func index(of categoryID: UUID) -> Int? { categories.firstIndex { $0.id == categoryID } }

    mutating func addEntry(_ item: PluginItem, to categoryID: UUID) {
        guard let c = index(of: categoryID), !categories[c].entries.contains(where: { $0.uri == item.uri }) else { return }
        categories[c].entries.append(Entry(item: item))
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

    mutating func setIcon(_ iconID: String, entry: UUID, in categoryID: UUID) {
        updateEntry(entry, in: categoryID) { $0.iconID = iconID }
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
