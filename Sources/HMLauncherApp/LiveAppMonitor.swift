import AppKit

/// Tracks whether Ableton Live is the frontmost app.
@MainActor
final class LiveAppMonitor {
    private(set) var isLiveFrontmost = false
    private(set) var livePID: pid_t?
    var onChange: ((Bool) -> Void)?

    static func isLive(_ app: NSRunningApplication?) -> Bool {
        app?.bundleIdentifier?.hasPrefix("com.ableton.live") ?? false
    }

    init() {
        update(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.update(app) }
        }
    }

    private func update(_ app: NSRunningApplication?) {
        let live = Self.isLive(app)
        if live { livePID = app?.processIdentifier }
        guard live != isLiveFrontmost else { return }
        isLiveFrontmost = live
        onChange?(live)
    }
}
