import Foundation

enum ScriptInstaller {
    static var targetURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/Ableton/User Library/Remote Scripts/HMLauncherBridge")
    }

    /// Copies the bundled bridge into Live's User Library, replacing an older copy.
    static func install() throws {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("HMLauncherBridge"),
              FileManager.default.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: targetURL.path) { try fm.removeItem(at: targetURL) }
        try fm.copyItem(at: source, to: targetURL)
    }
}
