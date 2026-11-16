import Foundation

public struct PanelRow: Equatable, Sendable {
    public let uri: String
    public let name: String
    public let source: ItemSource
    public let path: [String]
    public let iconID: String
    public let title: String
    public let isAvailable: Bool
    /// Set for folder rows: activating them opens the folder instead of inserting.
    public var folderID: UUID? = nil
    public var childCount: Int = 0
}

public enum PanelTab: Equatable, Sendable {
    case category(UUID, String)
    case all
}

public enum PanelKey: Equatable, Sendable {
    case digit(Int), character(Character)
    case backspace, left, right, tab, up, down, returnKey, escape
}

public enum PanelAction: Equatable, Sendable {
    case none, close
    case insert(PanelRow)
}

public struct PanelState {
    private let config: LauncherConfig
    private let items: [PluginItem]
    /// Rows of the "All" tab, sorted once (rows is read several times per keystroke).
    private let allRows: [PanelRow]
    public private(set) var tabs: [PanelTab]
    public private(set) var selectedTab: Int
    public private(set) var filter = ""
    public private(set) var highlighted: Int?
    /// The folder shown instead of the category's top level.
    public private(set) var openFolderID: UUID?

    public init(config: LauncherConfig, items: [PluginItem], selectedTab: Int = 0) {
        self.config = config
        self.items = items
        allRows = items
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { PanelRow(uri: $0.uri, name: $0.name, source: $0.source, path: $0.path,
                            iconID: IconCatalog.defaultID, title: $0.name, isAvailable: true) }
        tabs = config.categories.map { .category($0.id, $0.name) } + [.all]
        self.selectedTab = min(max(selectedTab, 0), tabs.count - 1)
    }

    /// Without a filter: the category's top level (plugins and folders) or the open folder's plugins.
    /// With a filter at top level the search reaches into folders, so a plugin is found wherever it is filed.
    public var rows: [PanelRow] {
        guard case .category = tabs[selectedTab] else {
            return filter.isEmpty ? allRows : allRows.filter { $0.title.localizedCaseInsensitiveContains(filter) }
        }
        let entries = categoryEntries
        if let openFolderID {
            let children = entries.first { $0.id == openFolderID }?.children ?? []
            return filtered(children.map(row))
        }
        guard !filter.isEmpty else { return entries.map(row) }
        return filtered(entries.flatMap { e in e.isFolder ? [row(e)] + (e.children ?? []).map(row) : [row(e)] })
    }

    public var openFolderName: String? {
        guard let openFolderID else { return nil }
        return categoryEntries.first { $0.id == openFolderID }?.title
    }

    private var categoryEntries: [Entry] {
        guard case .category(let id, _) = tabs[selectedTab] else { return [] }
        return config.categories.first { $0.id == id }?.entries ?? []
    }

    private func filtered(_ rows: [PanelRow]) -> [PanelRow] {
        filter.isEmpty ? rows : rows.filter { $0.title.localizedCaseInsensitiveContains(filter) }
    }

    private func row(_ e: Entry) -> PanelRow {
        if e.isFolder {
            return PanelRow(uri: "", name: e.name, source: e.source, path: [], iconID: e.iconID, title: e.title,
                            isAvailable: true, folderID: e.id, childCount: e.children?.count ?? 0)
        }
        let resolved = EntryResolver.resolve(e, in: items)
        return PanelRow(uri: resolved?.uri ?? e.uri, name: e.name, source: e.source, path: resolved?.path ?? e.path,
                        iconID: e.iconID, title: e.title, isAvailable: resolved != nil)
    }

    public mutating func selectTab(_ index: Int) {
        selectedTab = (index % tabs.count + tabs.count) % tabs.count
        filter = ""
        highlighted = nil
        openFolderID = nil
    }

    public mutating func openFolder(_ id: UUID) {
        openFolderID = id
        filter = ""
        highlighted = nil
    }

    public mutating func closeFolder() {
        openFolderID = nil
        filter = ""
        highlighted = nil
    }

    public mutating func handle(_ key: PanelKey) -> PanelAction {
        switch key {
        case .digit(let d):
            if !filter.isEmpty { return edit { $0.append(String(d)) } }
            guard (1...9).contains(d) else { return .none }
            return insert(at: d - 1)
        case .character(let c):
            return edit { $0.append(c) }
        case .backspace:
            if filter.isEmpty, openFolderID != nil { closeFolder(); return .none }
            return edit { if !$0.isEmpty { $0.removeLast() } }
        case .left:
            selectTab(selectedTab - 1)
        case .right, .tab:
            selectTab(selectedTab + 1)
        case .down:
            guard !rows.isEmpty else { return .none }
            highlighted = highlighted.map { min($0 + 1, rows.count - 1) } ?? 0
        case .up:
            guard !rows.isEmpty else { return .none }
            highlighted = highlighted.map { max($0 - 1, 0) } ?? 0
        case .returnKey:
            if let h = highlighted { return insert(at: h) }
            return filter.isEmpty ? .none : insert(at: 0)
        case .escape:
            if openFolderID != nil { closeFolder(); return .none }
            return .close
        }
        return .none
    }

    private mutating func edit(_ change: (inout String) -> Void) -> PanelAction {
        change(&filter)
        highlighted = nil
        return .none
    }

    /// Folder rows open; plugin rows insert.
    private mutating func insert(at index: Int) -> PanelAction {
        let rows = self.rows
        guard rows.indices.contains(index), rows[index].isAvailable else { return .none }
        if let folder = rows[index].folderID {
            openFolder(folder)
            return .none
        }
        return .insert(rows[index])
    }
}
