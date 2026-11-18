import Combine
import Foundation
import HMLauncherCore

/// Shared app state. Every config change is saved immediately.
@MainActor
final class AppModel: ObservableObject {
    @Published var config: LauncherConfig {
        didSet {
            Loc.language = Language.resolve(config.language)
            if oldValue.theme != config.theme { Self.applyTheme(config.theme) }
            invalidateSearchIndex()
            saveConfig()
        }
    }
    @Published private(set) var isConnected = false
    @Published private(set) var liveVersion: String?
    let catalog: PluginCatalog
    private var catalogWatch: AnyCancellable?
    private var cachedIndex: SearchIndex?
    private var indexRebuild: Task<Void, Never>?

    /// Search data for the panel and the quick search, rebuilt only when the plugin list or the menu changed.
    var searchIndex: SearchIndex {
        if let cachedIndex { return cachedIndex }
        let index = SearchIndex(items: catalog.items, config: config)
        cachedIndex = index
        return index
    }

    /// Drops the index and builds the new one shortly after (changes often come in bursts, e.g. while typing a
    /// name), so the next double-right-click finds it ready.
    private func invalidateSearchIndex() {
        cachedIndex = nil
        indexRebuild?.cancel()
        let items = catalog.items, config = config
        indexRebuild = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            // Built off the main thread, so editing in the settings never stutters.
            let index = await Task.detached(priority: .utility) { SearchIndex(items: items, config: config) }.value
            guard !Task.isCancelled, let self, self.cachedIndex == nil else { return }
            self.cachedIndex = index
        }
    }
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
        Self.applyTheme(loaded.theme)
        catalog = PluginCatalog(cacheURL: PluginCatalog.defaultCacheURL, client: client)
        saveConfig() // persists migrations right away
        catalogWatch = catalog.$items.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.invalidateSearchIndex() }
        }
    }

    /// HM_THEME=<name> previews a theme without saving it (developer aid for screenshots).
    private static func applyTheme(_ theme: AppTheme) {
        let preview = Dev.env("HM_THEME").flatMap(AppTheme.init(rawValue:))
        Palette.apply(preview ?? theme)
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
        do { try store.save(config) } catch { NSLog("HYNE ASM: saving config failed: \(error)") }
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

    // MARK: Inserting

    private let hud = HUD()

    /// The one way anything gets inserted (panel, quick search, plugin shortcuts): load into the selected track,
    /// count the insert, show a short message near the mouse if it fails.
    func insert(_ row: PanelRow) {
        if let action = row.action {
            run(action, usageKey: row.usageKey)
        } else {
            insert(uris: row.chain ?? [row.uri], usageKey: row.usageKey)
        }
    }

    func insert(uri: String, usageKey: String) { insert(uris: [uri], usageKey: usageKey) }

    func run(_ action: LiveAction, usageKey: String) {
        let client = client, usage = usage, hud = hud
        Task { @MainActor in
            do {
                try await client.run(action)
                usage.record(usageKey)
            } catch BridgeError.notConnected {
                hud.show(Loc.t("Nicht mit Live verbunden", "Not connected to Live"))
            } catch BridgeError.remote(let code) where code == "unknown_cmd" {
                hud.show(Loc.t("Live-Script aktualisieren (Menü → Live-Script installieren)", "Update the Live script (menu → Install Live Script)"))
            } catch {
                hud.show(Loc.t("Aktion fehlgeschlagen", "Action failed"))
            }
        }
    }

    /// One plugin or a chain, where the Behavior settings say (end of chain / after the selected device,
    /// selected track / all selected tracks).
    func insert(uris: [String], usageKey: String) {
        let client = client, usage = usage, hud = hud, options = config.insert
        Task { @MainActor in
            do {
                try await client.load(uris: uris, options: options)
                usage.record(usageKey)
            } catch BridgeError.notConnected {
                hud.show(Loc.t("Nicht mit Live verbunden", "Not connected to Live"))
            } catch BridgeError.remote(let code) where code.hasPrefix("not_found") {
                hud.show(Loc.t("Plugin nicht gefunden", "Plugin not found"))
            } catch {
                hud.show(Loc.t("Laden fehlgeschlagen", "Loading failed"))
            }
        }
    }

    func showMessage(_ text: String) { hud.show(text) }

    /// The ↻ button: Live rescans its browser.
    func refreshCatalog() {
        Task { try? await catalog.refresh(rescan: true) }
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
