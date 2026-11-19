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

    // Pads: one 3×3 page at a time; more entries go on further pages.
    static let padSpacing: CGFloat = 6
    /// Between blocks in the Settings editor, side by side and stacked.
    static let blockSpacing: CGFloat = 14
    /// Category name and page dots above the pads.
    static let headerHeight: CGFloat = 30
    /// Strip right of the pads: resting the mouse there turns to the next page.
    static let edgeWidth: CGFloat = 30
    /// Categories down the left side.
    static let categoryWidth: CGFloat = 132
    static let categoryRowHeight: CGFloat = 28
    static let categorySpacing: CGFloat = 2
    /// Category column + the hairline and gap before the pads (also the "previous page" strip).
    static let sidebarGap: CGFloat = 12
    /// How long the mouse rests on a page edge before the page turns, and again for each further page.
    static let edgeDelay: UInt64 = 150_000_000
    static let edgeRepeat: UInt64 = 380_000_000

    /// Pad height for the entry height of the resize grip (34–64 → 72–102).
    static func padHeight(_ size: PanelSize) -> CGFloat { CGFloat(size.itemHeight) + 38 }
    static func padWidth(columnWidth: CGFloat) -> CGFloat { (columnWidth - padSpacing * 2) / 3 }

    /// Height of `padRows` pad rows, with the wider gap after every third row (a new block row).
    static func gridHeight(padRows: Int, padHeight: CGFloat) -> CGFloat {
        let rows = max(padRows, 1)
        let blockRows = (rows + 2) / 3
        return CGFloat(rows) * padHeight + CGFloat(rows - 1) * padSpacing + CGFloat(blockRows - 1) * (blockSpacing - padSpacing)
    }

    /// Left edge of the pads inside the panel window.
    static var gridMinX: CGFloat { padding + categoryWidth + 6 + sidebarGap }
    /// The panel is always one page of 3×3 pads, whatever the category holds.
    static func size(_ panelSize: PanelSize) -> CGSize {
        let width = gridMinX + CGFloat(panelSize.columnWidth) + edgeWidth + padding
        let height = padding * 2 + headerHeight + gridHeight(padRows: 3, padHeight: padHeight(panelSize)) + 6 + footerHeight
        return CGSize(width: width, height: height)
    }
    static var width: CGFloat { size(.default).width }

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

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            categoryColumn
            Rectangle().fill(Color.panelStroke).frame(width: 1)
            edgeStrip(-1).frame(width: Self.sidebarGap - 1)
            VStack(spacing: 0) {
                header
                pagedGrid
                Spacer(minLength: 0)
                footer
            }
            .frame(width: viewModel.columnWidth)
            edgeStrip(1).frame(width: Self.edgeWidth)
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
            if let h, h / 9 != viewModel.page { turn(to: h / 9) }
        }
    }

    private var pageCount: Int { max(1, (viewModel.state.rows.count + 8) / 9) }

    /// Slides to `page` (from the right when moving forward).
    private func turn(to page: Int) {
        let target = min(max(page, 0), pageCount - 1)
        guard target != viewModel.page else { return }
        viewModel.forward = target > viewModel.page
        viewModel.hovered = nil
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.14)) {
            viewModel.page = target
        }
    }

    /// Resting the mouse on the strip right of the pads (or left of them) turns the page, again and again
    /// while it stays there. A chevron shows when there is a page that way.
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
        .onHover { inside in
            edgeTask?.cancel()
            edgeHover = inside ? direction : nil
            guard inside else { return }
            edgeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.edgeDelay)
                while !Task.isCancelled {
                    let next = viewModel.page + direction
                    guard next >= 0, next < pageCount else { return }
                    turn(to: next)
                    try? await Task.sleep(nanoseconds: Self.edgeRepeat)
                }
            }
        }
        .onTapGesture { turn(to: viewModel.page + direction) }
    }

    /// Category name and count (or the open folder, or the search), page dots on the right.
    private var header: some View {
        HStack(spacing: 8) {
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
            } else if !viewModel.state.filter.isEmpty {
                filterField
            } else {
                Text(categoryTitle).font(DS.Font.columnTitle).foregroundColor(DS.textPrimary).lineLimit(1)
                Text("\(viewModel.state.rows.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.textTertiary)
            }
            Spacer(minLength: 4)
            if pageCount > 1 { pageDots }
        }
        .padding(.leading, 2)
        .frame(height: Self.headerHeight - 6)
        .padding(.bottom, 6)
    }

    /// A dot per page (click to go there); with many pages "3 / 12" instead, so the header never overflows.
    @ViewBuilder private var pageDots: some View {
        if pageCount > 7 {
            Text("\(viewModel.page + 1) / \(pageCount)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
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

    /// Bottom line of every category: how to search, or how many hits the search found.
    private var footer: some View {
        let state = viewModel.state
        return HStack(spacing: 6) {
            if viewModel.pinned {
                Image(systemName: "pin.fill").font(.themed(10, .semibold))
                Text(Loc.t("Angeheftet – ⇧ loslassen, dann schließt der nächste Klick", "Pinned – release ⇧ and the next insert closes"))
            } else if state.filter.isEmpty {
                Text(Loc.t("Tippen zum Suchen · ⇧ heftet an", "Type to search · ⇧ pins"))
            } else {
                let n = state.rows.count
                Text(n == 1 ? Loc.t("1 Treffer", "1 result") : Loc.t("\(n) Treffer", "\(n) results"))
            }
            Spacer(minLength: 4)
            Text("HYNE ASM")
        }
        // Small print of a hardware panel: monospaced capitals.
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .textCase(.uppercase)
        .lineLimit(1)
        .foregroundColor(viewModel.pinned ? .accent : DS.textTertiary.opacity(0.8))
        .padding(.leading, 2).padding(.trailing, 8)
        .frame(maxWidth: .infinity, minHeight: Self.footerHeight, maxHeight: Self.footerHeight)
        .allowsHitTesting(false)
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

    // MARK: Categories

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
                // LED: lit (with a glow) on the open category, dark on the others.
                Circle()
                    .fill(selected ? Color.accent : Color.ink.opacity(0.16))
                    .frame(width: 6, height: 6)
                    .shadow(color: selected ? Color.accent.opacity(0.9) : .clear, radius: 4)
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

    /// The current page: 9 slots, empty ones drawn as dark sockets so the grid keeps its shape.
    private var pagedGrid: some View {
        let rows = viewModel.state.rows
        return ZStack(alignment: .topLeading) {
            if rows.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.state.filter.isEmpty ? "tray" : "magnifyingglass")
                    Text(viewModel.state.filter.isEmpty ? Loc.t("Keine Einträge – in den Einstellungen hinzufügen", "No entries – add some in Settings") : Loc.t("Nichts gefunden", "Nothing found"))
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
        .frame(width: viewModel.columnWidth, height: Self.gridHeight(padRows: 3, padHeight: viewModel.padHeight), alignment: .topLeading)
        .clipped()
    }

    /// One page of 3×3 pads; while an entry is dragged, the others on the page make room for it.
    private func page(_ page: Int, rows: [PanelRow]) -> some View {
        let start = page * 9
        let reorderable = viewModel.state.filter.isEmpty
        let order: [Int] = {
            guard reorderable, let d = viewModel.drag else { return Array(0..<rows.count) }
            return PanelGrid.order(count: rows.count, moving: d.from, to: d.to)
        }()
        let padWidth = Self.padWidth(columnWidth: viewModel.columnWidth)
        return VStack(alignment: .leading, spacing: Self.padSpacing) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: Self.padSpacing) {
                    ForEach(0..<3, id: \.self) { c in
                        let slot = start + r * 3 + c
                        if slot < rows.count {
                            let source = order[slot]
                            padView(rows[source], index: slot, source: source, reorderable: reorderable)
                                .frame(width: padWidth)
                        } else {
                            RoundedRectangle(cornerRadius: CGFloat(8).themedRadius)
                                .strokeBorder(Color.ink.opacity(0.05))
                                .frame(width: padWidth, height: viewModel.padHeight)
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
                let padHeight = viewModel.padHeight
                let start = viewModel.page * 9
                let local = PanelGrid.padIndex(atX: value.location.x, y: value.location.y, columns: 1,
                                               blockStride: viewModel.columnWidth + Self.blockSpacing,
                                               padStride: Self.padWidth(columnWidth: viewModel.columnWidth) + Self.padSpacing,
                                               blockRowStride: Self.gridHeight(padRows: 3, padHeight: padHeight) + Self.blockSpacing,
                                               padRowStride: padHeight + Self.padSpacing, count: max(min(count - start, 9), 1))
                let to = start + local
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
        .frame(height: Self.headerHeight - 6)
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

    private func padView(_ row: PanelRow, index: Int, source: Int, reorderable: Bool) -> some View {
        let dragged = reorderable && viewModel.drag?.from == source
        let active = dragged || (viewModel.drag == nil && (viewModel.state.highlighted == index || viewModel.hovered == index))
        return Button { onInsert(row) } label: {
            LauncherPad(number: index % 9, symbol: IconCatalog.symbolName(for: row.iconID), title: row.title,   // keys 1–9 on every page
                        height: viewModel.padHeight,
                        active: active, available: row.isAvailable, color: Color(label: row.colorID)) {
                if row.isNew { NewBadge() }
                if row.folderID != nil {
                    Text("\(row.childCount)")
                        .font(DS.Font.badge.monospacedDigit()).foregroundColor(DS.textSecondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color.ink.opacity(0.09)))
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
