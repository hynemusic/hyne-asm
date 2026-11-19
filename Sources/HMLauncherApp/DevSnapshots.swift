import AppKit
import SwiftUI
import HMLauncherCore

/// Developer aids (debug builds only): environment switches that preview a theme/page and save screenshots of the
/// windows for design reviews (`scripts/snapshot-settings.sh`). The installed app is built in release and has none.
enum Dev {
    static func env(_ key: String) -> String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment[key]
        #else
        return nil
        #endif
    }
}

#if DEBUG
extension AppDelegate {
    func runDevSnapshots() {
        // Developer aid: HM_SNAPSHOT=<file.png> opens settings and saves a picture of the window, then quits.
        if let path = Dev.env("HM_SNAPSHOT") {
            settings.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.settings.snapshot(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
        // Developer aid: HM_ONBOARDING_STEP=<0-4> + HM_ONBOARDING_SNAPSHOT=<file.png> saves that welcome step, then quits.
        if let raw = Dev.env("HM_ONBOARDING_STEP"), let step = OnboardingStep(rawValue: Int(raw) ?? 0),
           let path = Dev.env("HM_ONBOARDING_SNAPSHOT") {
            onboarding.show(step: step)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.onboarding.snapshot(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
        // Developer aid: HM_SNAPSHOT_KNOWN=<dir> saves the shortcut overview (plain and with a hovered shortcut), then quits.
        if let dir = Dev.env("HM_SNAPSHOT_KNOWN") {
            let out = URL(fileURLWithPath: dir)
            func render(_ name: String, hover: String?, then: @escaping () -> Void) {
                KnownShortcutsSheet.debugHover = hover
                let host = NSHostingView(rootView: KnownShortcutsSheet(config: model.config) {})
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 580), styleMask: [.borderless], backing: .buffered, defer: false)
                w.contentView = host
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
        if let dir = Dev.env("HM_SNAPSHOT_PANEL") {
            let out = URL(fileURLWithPath: dir)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                let screen = NSScreen.main?.visibleFrame ?? .zero
                self.panel.show(at: CGPoint(x: screen.midX - PanelView.width / 2, y: screen.maxY - 80))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.panel.snapshot(to: out.appendingPathComponent("panel.png"))
                    for _ in 0..<3 { _ = self.panel.handle(.right) } // a shorter category: height must stay
                    self.panel.snapshot(to: out.appendingPathComponent("panel-short-tab.png"))
                    // Opened fresh on the short category: one column wide.
                    self.panel.hide()
                    self.panel.show(at: CGPoint(x: screen.midX - PanelView.width / 2, y: screen.maxY - 80))
                    self.panel.snapshot(to: out.appendingPathComponent("panel-short-fresh.png"))
                    _ = self.panel.handle(.right); _ = self.panel.handle(.right) // back towards Favorites
                    for ch in "re" { _ = self.panel.handle(.character(ch)) }
                    _ = self.panel.handle(.down); _ = self.panel.handle(.down) // a highlighted (lit) entry
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        self.panel.snapshot(to: out.appendingPathComponent("panel-filter.png"))
                        for _ in 0..<9 { _ = self.panel.handle(.down) } // highlight on page 2: the page turns
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            self.panel.snapshot(to: out.appendingPathComponent("panel-page2.png"))
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
        }

    }
}
#endif
