import AppKit
import SwiftUI
import HMLauncherCore

@MainActor
final class PanelViewModel: ObservableObject {
    @Published var state: PanelState
    @Published var hovered: Int?
    /// One 3×3 block: the panel shows a page of 9 at a time.
    let columns = 1
    /// The page of 9 on show, and which way the last turn went (for the slide).
    @Published var page = 0
    var forward = true
    /// Column width and entry height (resize grip).
    @Published var size = PanelSize.default
    /// ⇧ held: inserting keeps the panel open (pinned mode).
    @Published var pinned = false
    /// An entry being dragged to a new place: its index and the slot it would land in.
    @Published var drag: (from: Int, to: Int)?
    var padHeight: CGFloat { PanelView.padHeight(size) }
    var columnWidth: CGFloat { CGFloat(size.columnWidth) }
    /// Favorites gets a star in the tab bar.
    var favoritesID: UUID?
    init(state: PanelState) { self.state = state }
    func isFavorites(_ id: UUID) -> Bool { id == favoritesID }
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
    private let flyout = FolderFlyout()
    private var flyoutFolder: UUID?

    init(model: AppModel) {
        self.model = model
        viewModel = PanelViewModel(state: PanelState(config: model.config, index: SearchIndex(items: [], config: model.config)))
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
                             onToggleFavorite: { [weak self] in self?.toggleFavorite($0) },
                             alternatives: { [weak self] row in self?.model.searchIndex.alternatives(forKey: row.usageKey) ?? [] },
                             onInsertVersion: { [weak self] row, version in
                                 if !NSEvent.modifierFlags.contains(.shift) { self?.hide() }
                                 self?.model.insert(uri: version.uri, usageKey: row.usageKey)
                             },
                             onReorder: { [weak self] in self?.reorder(from: $0, to: $1) },
                             onResize: { [weak self] in self?.resize(active: $0) },
                             onOpenSettings: { [weak self] in self?.hide(); self?.onOpenSettings?() })
        panel.contentView = FirstMouseHostingView(rootView: view)
    }

    /// Developer aid: saves what the window shows as a PNG.
    func snapshot(to url: URL) {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    var isVisible: Bool { panel.isVisible }

    func contains(_ point: CGPoint) -> Bool {
        (panel.isVisible && panel.frame.contains(point)) || flyout.contains(point)
    }

    func show(at point: CGPoint) {
        viewModel.state = PanelState(config: model.config, index: model.searchIndex, selectedTab: lastTab, usage: model.usage.counts)
        viewModel.favoritesID = model.config.favoritesID
        viewModel.hovered = nil
        viewModel.drag = nil
        viewModel.page = 0
        if !model.panelOpened { model.panelOpened = true }
        viewModel.size = model.config.panelSize
        if let dev = Dev.env("HM_PANEL_SIZE")?.split(separator: ",").compactMap({ Double($0) }), dev.count == 2 {
            viewModel.size = PanelSize(columnWidth: dev[0], itemHeight: dev[1]) // developer aid
        }
        topLeft = point
        resetFloors()
        layout()
        panel.orderFrontRegardless()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                // Pinned: clicks in Live (another track, a device) keep the panel open.
                guard let self, !NSEvent.modifierFlags.contains(.shift) else { return }
                self.hide()
            }
        }
        viewModel.pinned = NSEvent.modifierFlags.contains(.shift)
        let flags: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.viewModel.pinned = event.modifierFlags.contains(.shift) }
        }
        flagsMonitors = [NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags),
                         NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { flags($0); return $0 }].compactMap { $0 }
    }

    /// The gear in the panel's top-right corner.
    var onOpenSettings: (() -> Void)?

    /// The panel is one 3×3 page at its saved pad size; nothing to work out per category any more.
    private func resetFloors() {}

    // MARK: Resize grip

    private var resizeStart: (mouse: CGPoint, size: PanelSize, columns: Int, rows: Int)?

    /// Width per column follows the horizontal move, entry height the vertical one; saved when let go.
    private func resize(active: Bool) {
        guard active else {
            if resizeStart != nil { model.config.panelSize = viewModel.size }
            resizeStart = nil
            return
        }
        let mouse = NSEvent.mouseLocation
        if resizeStart == nil {
            resizeStart = (mouse, viewModel.size, 1, 3)
        }
        guard let start = resizeStart else { return }
        let dx = mouse.x - start.mouse.x
        let dy = start.mouse.y - mouse.y   // dragging down makes entries taller
        viewModel.size = PanelSize(columnWidth: start.size.columnWidth + Double(dx) / Double(start.columns),
                                   itemHeight: start.size.itemHeight + Double(dy) / Double(start.rows))
        resetFloors()
        layout(animated: false)
    }

    // MARK: Reordering

    /// An entry dragged to a new slot: saved to the category (or the open folder) right away.
    private func reorder(from: Int, to: Int) {
        let state = viewModel.state
        guard state.filter.isEmpty, case .category(let id, _) = state.tabs[state.selectedTab] else { return }
        let folder = state.openFolderID
        model.config.moveEntry(in: id, folder: folder, from: from, to: to)
        var fresh = PanelState(config: model.config, index: model.searchIndex, selectedTab: state.selectedTab, usage: model.usage.counts)
        if let folder { fresh.openFolder(folder) }
        viewModel.state = fresh
        layout()
    }

    private var flagsMonitors: [Any] = []

    func hide() {
        TooltipWindow.shared.cancel()
        flagsMonitors.forEach(NSEvent.removeMonitor)
        flagsMonitors = []
        viewModel.pinned = false
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
        // Beside the folder's whole block, so the list doesn't cover the pads next to the folder.
        _ = index
        let blockMinX = panel.frame.minX + PanelView.gridMinX
        let blockFrame = NSRect(x: blockMinX, y: panel.frame.minY, width: viewModel.columnWidth, height: panel.frame.height)
        let mouse = NSEvent.mouseLocation
        flyout.show(rows: viewModel.state.folderRows(folder),
                    besides: blockFrame, top: mouse.y + PanelView.rowHeight / 2 + PanelView.padding,
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
        // Pinned mode: with ⇧ held the panel stays for the next insert; after letting go, the next one closes it.
        if !NSEvent.modifierFlags.contains(.shift) { hide() }
        model.insert(row)
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
        var state = PanelState(config: model.config, index: model.searchIndex, selectedTab: viewModel.state.selectedTab, usage: model.usage.counts)
        for ch in viewModel.state.filter { _ = state.handle(.character(ch)) }
        viewModel.state = state
        layout()
    }

    /// Always one page of 3×3 pads; the top-left corner stays at the click, clamped to the screen.
    private func layout(animated: Bool = true) {
        let size = PanelView.size(viewModel.size)
        let height = size.height
        let screen = NSScreen.screens.first { $0.frame.contains(topLeft) } ?? NSScreen.main
        var frame = NSRect(x: topLeft.x, y: topLeft.y - height, width: size.width, height: height)
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        guard animated, panel.isVisible, frame != panel.frame else { panel.setFrame(frame, display: true); return }
        // Grows with a short ease-out instead of snapping, so the eye can follow where the new rows appear.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }
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
        label.textColor = NSColor(Palette.current.textPrimary)
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 28, height: 34)
        let p = panel ?? NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(Palette.current.panelSurface).withAlphaComponent(0.97).cgColor
        box.layer?.cornerRadius = 10
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor(Palette.current.panelStroke).cgColor
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
                    Text(Loc.t("Leerer Ordner", "Empty folder")).font(DS.Font.secondary).foregroundColor(DS.textTertiary)
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
        .modifier(PanelChrome())
        .id(Palette.theme)
    }
}
