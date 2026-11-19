import SwiftUI
import HMLauncherCore

struct PanelView: View {
    /// Row height of the list windows beside the panel (quick search, folder side list).
    static let rowHeight: CGFloat = 46
    static let filterHeight: CGFloat = 28
    static let padding: CGFloat = 8
    /// Rows of the list windows; more scroll.
    static let maxVisibleRows = PanelGrid.rowsPerColumn
    static let footerHeight: CGFloat = 22

    // Pads: one page (columns × rows, set in Settings) at a time; more entries go on further pages.
    static let padSpacing: CGFloat = 6
    /// Between pages in the Settings editor.
    static let blockSpacing: CGFloat = 14
    /// Category name (or count) and page dots above the pads.
    static let headerHeight: CGFloat = 30
    /// Category tabs on top (when categories sit on top).
    static let tabBarHeight: CGFloat = 34
    /// Strip right of the pads: a swipe into it or resting there turns to the next page.
    static let edgeWidth: CGFloat = 30
    /// Categories down the left side (when categories sit on the left).
    static let categoryWidth: CGFloat = 132
    static let categoryRowHeight: CGFloat = 28
    static let categorySpacing: CGFloat = 2
    /// Strip left of the pads ("previous page"); with the left column it includes the hairline.
    static let sidebarGap: CGFloat = 12
    /// How long the mouse rests on a page edge before the page turns, and again for each further page.
    static let edgeDelay: UInt64 = 150_000_000
    static let edgeRepeat: UInt64 = 380_000_000

    /// Pad height for the entry height of the resize grip (34–64 → 72–102).
    static func padHeight(_ size: PanelSize) -> CGFloat { CGFloat(size.itemHeight) + 38 }
    /// `columnWidth` of the resize grip is the width of three pads.
    static func padWidth(columnWidth: CGFloat) -> CGFloat { (columnWidth - padSpacing * 2) / 3 }

    /// Height of `padRows` pad rows, with the wider gap after every third row (Settings editor blocks).
    static func gridHeight(padRows: Int, padHeight: CGFloat) -> CGFloat {
        let rows = max(padRows, 1)
        let blockRows = (rows + 2) / 3
        return CGFloat(rows) * padHeight + CGFloat(rows - 1) * padSpacing + CGFloat(blockRows - 1) * (blockSpacing - padSpacing)
    }


    /// Left edge of the pads inside the panel content (after the padding) and inside the window.
    static func gridStart(_ placement: CategoryPlacement) -> CGFloat {
        (placement == .left ? categoryWidth + 6 : 0) + sidebarGap
    }
    static func gridMinX(_ placement: CategoryPlacement) -> CGFloat { padding + gridStart(placement) }
    /// From the window's top edge to the first pad row.
    static func gridTopInset(_ placement: CategoryPlacement) -> CGFloat {
        padding + (placement == .top ? tabBarHeight : headerHeight)
    }

    /// The panel is always one page, whatever the category holds.
    static func size(_ metrics: PageMetrics, placement: CategoryPlacement) -> CGSize {
        let width = gridMinX(placement) + metrics.width + edgeWidth + padding
        let height = gridTopInset(placement) + metrics.height + 6 + footerHeight + padding
        return CGSize(width: width, height: height)
    }
    static var width: CGFloat {
        size(PageMetrics(style: .grid, page: PanelPage(columns: 3, rows: 3, columnMajor: false), size: .default), placement: .top).width
    }

