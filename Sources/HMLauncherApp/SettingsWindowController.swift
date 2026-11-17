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
            let host = NSHostingController(rootView: SettingsView(model: model, catalog: model.catalog))
            // The window keeps its own size; otherwise it grows/shrinks with each page's preferred size.
            host.sizingOptions = []
            let w = NSWindow(contentViewController: host)
            w.title = Self.title
            titleUpdates = model.$config.sink { [weak w] _ in DispatchQueue.main.async { w?.title = Self.title } }
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.contentMinSize = NSSize(width: 900, height: 560)
            w.setContentSize(NSSize(width: 1320, height: 820))
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("HYNE ASM Settings")   // remembers the size you drag it to
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
