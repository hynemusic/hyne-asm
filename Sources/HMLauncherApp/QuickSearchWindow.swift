import AppKit
import SwiftUI
import HMLauncherCore

/// The ⌃Space search window: a rounded field in the middle of the screen, results below.
/// Like the panel it never takes focus from Live — keys arrive through the event tap.
@MainActor
final class QuickSearchWindowController {
    static let width: CGFloat = 620
    static let fieldHeight: CGFloat = 58
    static let visibleResults = 8

    private let model: AppModel
    private let panel: NSPanel
    private let viewModel = QuickSearchViewModel()
    private var outsideClickMonitor: Any?

    init(model: AppModel) {
        self.model = model
        panel = QuickSearchPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.fieldHeight),
                                 styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = QuickSearchHostingView(rootView: QuickSearchView(
            viewModel: viewModel,
            onInsert: { [weak self] in self?.insert($0) },
            onHover: { [weak self] in self?.viewModel.state?.highlight($0) }))
    }

    /// Developer aid: saves what the window shows as a PNG.
    func snapshot(to url: URL) {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    var isVisible: Bool { panel.isVisible }

    func contains(_ point: CGPoint) -> Bool { panel.isVisible && panel.frame.contains(point) }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        viewModel.state = QuickSearchState(search: QuickSearch(config: model.config, index: model.searchIndex,
                                                               usage: model.usage.counts))
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

    /// Every key belongs to the window while it is open.
    func handle(_ key: PanelKey) -> Bool {
        guard var state = viewModel.state else { return false }
        let action = state.handle(key)
        viewModel.state = state
        switch action {
        case .none: layout()
        case .close: hide()
        case .insert(let row): insert(row)
        }
        return true
    }

    private func insert(_ row: PanelRow) {
        guard row.isAvailable else { return }
        hide()
        model.insert(row)
    }

    /// Centered horizontally on the screen with the mouse, a quarter from the top; grows downwards with results.
    private func layout() {
        let count = viewModel.state?.results.count ?? 0
        let list = count == 0 ? 0 : CGFloat(min(count, Self.visibleResults)) * PanelView.rowHeight + PanelView.padding * 2 + 1
        let height = Self.fieldHeight + list
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let top = visible.maxY - visible.height * 0.22
        panel.setFrame(NSRect(x: visible.midX - Self.width / 2, y: top - height, width: Self.width, height: height), display: true)
    }
}

private final class QuickSearchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class QuickSearchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class QuickSearchViewModel: ObservableObject {
    @Published var state: QuickSearchState?
}

private struct QuickSearchView: View {
    @ObservedObject var viewModel: QuickSearchViewModel
    let onInsert: (PanelRow) -> Void
    let onHover: (Int) -> Void

    var body: some View {
        let state = viewModel.state
        let typing = !(state?.query ?? "").isEmpty
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.themed(18, .semibold))
                    .foregroundColor(typing ? .accent : DS.textTertiary)
                HStack(spacing: 1) {
                    if let q = state?.query, !q.isEmpty {
                        Text(q).font(DS.Font.field).foregroundColor(DS.textPrimary)
                            .modifier(SelectedText(isSelected: state?.isQuerySelected ?? false))
                        if !(state?.isQuerySelected ?? false) { TextCaret(height: 26) }
                    } else {
                        // Caret before the placeholder, like a real empty field.
                        TextCaret(height: 26)
                        Text(Loc.t("Plugins und Presets suchen …", "Search plugins and presets …"))
                            .font(DS.Font.field).foregroundColor(DS.textTertiary)
                    }
                }
                Spacer()
                keyHint("↩", Loc.t("einfügen", "insert"))
                keyHint("esc", Loc.t("schließen", "close"))
            }
            .padding(.horizontal, 18)
            .frame(height: QuickSearchWindowController.fieldHeight)
            if let results = state?.results, !results.isEmpty {
                Rectangle().fill(Color.panelStroke).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: results.count > QuickSearchWindowController.visibleResults) {
                        VStack(spacing: 4) {
                            ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                                row(result, index: index, highlighted: index == state?.highlighted).id(index)
                            }
                        }
                        .padding(PanelView.padding)
                    }
                    .onChange(of: state?.highlighted) { h in if let h { proxy.scrollTo(h) } }
                }
            }
        }
        .modifier(PanelChrome(radius: 16 * Palette.current.radiusScale))
        .id(Palette.theme)
    }

    private func keyHint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(DS.Font.keycap)
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 18)
                .background(RoundedRectangle(cornerRadius: CGFloat(5).themedRadius).fill(Color.ink.opacity(0.07)))
            Text(text).font(DS.Font.caption).foregroundColor(DS.textTertiary)
        }
    }

    private func row(_ result: QuickResult, index: Int, highlighted: Bool) -> some View {
        let r = result.row
        return Button { onInsert(r) } label: {
            LauncherRow(number: nil, symbol: IconCatalog.symbolName(for: r.iconID), title: r.title,
                        subtitle: result.place ?? Loc.t("Alle Plugins", "All plugins") + " · " + PluginGrouping.formatLabel(
                            PluginItem(uri: r.uri, name: r.name, source: r.source, path: r.path)),
                        active: highlighted, available: r.isAvailable, color: Color(label: r.colorID)) {
                if r.isNew { NewBadge() }
                if highlighted {
                    Text("↩")
                        .font(DS.Font.keycap).foregroundColor(.onAccent)
                        .frame(width: 22, height: 20)
                        .background(RoundedRectangle(cornerRadius: CGFloat(5).themedRadius).fill(Color.accent))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { if $0 { onHover(index) } }
    }
}
