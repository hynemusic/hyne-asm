import Foundation

/// A named menu: its own categories, entries and folders ("Production", "Mixing", "Live Show").
/// The active profile's menu is `LauncherConfig.categories`; the others are kept here and swapped in on switch.
public struct Profile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// Only up to date for inactive profiles; the active one lives in `LauncherConfig.categories`.
    public var categories: [Category]

    public init(id: UUID = UUID(), name: String, categories: [Category] = []) {
        self.id = id; self.name = name; self.categories = categories
    }

    public static func == (a: Profile, b: Profile) -> Bool { a.id == b.id && a.name == b.name }
}

public extension LauncherConfig {
    var activeProfile: Profile { profiles.first { $0.id == activeProfileID } ?? profiles[0] }

    /// Adds a profile (not switching to it): a copy of the current menu, or a fresh one with Favorites.
    @discardableResult
    mutating func addProfile(named name: String, copyingCurrent: Bool) -> UUID {
        let profile = Profile(name: name, categories: copyingCurrent ? Self.copy(categories) : Self.freshCategories())
        profiles.append(profile)
        return profile.id
    }

    /// Saves the current menu into the active profile, then loads the other one.
    mutating func switchProfile(to id: UUID) {
        guard id != activeProfileID, let target = profiles.firstIndex(where: { $0.id == id }) else { return }
        if let current = profiles.firstIndex(where: { $0.id == activeProfileID }) { profiles[current].categories = categories }
        var loaded = profiles[target].categories
        if !loaded.contains(where: \.isFavorites) { loaded.insert(Category(name: "Favorites", isFavorites: true), at: 0) }
        categories = loaded
        activeProfileID = id
    }

    mutating func switchToNextProfile() {
        guard profiles.count > 1, let i = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        switchProfile(to: profiles[(i + 1) % profiles.count].id)
    }

    mutating func renameProfile(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].name = trimmed
    }

    /// The active profile and the last one stay.
    mutating func deleteProfile(_ id: UUID) {
        guard id != activeProfileID, profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
    }

    /// Makes sure there is one profile and it is the active one (configs from before profiles).
    internal mutating func ensureProfile() {
        if profiles.isEmpty {
            let first = Profile(name: Loc.t("Standard", "Default"))
            profiles = [first]
            activeProfileID = first.id
        } else if !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = profiles[0].id
        }
    }

    static func freshCategories() -> [Category] {
        [Category(name: "Favorites", isFavorites: true), Category(name: "Instruments"), Category(name: "Effects")]
    }

    /// Copies with new ids, so two profiles never share a category or entry id.
    static func copy(_ categories: [Category]) -> [Category] {
        categories.map { c in
            var n = Category(name: c.name, isFavorites: c.isFavorites)
            n.entries = c.entries.map(copyEntry)
            return n
        }
    }

    private static func copyEntry(_ e: Entry) -> Entry {
        var n = e
        n.id = UUID()
        n.children = e.children?.map(copyEntry)
        return n
    }
}
