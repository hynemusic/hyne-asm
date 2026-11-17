import Foundation

enum ScriptInstaller {
    static var scriptsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/Ableton/User Library/Remote Scripts")
    }
    static var targetURL: URL { scriptsFolder.appendingPathComponent("ASMbridge") }
    /// Name of the bridge before the rename; its copy is removed on install so Live lists only one.
    static var legacyURL: URL { scriptsFolder.appendingPathComponent("HMLauncherBridge") }

    /// Copies the bundled bridge into Live's User Library, replacing an older copy.
    static func install() throws {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("ASMbridge"),
              FileManager.default.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: targetURL.path) { try fm.removeItem(at: targetURL) }
        try fm.copyItem(at: source, to: targetURL)
        if fm.fileExists(atPath: legacyURL.path) { try? fm.removeItem(at: legacyURL) }
    }
}
