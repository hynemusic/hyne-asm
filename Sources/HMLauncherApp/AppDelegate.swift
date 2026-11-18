import AppKit
import HMLauncherCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var menuBar: MenuBarController!
    private var monitor: LiveAppMonitor!
    private var eventTap: EventTapController!
    private var panel: PanelWindowController!
    private var settings: SettingsWindowController!
    private var quickSearch: QuickSearchWindowController!
    private var tapRetry: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        monitor = LiveAppMonitor()
        menuBar = MenuBarController(model: model)
        panel = PanelWindowController(model: model)
        eventTap = EventTapController(monitor: monitor)
        settings = SettingsWindowController(model: model)
        quickSearch = QuickSearchWindowController(model: model)
        menuBar.onOpenSettings = { [weak self] in self?.settings.show() }
        // Developer aid: HM_SNAPSHOT=<file.png> opens settings and saves a picture of the window, then quits.
        if let path = ProcessInfo.processInfo.environment["HM_SNAPSHOT"] {
            settings.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.settings.snapshot(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
        // Developer aid: HM_SNAPSHOT_PANEL=<dir> saves the panel (plain, typed filter) and the quick search, then quits.
        if let dir = ProcessInfo.processInfo.environment["HM_SNAPSHOT_PANEL"] {
            let out = URL(fileURLWithPath: dir)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                let screen = NSScreen.main?.visibleFrame ?? .zero
                self.panel.show(at: CGPoint(x: screen.midX - PanelView.width / 2, y: screen.maxY - 80))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.panel.snapshot(to: out.appendingPathComponent("panel.png"))
                    for _ in 0..<3 { _ = self.panel.handle(.right) } // a shorter category: height must stay
                    self.panel.snapshot(to: out.appendingPathComponent("panel-short-tab.png"))
                    _ = self.panel.handle(.right); _ = self.panel.handle(.right) // back towards Favorites
                    for ch in "re" { _ = self.panel.handle(.character(ch)) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        self.panel.snapshot(to: out.appendingPathComponent("panel-filter.png"))
                        self.panel.hide()
                        self.quickSearch.show()
                        for ch in "pro" { _ = self.quickSearch.handle(.character(ch)) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            self.quickSearch.snapshot(to: out.appendingPathComponent("quicksearch.png"))
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
        }

        eventTap.onDoubleRightClick = { [weak self] point in self?.quickSearch.hide(); self?.panel.show(at: point) }
        // While the panel or the quick search is open, keys go to whichever is open.
        eventTap.isPanelVisible = { [weak self] in (self?.panel.isVisible ?? false) || (self?.quickSearch.isVisible ?? false) }
        eventTap.isPointInPanel = { [weak self] in (self?.panel.contains($0) ?? false) || (self?.quickSearch.contains($0) ?? false) }
        eventTap.panelBindings = { [weak self] in self?.model.config.panelKeys ?? .default }
        eventTap.panelKeyHandler = { [weak self] key in
            guard let self else { return false }
            return self.quickSearch.isVisible ? self.quickSearch.handle(key) : self.panel.handle(key)
        }
        eventTap.shortcutHandler = { [weak self] keyCode, mods in self?.handleShortcut(keyCode, mods) ?? false }
        monitor.onChange = { [weak self] liveFront in if !liveFront { self?.panel.hide(); self?.quickSearch.hide() } }

        model.start()
        startEventTap()
    }

    private func handleShortcut(_ keyCode: UInt16, _ mods: ModifierSet) -> Bool {
        guard let pid = monitor.livePID,
              let action = ShortcutMatcher(settings: model.config.shortcuts).match(keyCode: keyCode, modifiers: mods) else { return false }
        switch action {
        case .closeFocused: return WindowCloser.closeFocused(pid: pid)
        case .closeAll:
            // Swallow now, close outside the tap callback.
            DispatchQueue.main.async { WindowCloser.closeAll(pid: pid) }
            return true
        case .quickSearch:
            panel.hide()
            quickSearch.toggle()
            return true
        }
    }

    /// Without the Accessibility permission the tap cannot be created; retry until it is granted.
    private func startEventTap() {
        if eventTap.start() { return }
        Permissions.prompt()
        tapRetry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                if self?.eventTap.start() == true { timer.invalidate() }
            }
        }
    }
}
