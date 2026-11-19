import AppKit
import Combine
import SwiftUI
import HMLauncherCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel!
    private var menuBar: MenuBarController!
    private var monitor: LiveAppMonitor!
    private var eventTap: EventTapController!
    private(set) var panel: PanelWindowController!
    private(set) var settings: SettingsWindowController!
    private(set) var quickSearch: QuickSearchWindowController!
    private(set) var onboarding: OnboardingWindowController!
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
        panel.onOpenSettings = { [weak self] in self?.settings.show() }
        onboarding = OnboardingWindowController(model: model) { [weak self] page in
            self?.model.settingsPageRequest = page
            self?.settings.show()
        }
        menuBar.onShowIntroduction = { [weak self] in self?.onboarding.show() }
        if Onboarding.showOnLaunch(configExisted: model.configExistedAtLaunch, done: model.config.onboardingDone),
           Dev.env("HM_SNAPSHOT") == nil, Dev.env("HM_SNAPSHOT_PANEL") == nil {
            onboarding.show()
        }
        #if DEBUG
        runDevSnapshots()
        #endif

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
        // Stream Deck & co.: the local HTTP endpoint follows its Behavior switch.
        streamDeck.onCommand = { [weak self] in self?.perform($0) }
        let forced = Dev.env("HM_STREAMDECK") != nil   // developer aid: test the endpoint without changing settings
        streamDeck.token = model.config.streamDeckToken
        streamDeckWatch = model.$config.map { $0.streamDeckEnabled || forced }.removeDuplicates().sink { [weak self] on in
            self?.streamDeck.setEnabled(on)
        }
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
        case .nextProfile:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.panel.hide()
                self.model.config.switchToNextProfile()
                self.model.showMessage(Loc.t("Profil: ", "Profile: ") + self.model.config.activeProfile.name)
            }
            return true
        }
    }

    private var streamDeck: StreamDeckServer { model.streamDeck }
    private var streamDeckWatch: AnyCancellable?

    /// `hyneasm://…` links (Stream Deck "Open", Apple Shortcuts, scripts).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let command = RemoteCommand(url: url) { perform(command) }
        }
    }

    /// Runs a command from outside the app.
    func perform(_ command: RemoteCommand) {
        switch command {
        case .insert(let name):
            guard let row = RemoteTarget.row(named: name, config: model.config, index: model.searchIndex) else {
                model.showMessage(Loc.t("„\(name)“ nicht gefunden", "“\(name)” not found"))
                return
            }
            model.insert(row)
        case .action(let action):
            model.run(action, usageKey: "action|" + action.title.lowercased())
        case .quickSearch:
            panel.hide()
            quickSearch.show()
        case .panel:
            quickSearch.hide()
            panel.show(at: NSEvent.mouseLocation)
        case .profile(let name):
            guard let profile = model.config.profiles.first(where: { $0.name.lowercased() == name.lowercased() }) else {
                model.showMessage(Loc.t("Profil „\(name)“ nicht gefunden", "Profile “\(name)” not found"))
                return
            }
            model.config.switchProfile(to: profile.id)
            model.showMessage(Loc.t("Profil: ", "Profile: ") + profile.name)
        case .nextProfile:
            model.config.switchToNextProfile()
            model.showMessage(Loc.t("Profil: ", "Profile: ") + model.config.activeProfile.name)
        case .closePluginWindows:
            if let pid = monitor.livePID { WindowCloser.closeAll(pid: pid) }
        }
    }

    /// A plugin shortcut: insert straight into the selected track (best format, like the panel).
    private func insert(_ shortcut: ItemShortcut) {
        let items = model.catalog.items
        let target = items.first { $0.uri == shortcut.uri }
            ?? PluginVariants.collapse(items.filter { $0.name == shortcut.name && $0.source == shortcut.source }).first?.preferred
        guard let target else {
            model.showMessage(Loc.t("„\(shortcut.name)“ nicht gefunden", "“\(shortcut.name)” not found"))
            return
        }
        panel.hide()
        quickSearch.hide()
        model.insert(uri: target.uri, usageKey: model.searchIndex.usageKey[target.uri] ?? target.uri)
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
