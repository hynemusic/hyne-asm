import AppKit
import Combine
import HMLauncherCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var localized: [(NSMenuItem, () -> String)] = []
    var onOpenSettings: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "HYNE ASM")
        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(item({ Loc.t("Einstellungen …", "Settings …") }, #selector(openSettings), ","))
        menu.addItem(item({ Loc.t("Live-Script installieren …", "Install Live Script …") }, #selector(installScript)))
        menu.addItem(item({ Loc.t("Plugin-Liste neu laden", "Reload Plugin List") }, #selector(reload)))
        menu.addItem(.separator())
        menu.addItem(item({ Loc.t("HYNE ASM beenden", "Quit HYNE ASM") }, #selector(quit), "q"))
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for (item, title) in localized { item.title = title() }
        if model.isConnected {
            statusLine.title = Loc.t("Verbunden mit Live", "Connected to Live") + " \(model.liveVersion ?? "") · \(model.catalog.items.count) Plugins"
        } else {
            statusLine.title = Loc.t("Nicht mit Live verbunden", "Not connected to Live")
        }
    }

    private func item(_ title: @escaping () -> String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title(), action: action, keyEquivalent: key)
        i.target = self
        localized.append((i, title))
        return i
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func reload() { model.refreshCatalog() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func installScript() {
        let alert = NSAlert()
        do {
            try ScriptInstaller.install()
            alert.messageText = Loc.t("Live-Script installiert", "Live script installed")
            alert.informativeText = Loc.t("""
            1. Live neu starten.
            2. Live → Einstellungen → Link/Tempo/MIDI.
            3. In einer freien Zeile unter „Control Surface“ „HMLauncherBridge“ wählen, Input und Output auf „None“.
            """, """
            1. Restart Live.
            2. Live → Settings → Link/Tempo/MIDI.
            3. In a free row under “Control Surface” choose “HMLauncherBridge”, Input and Output “None”.
            """)
        } catch {
            alert.messageText = Loc.t("Installation fehlgeschlagen", "Installation failed")
            alert.informativeText = error.localizedDescription
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
