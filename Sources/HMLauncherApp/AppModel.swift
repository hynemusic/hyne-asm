import Foundation
import HMLauncherCore

/// Shared app state. Every config change is saved immediately.
@MainActor
final class AppModel: ObservableObject {
    @Published var config: LauncherConfig { didSet { saveConfig() } }
    @Published private(set) var isConnected = false
    @Published private(set) var liveVersion: String?
    let catalog: PluginCatalog
    let client: BridgeClient
    private let store: ConfigStore

    init(store: ConfigStore = ConfigStore(url: ConfigStore.defaultURL), client: BridgeClient = BridgeClient()) {
        self.store = store
        self.client = client
        config = store.load()
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
