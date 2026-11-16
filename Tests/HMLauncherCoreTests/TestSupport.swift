import Foundation
@testable import HMLauncherCore

func item(_ name: String, uri: String? = nil, source: ItemSource = .plugins, path: [String] = []) -> PluginItem {
    PluginItem(uri: uri ?? "u:\(name)", name: name, source: source, path: path)
}

func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
