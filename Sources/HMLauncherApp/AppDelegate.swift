import AppKit
import SwiftUI
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
        // Developer aid: HM_SNAPSHOT_KNOWN=<dir> saves the shortcut overview (plain and with a hovered shortcut), then quits.
        if let dir = ProcessInfo.processInfo.environment["HM_SNAPSHOT_KNOWN"] {
            let out = URL(fileURLWithPath: dir)
            func render(_ name: String, hover: String?, then: @escaping () -> Void) {
                KnownShortcutsSheet.debugHover = hover
                let host = NSHostingView(rootView: KnownShortcutsSheet(config: model.config) {})
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 580), styleMask: [.borderless], backing: .buffered, defer: false)
                w.contentView = host
                w.appearance = NSAppearance(named: .darkAqua)
                w.center()
                w.orderFrontRegardless()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name))
                    }
                    w.orderOut(nil)
                    then()
                }
            }
            let duplicate = KnownShortcuts.live.first { $0.title == Loc.t("Duplizieren", "Duplicate") }?.id
            render("known.png", hover: nil) { render("known-hover.png", hover: duplicate) { NSApp.terminate(nil) } }
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
        guard let pid = monitor.livePID else { return false }
        guard let action = ShortcutMatcher(settings: model.config.shortcuts).match(keyCode: keyCode, modifiers: mods) else {
            guard let item = ShortcutMatcher.itemShortcut(keyCode: keyCode, modifiers: mods, in: model.config.itemShortcuts) else { return false }
            DispatchQueue.main.async { self.insert(item) } // outside the tap callback
            return true
        }
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

    private let hud = HUD()

    /// A plugin shortcut: insert straight into the selected track (best format, like the panel).
    private func insert(_ shortcut: ItemShortcut) {
        let items = model.catalog.items
        let target = items.first { $0.uri == shortcut.uri }
            ?? PluginVariants.collapse(items.filter { $0.name == shortcut.name && $0.source == shortcut.source }).first?.preferred
        guard let target else {
            hud.show(Loc.t("„\(shortcut.name)“ nicht gefunden", "“\(shortcut.name)” not found"))
            return
        }
        panel.hide()
        quickSearch.hide()
        let client = model.client, usage = model.usage, hud = self.hud
        let key = PluginVariants.Keys(items).key(target)
        Task { @MainActor in
            do {
                try await client.load(uri: target.uri)
                usage.record(key)
            } catch BridgeError.notConnected {
                hud.show(Loc.t("Nicht mit Live verbunden", "Not connected to Live"))
            } catch {
                hud.show(Loc.t("Laden fehlgeschlagen", "Loading failed"))
            }
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
