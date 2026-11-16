import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var onOpenSettings: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "HM Launcher")
        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(item("Einstellungen…", #selector(openSettings), ","))
        menu.addItem(item("Live-Script installieren…", #selector(installScript)))
        menu.addItem(item("Plugin-Liste neu laden", #selector(reload)))
        menu.addItem(.separator())
        menu.addItem(item("HM Launcher beenden", #selector(quit), "q"))
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if model.isConnected {
            statusLine.title = "Verbunden mit Live \(model.liveVersion ?? "") · \(model.catalog.items.count) Plugins"
        } else {
            statusLine.title = "Nicht mit Live verbunden"
        }
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func reload() { model.refreshCatalog() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func installScript() {
        let alert = NSAlert()
        do {
            try ScriptInstaller.install()
            alert.messageText = "Live-Script installiert"
            alert.informativeText = """
            1. Live neu starten.
            2. Live → Einstellungen → Link/Tempo/MIDI.
            3. In einer freien Zeile unter „Control Surface“ „HMLauncherBridge“ wählen, Input und Output auf „None“.
            """
        } catch {
            alert.messageText = "Installation fehlgeschlagen"
            alert.informativeText = error.localizedDescription
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
