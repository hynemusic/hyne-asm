import AppKit
import SwiftUI
import Combine
import HMLauncherCore

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private var titleUpdates: AnyCancellable?

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, catalog: model.catalog)))
            w.title = Self.title
            titleUpdates = model.$config.sink { [weak w] _ in DispatchQueue.main.async { w?.title = Self.title } }
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.setContentSize(NSSize(width: 1040, height: 660))
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private static var title: String { "HYNE ASM – " + Loc.t("Einstellungen", "Settings") }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
