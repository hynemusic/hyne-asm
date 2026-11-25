import Foundation

/// The folders Live reads plugins and presets from. The app's list comes from Live's browser, so these
/// are shown for orientation only: they are changed in Live itself (Places, Settings → Plug-Ins).
public struct LibraryLocation: Hashable, Sendable {
    public enum Kind: Sendable { case pluginFolder, userLibrary, place }
    public var kind: Kind
    public var name: String
    public var path: String

    public init(kind: Kind, name: String, path: String) {
        self.kind = kind; self.name = name; self.path = path
    }
}

public enum LibraryLocations {
    /// The standard macOS plugin folders Live scans (VST2 and VST3 only when enabled in Live's settings).
    public static func pluginFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [LibraryLocation] {
        let formats = [("VST3", "VST3"), ("VST", "VST2"), ("Components", "Audio Units")]
        let roots = [URL(fileURLWithPath: "/Library/Audio/Plug-Ins"), home.appendingPathComponent("Library/Audio/Plug-Ins")]
        return roots.flatMap { root in
            formats.map { folder, label in
                LibraryLocation(kind: .pluginFolder, name: label, path: root.appendingPathComponent(folder).path)
            }
        }
    }

    /// Live's preferences folder: `~/Library/Preferences/Ableton`.
    public static func preferencesRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Preferences/Ableton")
    }

    /// The `Library.cfg` of the running Live version ("12.4.7" → "Live 12.4.7"), else the most recently changed one.
    public static func libraryConfig(liveVersion: String?, root: URL = preferencesRoot(),
                                     fileManager: FileManager = .default) -> URL? {
        if let liveVersion {
            let exact = root.appendingPathComponent("Live \(liveVersion)/Library.cfg")
            if fileManager.fileExists(atPath: exact.path) { return exact }
        }
        let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders
            .filter { $0.lastPathComponent.hasPrefix("Live ") }
            .map { $0.appendingPathComponent("Library.cfg") }
            .compactMap { url -> (URL, Date)? in
                guard let date = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return nil }
                return (url, date)
            }
            .max { $0.1 < $1.1 }?.0
    }

    /// User Library and Places from a `Library.cfg`. Without a User Library entry, Live's default location is used.
    public static func parse(libraryConfig data: Data) -> [LibraryLocation] {
        let reader = LibraryConfigReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        let library = reader.userLibraryParent.map { URL(fileURLWithPath: $0).appendingPathComponent(reader.userLibraryName ?? "User Library").path }
            ?? PresetImport.userLibraryURL.path
        return [LibraryLocation(kind: .userLibrary, name: "User Library", path: library)] + reader.places
    }

    /// Everything to show: plugin folders, then User Library and Places of the given Live version.
    public static func all(liveVersion: String?) -> [LibraryLocation] {
        let presets = libraryConfig(liveVersion: liveVersion)
            .flatMap { try? Data(contentsOf: $0) }
            .map(parse(libraryConfig:))
            ?? [LibraryLocation(kind: .userLibrary, name: "User Library", path: PresetImport.userLibraryURL.path)]
        return pluginFolders() + presets
    }
}

private final class LibraryConfigReader: NSObject, XMLParserDelegate {
    var userLibraryParent: String?
    var userLibraryName: String?
    var places: [LibraryLocation] = []
    private var inUserLibrary = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "UserLibrary": inUserLibrary = true
        case "ProjectPath" where inUserLibrary && userLibraryParent == nil:
            if let value = attributes["Value"], !value.isEmpty { userLibraryParent = value }
        case "ProjectName" where inUserLibrary && userLibraryName == nil:
            if let value = attributes["Value"], !value.isEmpty { userLibraryName = value }
        case "UserFolderInfo":
            guard let path = attributes["Path"], !path.isEmpty else { return }
            let display = attributes["DisplayName"].flatMap { $0.isEmpty ? nil : $0 } ?? URL(fileURLWithPath: path).lastPathComponent
            places.append(LibraryLocation(kind: .place, name: display, path: path))
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "UserLibrary" { inUserLibrary = false }
    }
}
