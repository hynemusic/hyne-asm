import Foundation
import HMLauncherCore

/// Shared app state. Every config change is saved immediately.
@MainActor
final class AppModel: ObservableObject {
    @Published var config: LauncherConfig {
        didSet {
            Loc.language = Language.resolve(config.language)
            saveConfig()
        }
    }
    @Published private(set) var isConnected = false
    @Published private(set) var liveVersion: String?
    let catalog: PluginCatalog
    let versions = MenuVersionStore(directory: MenuVersionStore.defaultDirectory)
    /// Insert counts per plugin, used to rank search results.
    let usage = UsageStore(url: UsageStore.defaultURL)
    @Published private(set) var versionList: [MenuVersion] = []
    let client: BridgeClient
    private let store: ConfigStore

    init(store: ConfigStore = ConfigStore(url: ConfigStore.defaultURL), client: BridgeClient = BridgeClient()) {
        self.store = store
        self.client = client
        let loaded = store.load()
        Loc.language = Language.resolve(loaded.language)
        config = loaded
        catalog = PluginCatalog(cacheURL: PluginCatalog.defaultCacheURL, client: client)
        saveConfig() // persists migrations right away
    }

    func start() {
        catalog.loadCache()
        Task {
            await client.setConnectionHandler { connected in
                Task { @MainActor [weak self] in self?.connectionChanged(connected) }
            }
            await client.start()
        }
    }

    func saveConfig() {
        do { try store.save(config) } catch { NSLog("HM Launcher: saving config failed: \(error)") }
    }

    // MARK: Menu versions, import, export

    func reloadVersions() {
        versionList = (try? versions.list()) ?? []
    }

    func saveVersion(name: String, automatic: Bool) throws {
        try versions.save(name: name, categories: config.categories, isAutomatic: automatic)
        reloadVersions()
    }

    /// Every change of the whole menu first saves the current state as an automatic version.
    private func backup(_ reason: String) throws {
        try saveVersion(name: reason, automatic: true)
    }

    func push(_ draft: ImportDraft, mode: ImportMode) throws {
        try backup(Loc.t("Vor LES-Import", "Before LES import"))
        config.apply(draft, mode: mode)
    }

    func restoreVersion(_ version: MenuVersion) throws {
        let doc = try versions.load(version.id)
        try backup(Loc.t("Vor Wiederherstellen von „\(version.name)“", "Before restoring “\(version.name)”"))
        config.restoreMenu(doc.categories)
    }

    func importMenuFile(_ url: URL) throws {
        let doc = try MenuDocument.read(from: url)
        try backup(Loc.t("Vor Import von „\(doc.name)“", "Before importing “\(doc.name)”"))
        config.restoreMenu(doc.categories)
    }

    func exportMenu(to url: URL) throws {
        try MenuDocument(name: url.deletingPathExtension().lastPathComponent, categories: config.categories).write(to: url)
    }

    func deleteVersion(_ version: MenuVersion) {
        try? versions.delete(version.id)
        reloadVersions()
    }

    func refreshCatalog() {
        Task { try? await catalog.refresh() }
    }

    private func connectionChanged(_ connected: Bool) {
        isConnected = connected
        guard connected else { liveVersion = nil; return }
        Task {
            liveVersion = try? await client.hello().liveVersion
            try? await catalog.refresh()
        }
    }
}
