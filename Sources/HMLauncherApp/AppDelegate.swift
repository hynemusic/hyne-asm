import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var menuBar: MenuBarController!
    private var monitor: LiveAppMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        monitor = LiveAppMonitor()
        menuBar = MenuBarController(model: model)
        model.start()
        if !Permissions.isTrusted { Permissions.prompt() }
    }
}
