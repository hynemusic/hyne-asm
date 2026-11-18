import Foundation

/// What is selected in the settings browser: whole folders (presets folder, manufacturer, Live group) and single items.
public struct BrowserSelection: Equatable, Sendable {
    public struct Folder: Equatable, Sendable {
        public let title: String
        public let items: [PluginItem]
        public init(title: String, items: [PluginItem]) { self.title = title; self.items = items }
    }

    public var folders: [Folder]
    public var items: [PluginItem]
    /// Live actions (with their default values: Tempo 120, 4/4).
    public var actions: [LiveAction]

    public init(folders: [Folder] = [], items: [PluginItem] = [], actions: [LiveAction] = []) {
        self.folders = folders
        self.items = items
        self.actions = actions
    }

    public var isEmpty: Bool { folders.isEmpty && items.isEmpty && actions.isEmpty }
    /// Number of entries it adds (an item inside a selected folder counts once).
    public var pluginCount: Int {
        let inFolders = Set(folders.flatMap { $0.items.map(\.uri) })
        return inFolders.count + items.filter { !inFolders.contains($0.uri) }.count + actions.count
    }
}

public extension LauncherConfig {
    /// Adds a browser selection to a category.
    /// - `asFolders`: each selected folder becomes a folder of the same name (an existing one is reused), single
    ///   items go to the top level. Otherwise everything is added loose.
    /// - `folder`: dropped into an existing folder — everything goes in there (folders can't nest).
    /// Plugins the target already holds are skipped.
    mutating func add(_ selection: BrowserSelection, to categoryID: UUID, folder: UUID? = nil, asFolders: Bool = true) {
        let inFolders = Set(selection.folders.flatMap { $0.items.map(\.uri) })
        let loose = selection.items.filter { !inFolders.contains($0.uri) }
        if folder != nil || !asFolders {
            for item in selection.folders.flatMap(\.items) + loose { addEntry(item, to: categoryID, folder: folder) }
            for action in selection.actions { addAction(action, to: categoryID, folder: folder) }
            return
        }
        for f in selection.folders {
            let existing = categories.first { $0.id == categoryID }?.entries.first { $0.isFolder && $0.title == f.title }?.id
            let id = existing ?? addFolder(named: f.title, to: categoryID)
            for item in f.items { addEntry(item, to: categoryID, folder: id) }
        }
        for item in loose { addEntry(item, to: categoryID) }
        for action in selection.actions { addAction(action, to: categoryID) }
    }
}
