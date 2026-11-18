import Foundation

/// The user's own preset files (racks, device presets, plugin presets) as listed by the bridge.
public enum PresetFormat {
    /// Extensions Live can load from the browser, without the dot.
    public static let extensions: Set<String> = ["adg", "adv", "vstpreset", "aupreset", "fxp", "fxb", "amxd"]
    public static let groupPrefix = "Presets · "

    public static func isPresetFile(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    /// Short badge shown next to the preset in the settings browser.
    public static func label(_ item: PluginItem) -> String {
        switch item.format?.lowercased() {
        case "adg": return "Rack"
        case "adv": return "Preset"
        case "vstpreset": return "VST3"
        case "aupreset": return "AU"
        case "fxp", "fxb": return "VST2"
        case "amxd": return "M4L"
        default: return "Preset"
        }
    }

    /// Settings browser group: "Presets · <folder>". User Library presets drop Live's own "Presets" level,
    /// so "Presets/Audio Effects/…" becomes "Presets · Audio Effects". Places folders use their own name.
    public static func groupTitle(_ item: PluginItem) -> String {
        var path = item.path
        if item.source == .userLibrary, path.first == "Presets" { path.removeFirst() }
        if let first = path.first { return groupPrefix + first }
        return groupPrefix + "User Library"
    }

    /// Icon when the name gives no hint: drum racks get drums, instrument racks a synth, other racks the rack icon.
    static func fallbackIcon(_ item: PluginItem) -> String {
        let path = item.path.joined(separator: "/").lowercased()
        if path.contains("drum") { return "drums" }
        if path.contains("instrument") { return "synth" }
        if path.contains("midi") { return "midi" }
        switch item.format?.lowercased() {
        case "adg": return "rack"
        default: return IconCatalog.defaultID
        }
    }
}

/// Dropping preset files from Finder into the settings: find them in Live's list, or copy them into the User Library.
public enum PresetImport {
    /// Live's default User Library location (the same one the Live script is installed into).
    public static var userLibraryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/Ableton/User Library")
    }

    /// Where copied presets go, so they stay together and are easy to find in Live's browser.
    public static let importFolder = ["Presets", "HYNE ASM"]

    /// The listed preset for this file: same name and type, and its browser path matches the file's folders.
    /// When several match (same name in different folders), the one with the longest matching path wins.
    /// User Library presets must sit at exactly their browser path inside the library; Places presets
    /// (whose path starts with the place's name) must end in their browser path.
    public static func match(_ file: URL, in items: [PluginItem], library: URL = userLibraryURL) -> PluginItem? {
        let stem = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension.lowercased()
        let folders = file.deletingLastPathComponent().standardizedFileURL.pathComponents
        let root = library.standardizedFileURL.pathComponents
        let inLibrary = isInside(file, library) ? Array(folders.dropFirst(root.count)) : nil
        return items
            .filter { $0.format?.lowercased() == ext && $0.name == stem }
            .filter { item in
                switch item.source {
                case .userLibrary: return inLibrary == item.path
                case .userFolders: return !item.path.isEmpty && folders.hasSuffix(item.path)
                default: return false
                }
            }
            .max { $0.path.count < $1.path.count }
    }

    public static func isInside(_ file: URL, _ folder: URL) -> Bool {
        let f = file.standardizedFileURL.pathComponents, root = folder.standardizedFileURL.pathComponents
        return f.count > root.count && Array(f.prefix(root.count)) == root
    }

    /// A free file name in the import folder ("Bus.adg", then "Bus 2.adg" …).
    public static func copyDestination(for file: URL, library: URL = userLibraryURL, fileManager: FileManager = .default) -> URL {
        let folder = importFolder.reduce(library) { $0.appendingPathComponent($1) }
        let stem = file.deletingPathExtension().lastPathComponent, ext = file.pathExtension
        var candidate = folder.appendingPathComponent(file.lastPathComponent)
        var n = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(stem) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}

extension Array where Element: Equatable {
    func hasSuffix(_ suffix: [Element]) -> Bool {
        suffix.count <= count && Array(self[(count - suffix.count)...]) == suffix
    }
}
