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
    static var width: CGFloat { PanelView.width }
    private let model: AppModel
    private let panel: LauncherPanel
    private let viewModel: PanelViewModel
    private var outsideClickMonitor: Any?
    private var lastTab = 0
    private var topLeft = CGPoint.zero
    private let hud = HUD()
    private let flyout = FolderFlyout()
    private var flyoutFolder: UUID?

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
                             onHoverRow: { [weak self] in self?.hovered($0) },
                             onSelectTab: { [weak self] in self?.selectTab($0) },
                             isFavorite: { [weak self] in self?.isFavorite($0) ?? false },
                             onToggleFavorite: { [weak self] in self?.toggleFavorite($0) })
        panel.contentView = FirstMouseHostingView(rootView: view)
    }

    var isVisible: Bool { panel.isVisible }

    func contains(_ point: CGPoint) -> Bool {
        (panel.isVisible && panel.frame.contains(point)) || flyout.contains(point)
    }

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
        hideFlyout()
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

    // MARK: Folder side list

    private var pendingHide: Task<Void, Never>?

    /// Another row closes the side list after a short grace period, so a diagonal move from the folder into
    /// the list (brushing the row below) doesn't close it.
    private func hovered(_ row: PanelRow) {
        pendingHide?.cancel()
        if let folder = row.folderID { showFlyout(folder); return }
        guard flyout.isVisible else { return }
        pendingHide = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self, !Task.isCancelled, !self.flyout.contains(NSEvent.mouseLocation) else { return }
            self.hideFlyout()
        }
    }

    /// Opens the folder's plugins right beside the folder row, on top of whatever is there (the right column,
    /// or next to the panel), its first row level with the folder row.
    private func showFlyout(_ folder: UUID) {
        guard flyoutFolder != folder || !flyout.isVisible else { return }
        flyoutFolder = folder
        let index = viewModel.state.rows.firstIndex { $0.folderID == folder } ?? 0
        let column = (index % (PanelGrid.columns * PanelGrid.rowsPerColumn)) / PanelGrid.rowsPerColumn
        let rowMinX = panel.frame.minX + PanelView.padding + CGFloat(column) * (PanelView.columnWidth + PanelView.columnSpacing)
        let rowFrame = NSRect(x: rowMinX, y: panel.frame.minY, width: PanelView.columnWidth, height: panel.frame.height)
        let mouse = NSEvent.mouseLocation
        flyout.show(rows: viewModel.state.folderRows(folder),
                    besides: rowFrame, top: mouse.y + PanelView.rowHeight / 2 + PanelView.padding,
                    onInsert: { [weak self] in self?.insert($0) })
    }

    private func hideFlyout() {
        flyoutFolder = nil
        flyout.hide()
    }

    private func insert(_ row: PanelRow) {
        guard row.isAvailable else { return }
        if let folder = row.folderID {
            showFlyout(folder) // clicking a folder opens its side list
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
        hideFlyout()
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
        let all = viewModel.state.rows
        let globalCount = all.filter(\.isGlobal).count
        let gridRows = PanelGrid.rows(all.count - globalCount) + PanelGrid.rows(globalCount)
        let visibleRows = CGFloat(min(max(gridRows, 1), PanelView.maxVisibleRows))
        let filterHeight: CGFloat = (viewModel.state.filter.isEmpty ? 0 : PanelView.filterHeight)
            + (viewModel.state.openFolderName == nil ? 0 : PanelView.filterHeight)
            + (globalCount > 0 && gridRows <= PanelView.maxVisibleRows ? PanelView.globalHeaderHeight : 0)
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

/// The folder's plugins in a small list to the right of the panel (left if there is no room).
@MainActor
final class FolderFlyout {
    private let panel: NSPanel
    private let model = FlyoutModel()

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = FlyoutHostingView(rootView: FlyoutView(model: model))
    }

    var isVisible: Bool { panel.isVisible }

    func contains(_ point: CGPoint) -> Bool { panel.isVisible && panel.frame.contains(point) }

    func show(rows: [PanelRow], besides main: NSRect, top: CGFloat, onInsert: @escaping (PanelRow) -> Void) {
        model.rows = rows
        model.hovered = nil
        model.onInsert = onInsert
        let visible = CGFloat(min(max(rows.count, 1), PanelView.maxVisibleRows))
        let size = NSSize(width: 280, height: visible * PanelView.rowHeight + PanelView.padding * 2)
        let screen = NSScreen.screens.first { $0.frame.intersects(main) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? main
        var x = main.maxX + 2
        if x + size.width > screen.maxX { x = main.minX - 2 - size.width }
        let y = min(max(top - size.height, screen.minY), screen.maxY - size.height)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}

@MainActor
private final class FlyoutModel: ObservableObject {
    @Published var rows: [PanelRow] = []
    @Published var hovered: Int?
    var onInsert: (PanelRow) -> Void = { _ in }
}

private final class FlyoutHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct FlyoutView: View {
    @ObservedObject var model: FlyoutModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: model.rows.count > PanelView.maxVisibleRows) {
            VStack(spacing: 4) {
                if model.rows.isEmpty {
                    Text(Loc.t("Leerer Ordner", "Empty folder")).font(.system(size: 12)).foregroundColor(.dimText)
                        .frame(maxWidth: .infinity, minHeight: PanelView.rowHeight - 4)
                }
                ForEach(Array(model.rows.enumerated()), id: \.offset) { index, row in
                    Button { model.onInsert(row) } label: {
                        LauncherRow(number: nil, symbol: IconCatalog.symbolName(for: row.iconID), title: row.title,
                                    active: model.hovered == index, available: row.isAvailable, color: Color(label: row.colorID))
                            .opacity(row.isAvailable ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { model.hovered = index } else if model.hovered == index { model.hovered = nil }
                    }
                }
            }
        }
        .padding(PanelView.padding)
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
