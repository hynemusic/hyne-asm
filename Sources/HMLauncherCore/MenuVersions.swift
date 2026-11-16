import Foundation

/// A whole menu (categories with order, icons and display names) as a shareable file (`.hmlmenu`).
public struct MenuDocument: Codable, Sendable {
    public static let formatID = "hm-launcher-menu"
    public static let fileExtension = "hmlmenu"

    public var format: String
    public var formatVersion: Int
    public var name: String
    public var createdAt: Date
    public var categories: [Category]

    public init(name: String, categories: [Category], createdAt: Date = Date()) {
        format = Self.formatID
        formatVersion = 1
        self.name = name
        self.createdAt = createdAt
        self.categories = categories
    }

    public struct NotAMenuFile: Error {}

    public func write(to url: URL) throws {
        try Self.encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> MenuDocument {
        let doc = try decoder.decode(MenuDocument.self, from: Data(contentsOf: url))
        guard doc.format == formatID else { throw NotAMenuFile() }
        return doc
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

public struct MenuVersion: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let date: Date
    public let isAutomatic: Bool
    public let categoryCount: Int
    public let entryCount: Int
}

/// Saved states of the menu, one JSON file each. Automatic versions (made before an import, push or restore)
/// are pruned to the newest `maxAutomatic`; versions saved by hand are kept.
public final class MenuVersionStore {
    private struct Stored: Codable {
        var isAutomatic: Bool
        var document: MenuDocument
    }

    public let directory: URL
    private let maxAutomatic: Int

    public init(directory: URL, maxAutomatic: Int = 30) {
        self.directory = directory
        self.maxAutomatic = maxAutomatic
    }

    public static var defaultDirectory: URL {
        ConfigStore.defaultURL.deletingLastPathComponent().appendingPathComponent("Versions")
    }

    @discardableResult
    public func save(name: String, categories: [Category], isAutomatic: Bool, date: Date = Date()) throws -> MenuVersion {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = "\(Int(date.timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))"
        let stored = Stored(isAutomatic: isAutomatic, document: MenuDocument(name: name, categories: categories, createdAt: date))
        try MenuDocument.encoder.encode(stored).write(to: url(id), options: .atomic)
        if isAutomatic { try prune() }
        return Self.version(id, stored)
    }

    public func list() throws -> [MenuVersion] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { file -> MenuVersion? in
                guard let stored = try? MenuDocument.decoder.decode(Stored.self, from: Data(contentsOf: file)) else { return nil }
                return Self.version(file.deletingPathExtension().lastPathComponent, stored)
            }
            .sorted { $0.date > $1.date }
    }

    public func load(_ id: String) throws -> MenuDocument {
        try MenuDocument.decoder.decode(Stored.self, from: Data(contentsOf: url(id))).document
    }

    public func delete(_ id: String) throws {
        try FileManager.default.removeItem(at: url(id))
    }

    private func prune() throws {
        for old in try list().filter(\.isAutomatic).dropFirst(maxAutomatic) { try delete(old.id) }
    }

    private func url(_ id: String) -> URL { directory.appendingPathComponent(id + ".json") }

    private static func version(_ id: String, _ s: Stored) -> MenuVersion {
        MenuVersion(id: id, name: s.document.name, date: s.document.createdAt, isAutomatic: s.isAutomatic,
                    categoryCount: s.document.categories.count, entryCount: s.document.categories.reduce(0) { $0 + $1.entries.count })
    }
}
