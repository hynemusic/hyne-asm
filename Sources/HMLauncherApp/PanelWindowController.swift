import AppKit
import SwiftUI
import HMLauncherCore

@MainActor
final class PanelViewModel: ObservableObject {
    @Published var state: PanelState
    @Published var hovered: Int?
    init(state: PanelState) { self.state = state }
}

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Floating, non-activating panel: Live stays the active app; keys arrive via the event tap.
@MainActor
final class PanelWindowController {
    static let width: CGFloat = 340
    private let model: AppModel
    private let panel: LauncherPanel
    private let viewModel: PanelViewModel
    private var outsideClickMonitor: Any?
    private var lastTab = 0
    private var topLeft = CGPoint.zero
    private let hud = HUD()

    init(model: AppModel) {
        self.model = model
        viewModel = PanelViewModel(state: PanelState(config: model.config, items: model.catalog.items))
        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                              styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = PanelView(viewModel: viewModel,
                             onInsert: { [weak self] in self?.insert($0) },
                             onCloseFolder: { [weak self] in self?.closeFolder() },
                             onSelectTab: { [weak self] in self?.selectTab($0) },
                             isFavorite: { [weak self] in self?.isFavorite($0) ?? false },
                             onToggleFavorite: { [weak self] in self?.toggleFavorite($0) })
        panel.contentView = FirstMouseHostingView(rootView: view)
    }

    var isVisible: Bool { panel.isVisible }

    func contains(_ point: CGPoint) -> Bool { panel.isVisible && panel.frame.contains(point) }

    func show(at point: CGPoint) {
        viewModel.state = PanelState(config: model.config, items: model.catalog.items, selectedTab: lastTab, usage: model.usage.counts)
        viewModel.hovered = nil
        topLeft = point
        layout()
        panel.orderFrontRegardless()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        panel.orderOut(nil)
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
    }

    /// Returns true: while the panel is open every key belongs to it.
    func handle(_ key: PanelKey) -> Bool {
        var state = viewModel.state
        let action = state.handle(key)
        viewModel.state = state
        lastTab = state.selectedTab
        perform(action)
        if panel.isVisible { layout() }
        return true
    }

    private func perform(_ action: PanelAction) {
        switch action {
        case .none: break
        case .close: hide()
        case .insert(let row): insert(row)
        }
    }

    private func closeFolder() {
        viewModel.state.closeFolder()
        layout()
    }

    private func insert(_ row: PanelRow) {
        guard row.isAvailable else { return }
        if let folder = row.folderID {
            viewModel.state.openFolder(folder)
            viewModel.hovered = nil
            layout()
            return
        }
        hide()
        let client = model.client
        let usage = model.usage
        let hud = self.hud
        Task { @MainActor in
            do {
                try await client.load(uri: row.uri)
                usage.record(row.usageKey)
            } catch BridgeError.notConnected {
                hud.show(Loc.t("Nicht mit Live verbunden", "Not connected to Live"))
            } catch BridgeError.remote(let code) where code == "not_found" {
                hud.show(Loc.t("Plugin nicht gefunden", "Plugin not found"))
            } catch {
                hud.show(Loc.t("Laden fehlgeschlagen", "Loading failed"))
            }
        }
    }

    private func selectTab(_ index: Int) {
        viewModel.state.selectTab(index)
        lastTab = viewModel.state.selectedTab
        layout()
    }

    private func isFavorite(_ row: PanelRow) -> Bool {
        model.config.favoriteEntry(for: row, items: model.catalog.items) != nil
    }

    private func toggleFavorite(_ row: PanelRow) {
        let favID = model.config.favoritesID
        if let entry = model.config.favoriteEntry(for: row, items: model.catalog.items) {
            model.config.removeEntry(entry.id, from: favID)
        } else {
            model.config.addEntry(PluginItem(uri: row.uri, name: row.name, source: row.source, path: row.path), to: favID)
        }
        var state = PanelState(config: model.config, items: model.catalog.items, selectedTab: viewModel.state.selectedTab, usage: model.usage.counts)
        for ch in viewModel.state.filter { _ = state.handle(.character(ch)) }
        viewModel.state = state
        layout()
    }

    /// Height follows the row count; the top-left corner stays at the click, clamped to the screen.
    private func layout() {
        let rows = viewModel.state.rows.count
        let visibleRows = CGFloat(min(max(rows, 1), PanelView.maxVisibleRows))
        let filterHeight: CGFloat = (viewModel.state.filter.isEmpty ? 0 : PanelView.filterHeight)
            + (viewModel.state.openFolderName == nil ? 0 : PanelView.filterHeight)
            + (viewModel.state.rows.contains(where: \.isGlobal) && rows <= PanelView.maxVisibleRows ? PanelView.globalHeaderHeight : 0)
        let height = PanelView.tabBarHeight + filterHeight + visibleRows * PanelView.rowHeight + PanelView.padding * 2
        let screen = NSScreen.screens.first { $0.frame.contains(topLeft) } ?? NSScreen.main
        var frame = NSRect(x: topLeft.x, y: topLeft.y - height, width: Self.width, height: height)
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        panel.setFrame(frame, display: true)
    }
}

/// Short non-activating message near the mouse.
@MainActor
final class HUD {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 28, height: 34)
        let p = panel ?? NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
        box.layer?.cornerRadius = 8
        label.frame.origin = NSPoint(x: 14, y: (size.height - label.frame.height) / 2)
        box.addSubview(label)
        p.contentView = box
        let mouse = NSEvent.mouseLocation
        p.setFrame(NSRect(x: mouse.x + 12, y: mouse.y - size.height - 12, width: size.width, height: size.height), display: true)
        p.orderFrontRegardless()
        panel = p
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak p] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { p?.orderOut(nil) }
        }
    }
}
