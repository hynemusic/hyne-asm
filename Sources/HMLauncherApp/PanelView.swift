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

    // Pads: each column of 9 entries is a 3×3 block.
    static let padSpacing: CGFloat = 6
    /// Between blocks, side by side and stacked; wider than between pads so each block of 9 reads as one.
    static let blockSpacing: CGFloat = 14
    /// Two block rows; more scroll.
    static let maxVisiblePadRows = 6
    /// Categories down the left side.
    static let categoryWidth: CGFloat = 132
    static let categoryRowHeight: CGFloat = 28
    static let categorySpacing: CGFloat = 2
    /// Category column + the hairline and gap before the pads.
    static let sidebarGap: CGFloat = 9

    /// Pad height for the entry height of the resize grip (34–64 → 72–102).
    static func padHeight(_ size: PanelSize) -> CGFloat { CGFloat(size.itemHeight) + 38 }
    static func padWidth(columnWidth: CGFloat) -> CGFloat { (columnWidth - padSpacing * 2) / 3 }

    /// Height of `padRows` pad rows, with the wider gap after every third row (a new block row).
    static func gridHeight(padRows: Int, padHeight: CGFloat) -> CGFloat {
        let rows = max(padRows, 1)
        let blockRows = (rows + 2) / 3
        return CGFloat(rows) * padHeight + CGFloat(rows - 1) * padSpacing + CGFloat(blockRows - 1) * (blockSpacing - padSpacing)
    }

    /// Height the category column needs to show every category without scrolling.
    static func categoriesHeight(count: Int) -> CGFloat {
        CGFloat(count) * (categoryRowHeight + categorySpacing) + 30
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

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            categoryColumn
            Rectangle().fill(Color.panelStroke).frame(width: 1).padding(.trailing, Self.sidebarGap - 1)
            VStack(spacing: 0) {
                if let folder = viewModel.state.openFolderName {
                    Button(action: onCloseFolder) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.themed(10, .bold)).foregroundColor(DS.textTertiary)
                            Text(categoryTitle).foregroundColor(DS.textTertiary)
                            Text("/").foregroundColor(DS.textTertiary)
                            Image(systemName: "folder.fill").foregroundColor(.accent)
                            Text(folder).fontWeight(.semibold).foregroundColor(DS.textPrimary)
                            Spacer()
                            escHint
                        }
                        .font(DS.Font.body)
                        .frame(height: Self.filterHeight)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Loc.t("Zurück (Esc)", "Back (Esc)"))
                }
                if !viewModel.state.filter.isEmpty { filterField }
                padList
                Spacer(minLength: 0)
                footer
            }
        }
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        .padding(Self.padding)
        .modifier(PanelChrome())
        .id(Palette.theme)
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
            Spacer(minLength: 0)
        }
        // Small print of a hardware panel: monospaced capitals.
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .textCase(.uppercase)
        .lineLimit(1)
        .foregroundColor(viewModel.pinned ? .accent : DS.textTertiary.opacity(0.8))
        .padding(.leading, 2).padding(.trailing, 24)
        .frame(maxWidth: .infinity, minHeight: Self.footerHeight, maxHeight: Self.footerHeight)
        .allowsHitTesting(false)
    }

    /// Bottom-right corner: drag to make the entries wider or taller (saved).
    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.themed(9.5, .semibold))
            .foregroundColor(DS.textTertiary.opacity(0.8))
            .frame(width: 22, height: Self.footerHeight)
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

    private var padList: some View {
        let rows = viewModel.state.rows
        let firstGlobal = rows.firstIndex(where: \.isGlobal) ?? rows.count
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {   // a scroll bar would push the blocks wider than the panel; the cut-off row shows there is more
                VStack(alignment: .leading, spacing: Self.blockSpacing) {
                    if rows.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: viewModel.state.filter.isEmpty ? "tray" : "magnifyingglass")
                            Text(viewModel.state.filter.isEmpty ? Loc.t("Keine Einträge – in den Einstellungen hinzufügen", "No entries – add some in Settings") : Loc.t("Nichts gefunden", "Nothing found"))
                        }
                        .font(DS.Font.secondary).foregroundColor(DS.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: viewModel.padHeight)
                    }
                    // Blocks of 9 (left first), category hits and "All plugins" hits as separate grids.
                    if firstGlobal > 0 { grid(rows, 0..<firstGlobal, reorderable: viewModel.state.filter.isEmpty) }
                    if firstGlobal < rows.count {
                        VStack(spacing: 0) {
                            globalHeader
                            grid(rows, firstGlobal..<rows.count, reorderable: false)
                        }
                    }
                }
            }
            .onChange(of: viewModel.state.highlighted) { h in
                if let h { proxy.scrollTo(h) }
            }
        }
    }

    static let globalHeaderHeight: CGFloat = 26
    static var width: CGFloat { width(columns: PanelGrid.columns, columnWidth: PanelSize.default.columnWidth) }
    /// Category column plus one block per 9 entries, up to the setting (`PanelGrid.columnsNeeded`).
    static func width(columns: Int, columnWidth: Double) -> CGFloat {
        categoryWidth + 6 + sidebarGap + CGFloat(columnWidth) * CGFloat(columns) + blockSpacing * CGFloat(columns - 1) + padding * 2
    }

    /// Blocks of 3×3 pads; while an entry is dragged, the others make room for it.
    private func grid(_ rows: [PanelRow], _ range: Range<Int>, reorderable: Bool) -> some View {
        let order: [Int] = {
            guard reorderable, let d = viewModel.drag else { return Array(0..<rows.count) }
            return PanelGrid.order(count: range.count, moving: d.from, to: d.to)
        }()
        let padWidth = Self.padWidth(columnWidth: viewModel.columnWidth)
        return VStack(alignment: .leading, spacing: Self.blockSpacing) {
            ForEach(Array(PanelGrid.blocks(range, columns: viewModel.columns).enumerated()), id: \.offset) { _, blockRow in
                HStack(alignment: .top, spacing: Self.blockSpacing) {
                    // Empty blocks are left out, so a short category stays one block wide.
                    ForEach(Array(blockRow.filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, block in
                        VStack(alignment: .leading, spacing: Self.padSpacing) {
                            ForEach(Array(stride(from: 0, to: block.count, by: PanelGrid.padsPerRow)), id: \.self) { start in
                                HStack(spacing: Self.padSpacing) {
                                    ForEach(block[start..<min(start + PanelGrid.padsPerRow, block.count)], id: \.self) { slot in
                                        let source = order[slot]
                                        padView(rows[source], index: slot, source: source, reorderable: reorderable)
                                            .frame(width: padWidth)
                                            .id(slot)
                                    }
                                }
                            }
                        }
                        .frame(width: viewModel.columnWidth, alignment: .topLeading)
                    }
                }
            }
        }
        .coordinateSpace(name: reorderable ? Self.reorderSpace : "grid-\(range.lowerBound)")
        .frame(maxWidth: .infinity, alignment: .leading)   // a one-block section sits left in a wider panel
        .animation(.easeOut(duration: 0.12), value: viewModel.drag?.to)
    }

    private static let reorderSpace = "panelReorder"

    /// Long enough a move to be a drag, not a click; the slot follows the pointer.
    private func reorderGesture(source: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.reorderSpace))
            .onChanged { value in
                let padHeight = viewModel.padHeight
                let to = PanelGrid.padIndex(atX: value.location.x, y: value.location.y, columns: viewModel.columns,
                                            blockStride: viewModel.columnWidth + Self.blockSpacing,
                                            padStride: Self.padWidth(columnWidth: viewModel.columnWidth) + Self.padSpacing,
                                            blockRowStride: Self.gridHeight(padRows: 3, padHeight: padHeight) + Self.blockSpacing,
                                            padRowStride: padHeight + Self.padSpacing, count: count)
                let from = viewModel.drag?.from ?? source
                if viewModel.drag?.from != from || viewModel.drag?.to != to { viewModel.drag = (from, to) }
            }
            .onEnded { _ in
                if let d = viewModel.drag, d.from != d.to { onReorder(d.from, d.to) }
                viewModel.drag = nil
            }
    }

    private var globalHeader: some View {
        HStack(spacing: 8) {
            SectionLabel(text: Loc.t("Alle Plugins & Presets", "All plugins & presets"))
            Rectangle().fill(Color.panelStroke).frame(height: 1)
        }
        .padding(.horizontal, 4)
        .frame(height: Self.globalHeaderHeight)
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
        .frame(height: Self.filterHeight - 4)
        .background(RoundedRectangle(cornerRadius: CGFloat(7).themedRadius).fill(Color.ink.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: CGFloat(7).themedRadius).strokeBorder(Color.panelStroke))
        .padding(.vertical, 2)
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
            LauncherPad(number: index, symbol: IconCatalog.symbolName(for: row.iconID), title: row.title,
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