    @ObservedObject var viewModel: PanelViewModel
    let onInsert: (PanelRow) -> Void
    let onCloseFolder: () -> Void
    /// Hovering a row: folders open their side list, other rows close it.
    var onHoverRow: (PanelRow) -> Void = { _ in }
    let onSelectTab: (Int) -> Void
    let isFavorite: (PanelRow) -> Bool
    let onToggleFavorite: (PanelRow) -> Void
    /// Other versions of the row's plugin (Mono, other formats) and how to insert one.
    var alternatives: (PanelRow) -> [PluginItem] = { _ in [] }
    var onInsertVersion: (PanelRow, PluginItem) -> Void = { _, _ in }
    /// Entry `from` dropped on slot `to` (category or open folder, no search active).
    var onReorder: (Int, Int) -> Void = { _, _ in }
    /// Resize grip: true while dragging, false when let go.
    var onResize: (Bool) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}

    @State private var edgeTask: Task<Void, Never>?
    @State private var edgeHover: Int? = nil   // -1 left strip, 1 right strip
    @State private var lastPointer: (x: CGFloat, time: TimeInterval)?
    /// Pointer speed into the right strip that counts as a swipe (points per second).
    static let swipeSpeed: CGFloat = 350

    /// Which page strip a point of the panel's content (inside the padding) is in.
    private func edgeZone(_ x: CGFloat) -> Int? {
        let gridStart = Self.gridStart(viewModel.placement)
        let leftStart = gridStart - Self.sidebarGap + (viewModel.placement == .left ? 1 : 0)
        let gridEnd = gridStart + viewModel.metrics.width
        if x >= gridEnd { return 1 }
        if x >= leftStart && x < gridStart { return -1 }
        return nil
    }

    /// Swiping the pointer into the right strip turns the page at once; resting on a strip turns it after a
    /// moment and keeps turning while the pointer stays.
    private func edgeTracking(_ phase: HoverPhase) {
        switch phase {
        case .active(let point):
            let now = ProcessInfo.processInfo.systemUptime
            let zone = edgeZone(point.x)
            let previous = lastPointer.flatMap { edgeZone($0.x) }
            if zone != previous {
                edgeTask?.cancel()
                edgeHover = zone
                if let zone {
                    var swiped = false
                    if zone == 1, let last = lastPointer, now - last.time < 0.2,
                       (point.x - last.x) / CGFloat(max(now - last.time, 0.001)) > Self.swipeSpeed {
                        turn(to: viewModel.page + 1)
                        swiped = true
                    }
                    dwell(zone, first: swiped ? Self.edgeRepeat : Self.edgeDelay)
                }
            }
            lastPointer = (point.x, now)
        case .ended:
            edgeTask?.cancel()
            edgeHover = nil
            lastPointer = nil
        }
    }

    private func dwell(_ direction: Int, first: UInt64) {
        edgeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: first)
            while !Task.isCancelled {
                let next = viewModel.page + direction
                guard next >= 0, next < pageCount else { return }
                turn(to: next)
                try? await Task.sleep(nanoseconds: Self.edgeRepeat)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.placement == .top { topRow }
            HStack(alignment: .top, spacing: 0) {
                if viewModel.placement == .left {
                    categoryColumn
                    Rectangle().fill(Color.panelStroke).frame(width: 1)
                }
                edgeStrip(-1).frame(width: Self.sidebarGap - (viewModel.placement == .left ? 1 : 0))
                VStack(spacing: 0) {
                    if viewModel.placement == .left { header }
                    pagedGrid
                    Spacer(minLength: 0)
                    footer
                }
                .frame(width: viewModel.metrics.width)
                edgeStrip(1).frame(width: Self.edgeWidth)
            }
            .onContinuousHover(coordinateSpace: .local) { edgeTracking($0) }
        }
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        .padding(Self.padding)
        .modifier(PanelChrome(radius: 14 * Palette.current.radiusScale))
        .id(Palette.theme)
        .onChange(of: viewModel.state.selectedTab) { _ in viewModel.page = 0 }
        .onChange(of: viewModel.state.filter) { _ in viewModel.page = 0 }
        .onChange(of: viewModel.state.openFolderID) { _ in viewModel.page = 0 }
        .onChange(of: viewModel.state.highlighted) { h in
            // The keyboard highlight brings its page into view.
            let size = viewModel.metrics.page.size
            if let h, h / size != viewModel.page { turn(to: h / size) }
        }
    }

    private var pageCount: Int { viewModel.pageCount }
    private func turn(to page: Int) { viewModel.turn(to: page) }

    /// Strips right and left of the pads; a chevron shows when there is a page that way. What the pointer does
    /// there is handled by `edgeTracking` on the whole panel.
    private func edgeStrip(_ direction: Int) -> some View {
        let possible = direction > 0 ? viewModel.page < pageCount - 1 : viewModel.page > 0
        return ZStack {
            if possible {
                Image(systemName: direction > 0 ? "chevron.compact.right" : "chevron.compact.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(edgeHover == direction ? .accent : DS.textTertiary.opacity(0.55))
                    .shadow(color: edgeHover == direction ? Color.accent.opacity(0.8) : .clear, radius: 5)
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { turn(to: viewModel.page + direction) }
    }

    /// Categories on top: the tabs, or while searching the search field, or an open folder.
    @ViewBuilder private var topRow: some View {
        if viewModel.state.openFolderName != nil || !viewModel.state.filter.isEmpty {
            HStack(spacing: 8) { searchOrFolder }
                .frame(height: Self.tabBarHeight - 8)
                .padding(.bottom, 8)
        } else {
            tabBar
        }
    }

    /// Categories on the left: the category's name and count, or the search, or an open folder.
    private var header: some View {
        HStack(spacing: 8) {
            if viewModel.state.openFolderName != nil || !viewModel.state.filter.isEmpty {
                searchOrFolder
            } else {
                Text(categoryTitle).font(DS.Font.columnTitle).foregroundColor(DS.textPrimary).lineLimit(1)
                Text("\(viewModel.state.rows.count)").font(DS.Font.numeric).foregroundColor(DS.textTertiary)
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 2)
        .frame(height: Self.headerHeight - 6)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var searchOrFolder: some View {
        if let folder = viewModel.state.openFolderName {
            Button(action: onCloseFolder) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.themed(10, .bold)).foregroundColor(DS.textTertiary)
                    Image(systemName: "folder.fill").foregroundColor(.accent)
                    Text(folder).fontWeight(.semibold).foregroundColor(DS.textPrimary).lineLimit(1)
                }
                .font(DS.Font.body)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Loc.t("Zurück zu \(categoryTitle) (Esc)", "Back to \(categoryTitle) (Esc)"))
            Spacer(minLength: 0)
            escHint
        } else {
            filterField
        }
    }

    /// A dot per page (click to go there); with many pages "3 / 12" instead, so the header never overflows.
    @ViewBuilder private var pageDots: some View {
        if pageCount > 7 {
            Text("\(viewModel.page + 1) / \(pageCount)")
                .font(DS.Font.numeric)
                .foregroundColor(DS.textSecondary)
        } else {
            dotRow
        }
    }

    private var dotRow: some View {
        HStack(spacing: 5) {
            ForEach(0..<pageCount, id: \.self) { p in
                Button { turn(to: p) } label: {
                    Capsule()
                        .fill(p == viewModel.page ? DS.textPrimary : Palette.current.padStripe)
                        .frame(width: 16, height: 6)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Loc.t("Seite \(p + 1)", "Page \(p + 1)"))
            }
        }
    }

    /// Bottom line: what typing does (or that the panel is pinned, or how many hits), page dots on the right.
    private var footer: some View {
        let state = viewModel.state
        return HStack(spacing: 6) {
            Group {
                if viewModel.pinned {
                    Label(Loc.t("Angeheftet, nach dem nächsten Einfügen ⇧ loslassen", "Pinned. Let go of ⇧ to close after the next insert"),
                          systemImage: "pin.fill")
                } else if state.filter.isEmpty {
                    Text(Loc.t("Tippen zum Suchen", "Type to search"))
                } else {
                    let n = state.rows.count
                    Text(n == 1 ? Loc.t("1 Treffer", "1 result") : Loc.t("\(n) Treffer", "\(n) results"))
                }
            }
            .font(DS.Font.caption)
            .foregroundColor(viewModel.pinned ? .accent : DS.textTertiary)
            .lineLimit(1)
            .allowsHitTesting(false)
            Spacer(minLength: 6)
            if pageCount > 1 { pageDots }
        }
        .padding(.leading, 2).padding(.trailing, 4)
        .frame(maxWidth: .infinity, minHeight: Self.footerHeight, maxHeight: Self.footerHeight)
    }

    /// Bottom-right corner: drag to make the entries wider or taller (saved).
    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.themed(9.5, .semibold))
            .foregroundColor(DS.textTertiary.opacity(0.8))
            .frame(width: Self.edgeWidth + 6, height: Self.footerHeight)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in onResize(true) }
                .onEnded { _ in onResize(false) })
            .tooltip(Loc.t("Größe ändern", "Resize entries"))
    }

    // MARK: Categories on top

    /// Up to `limit` tabs, the selected one always among them.
    private func visibleTabIndices(_ limit: Int) -> [Int] {
        let count = viewModel.state.tabs.count
        var shown = Array(0..<min(limit, count))
        let sel = viewModel.state.selectedTab
        if !shown.isEmpty, !shown.contains(sel) { shown[shown.count - 1] = sel }
        return shown
    }

    /// As many tabs as fit the panel's width; the rest go into the "⋯" menu. Settings on the right.
    private var tabBar: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: max(viewModel.state.tabs.count, 1), through: 1, by: -1)), id: \.self) { n in
                tabRow(visibleTabIndices(n))
            }
        }
        .frame(height: Self.tabBarHeight - 8)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.panelStroke).frame(height: 1).padding(.bottom, 3) }
    }

    private func tabRow(_ shown: [Int]) -> some View {
        HStack(spacing: 2) {
            ForEach(shown, id: \.self) { i in tabButton(i) }
            Spacer(minLength: 0)
            let hidden = viewModel.state.tabs.indices.filter { !shown.contains($0) }
            if !hidden.isEmpty {
                Menu {
                    ForEach(hidden, id: \.self) { i in Button(title(of: i)) { onSelectTab(i) } }
                } label: {
                    Image(systemName: "ellipsis").font(.themed(12, .semibold)).foregroundColor(DS.textSecondary)
                        .frame(width: 26, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .tooltip(Loc.t("Weitere Kategorien", "More categories"))
            }
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape").font(.themed(12, .medium)).foregroundColor(DS.textTertiary)
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(HoverHighlight())
            .tooltip(Loc.t("Einstellungen öffnen", "Open Settings"))
        }
    }

    private func tabButton(_ index: Int) -> some View {
        let selected = index == viewModel.state.selectedTab
        return Button { onSelectTab(index) } label: {
            HStack(spacing: 6) {
                led(selected)
                if case .category(let id, _) = viewModel.state.tabs[index], viewModel.isFavorites(id) {
                    Image(systemName: "star.fill").font(.themed(9.5)).foregroundColor(selected ? .accent : DS.textTertiary)
                }
                Text(title(of: index))
                    .font(selected ? DS.Font.columnTitle : DS.Font.bodyStrong)
                    .foregroundColor(selected ? DS.textPrimary : DS.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: CGFloat(6).themedRadius).fill(selected ? Color.ink.opacity(0.06) : .clear))
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Moving over a category is enough to switch to it.
        .onHover { inside in if inside && !selected { onSelectTab(index) } }
    }

    /// LED: lit (with a glow) on the open category, dark on the others.
    private func led(_ on: Bool) -> some View {
        Circle()
            .fill(on ? Color.accent : Color.ink.opacity(0.16))
            .frame(width: 6, height: 6)
            .shadow(color: on ? Color.accent.opacity(0.9) : .clear, radius: 4)
    }

    // MARK: Categories on the left

    /// Every category down the left side (scrolls when there are many), settings at the bottom.
    private var categoryColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Self.categorySpacing) {
                    ForEach(viewModel.state.tabs.indices, id: \.self) { i in categoryButton(i) }
                }
            }
            Spacer(minLength: 4)
            Button(action: onOpenSettings) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape").font(.themed(12, .medium))
                    Text(Loc.t("Einstellungen", "Settings")).font(DS.Font.caption)
                }
                .foregroundColor(DS.textTertiary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(HoverHighlight())
            .tooltip(Loc.t("Einstellungen öffnen", "Open Settings"))
        }
        .frame(width: Self.categoryWidth)
        .padding(.trailing, 6)
        .layoutPriority(1)
    }

    private func title(of index: Int) -> String {
        switch viewModel.state.tabs[index] {
        case .category(_, let name): return name
        }
    }

    private func categoryButton(_ index: Int) -> some View {
        let selected = index == viewModel.state.selectedTab
        return Button { onSelectTab(index) } label: {
            HStack(spacing: 8) {
                led(selected)
                if case .category(let id, _) = viewModel.state.tabs[index], viewModel.isFavorites(id) {
                    Image(systemName: "star.fill").font(.themed(9.5)).foregroundColor(selected ? .accent : DS.textTertiary)
                }
                Text(title(of: index))
                    .font(selected ? DS.Font.columnTitle : DS.Font.bodyStrong)
                    .foregroundColor(selected ? DS.textPrimary : DS.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.categoryRowHeight)
            .background(RoundedRectangle(cornerRadius: CGFloat(6).themedRadius).fill(selected ? Color.ink.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title(of: index))   // long names are cut off in the narrow column
        // Moving over a category is enough to switch to it.
        .onHover { inside in if inside && !selected { onSelectTab(index) } }
    }

    // MARK: Pads

    /// The current page: columns × rows slots, empty ones drawn as dark sockets so the grid keeps its shape.
    private var pagedGrid: some View {
        let rows = viewModel.state.rows
        return ZStack(alignment: .topLeading) {
            if rows.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.state.filter.isEmpty ? "tray" : "magnifyingglass")
                    Text(viewModel.state.filter.isEmpty ? Loc.t("Noch keine Einträge. Füg welche in den Einstellungen hinzu.", "No entries yet. Add some in Settings.") : Loc.t("Nichts gefunden", "Nothing found"))
                }
                .font(DS.Font.secondary).foregroundColor(DS.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                page(viewModel.page, rows: rows)
                    .id(viewModel.page)
                    .transition(.asymmetric(
                        insertion: .move(edge: viewModel.forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: viewModel.forward ? .leading : .trailing).combined(with: .opacity)))
            }
        }
        .frame(width: viewModel.metrics.width, height: viewModel.metrics.height, alignment: .topLeading)
        .clipped()
    }

    /// One page of pads; while an entry is dragged, the others on the page make room for it.
    private func page(_ page: Int, rows: [PanelRow]) -> some View {
        let m = viewModel.metrics
        let start = page * m.page.size
        let reorderable = viewModel.state.filter.isEmpty
        let order: [Int] = {
            guard reorderable, let d = viewModel.drag else { return Array(0..<rows.count) }
            return PanelGrid.order(count: rows.count, moving: d.from, to: d.to)
        }()
        return VStack(alignment: .leading, spacing: m.vSpacing) {
            ForEach(0..<m.page.rows, id: \.self) { r in
                HStack(spacing: m.hSpacing) {
                    ForEach(0..<m.page.columns, id: \.self) { c in
                        let slot = start + m.page.slot(row: r, column: c)
                        if slot < rows.count {
                            let source = order[slot]
                            padView(rows[source], index: slot, source: source, reorderable: reorderable)
                                .frame(width: m.itemWidth)
                        } else {
                            RoundedRectangle(cornerRadius: CGFloat(8).themedRadius)
                                .strokeBorder(Color.ink.opacity(0.05))
                                .frame(width: m.itemWidth, height: m.itemHeight)
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: Self.reorderSpace)
        .animation(.easeOut(duration: 0.12), value: viewModel.drag?.to)
    }

    private static let reorderSpace = "panelReorder"

    /// Long enough a move to be a drag, not a click; the slot follows the pointer.
    private func reorderGesture(source: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.reorderSpace))
            .onChanged { value in
                // Slots of the current page; the page's first entry is the offset.
                let m = viewModel.metrics
                let start = viewModel.page * m.page.size
                let col = min(max(Int(value.location.x / (m.itemWidth + m.hSpacing)), 0), m.page.columns - 1)
                let row = min(max(Int(value.location.y / (m.itemHeight + m.vSpacing)), 0), m.page.rows - 1)
                let to = min(start + m.page.slot(row: row, column: col), max(count - 1, 0))
                let from = viewModel.drag?.from ?? source
                if viewModel.drag?.from != from || viewModel.drag?.to != to { viewModel.drag = (from, to) }
            }
            .onEnded { _ in
                if let d = viewModel.drag, d.from != d.to { onReorder(d.from, d.to) }
                viewModel.drag = nil
            }
    }

    /// What has been typed so far, drawn like a search field. Height = `filterHeight`.
    private var filterField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.themed(11, .semibold)).foregroundColor(.accent)
            HStack(spacing: 1) {
                Text(viewModel.state.filter).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                    .modifier(SelectedText(isSelected: viewModel.state.isFilterSelected))
                if !viewModel.state.isFilterSelected { TextCaret(height: 15) }
            }
            Spacer()
            escHint
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: CGFloat(7).themedRadius).fill(Color.ink.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: CGFloat(7).themedRadius).strokeBorder(Color.panelStroke))
    }

    private var escHint: some View {
        Text("esc")
            .font(DS.Font.badge)
            .foregroundColor(DS.textTertiary)
            .padding(.horizontal, 5).frame(height: 15)
            .background(RoundedRectangle(cornerRadius: CGFloat(4).themedRadius).strokeBorder(Color.panelStroke))
    }

    private var categoryTitle: String {
        if case .category(_, let name) = viewModel.state.tabs[viewModel.state.selectedTab] { return name }
        return ""
    }

    @ViewBuilder private func badges(_ row: PanelRow) -> some View {
        if row.isNew { NewBadge() }
        if row.folderID != nil {
            Text("\(row.childCount)")
                .font(DS.Font.badge.monospacedDigit()).foregroundColor(DS.textSecondary)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(Color.ink.opacity(0.09)))
        }
    }

    private func padView(_ row: PanelRow, index: Int, source: Int, reorderable: Bool) -> some View {
        let dragged = reorderable && viewModel.drag?.from == source
        let active = dragged || (viewModel.drag == nil && (viewModel.state.highlighted == index || viewModel.hovered == index))
        let number = index % viewModel.metrics.page.size   // keys 1–9 on every page
        // Folders stand out in the accent (orange) unless they have their own color label.
        let color = Color(label: row.colorID) ?? (row.folderID != nil ? Color.accent : nil)
        let symbol = IconCatalog.symbolName(for: row.iconID)
        return Button { onInsert(row) } label: {
            Group {
                if viewModel.style == .grid {
                    LauncherPad(number: number, symbol: symbol, title: row.title, height: viewModel.metrics.itemHeight,
                                active: active, available: row.isAvailable, color: color) { badges(row) }
                } else {
                    LauncherListRow(number: number, symbol: symbol, title: row.title, height: viewModel.metrics.itemHeight,
                                    active: active, available: row.isAvailable, color: color) { badges(row) }
                }
            }
            .opacity(row.isAvailable ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .scaleEffect(dragged ? 1.02 : 1)
        .shadow(color: .black.opacity(dragged ? 0.35 : 0), radius: 6, y: 2)
        .zIndex(dragged ? 1 : 0)
        .highPriorityGesture(reorderable ? reorderGesture(source: source, count: viewModel.state.rows.count) : nil)
        .onHover { inside in
            guard viewModel.drag == nil else { return }
            if inside { viewModel.hovered = index; onHoverRow(row) } else if viewModel.hovered == index { viewModel.hovered = nil }
        }
        .contextMenu {
            if row.folderID == nil {
                Button(isFavorite(row) ? Loc.t("Aus Favoriten entfernen", "Remove from Favorites") : Loc.t("Zu Favoriten hinzufügen", "Add to Favorites")) { onToggleFavorite(row) }
                let others = alternatives(row)
                if !others.isEmpty {
                    Divider()
                    ForEach(others, id: \.uri) { v in
                        Button(Loc.t("Als \(PluginVariants.label(v)) einfügen", "Insert as \(PluginVariants.label(v))")) { onInsertVersion(row, v) }
                    }
                }
            }
        }
        .help(row.isAvailable ? row.path.joined(separator: " / ") : Loc.t("Nicht mehr in Live gefunden", "No longer found in Live"))
    }
}

/// Sizes of one page of the panel for its style: square pads in a grid, or rows of a list.
/// `PanelSize.columnWidth` is three pads wide in the grid and one row wide in the list.
struct PageMetrics {
    let style: PanelStyle
    let page: PanelPage
    let size: PanelSize

    var itemWidth: CGFloat {
        style == .grid ? PanelView.padWidth(columnWidth: CGFloat(size.columnWidth)) : CGFloat(size.columnWidth)
    }
    var itemHeight: CGFloat { style == .grid ? PanelView.padHeight(size) : CGFloat(size.itemHeight) }
    var hSpacing: CGFloat { PanelView.padSpacing }
    var vSpacing: CGFloat { style == .grid ? PanelView.padSpacing : 4 }
    var width: CGFloat { CGFloat(page.columns) * itemWidth + CGFloat(page.columns - 1) * hSpacing }
    var height: CGFloat { CGFloat(page.rows) * itemHeight + CGFloat(page.rows - 1) * vSpacing }

    /// An entry's frame inside the page (origin top left).
    func frame(ofSlot slot: Int) -> CGRect {
        let p = page.position(of: slot)
        return CGRect(x: CGFloat(p.column) * (itemWidth + hSpacing), y: CGFloat(p.row) * (itemHeight + vSpacing),
                      width: itemWidth, height: itemHeight)
    }
}
