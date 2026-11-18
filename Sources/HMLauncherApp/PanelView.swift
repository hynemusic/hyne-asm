import SwiftUI
import HMLauncherCore

struct PanelView: View {
    static let rowHeight: CGFloat = 46
    static let tabBarHeight: CGFloat = 38
    static let filterHeight: CGFloat = 28
    static let padding: CGFloat = 8
    static let maxVisibleRows = 10
    static let maxVisibleTabs = 6

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

    var body: some View {
        VStack(spacing: 0) {
            tabBar
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
            rowList
        }
        .padding(Self.padding)
        .modifier(PanelChrome())
        .id(Palette.theme)
    }

    // MARK: Tabs

    /// Up to `limit` tabs, the selected one always among them.
    private func visibleTabIndices(_ limit: Int) -> [Int] {
        let count = viewModel.state.tabs.count
        var shown = Array(0..<min(limit, count))
        let sel = viewModel.state.selectedTab
        if !shown.contains(sel) { shown[shown.count - 1] = sel }
        return shown
    }

    /// As many tabs as fit the panel's width (one column is narrow); the rest go into the "⋯" menu.
    private var tabBar: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: min(Self.maxVisibleTabs, viewModel.state.tabs.count), through: 1, by: -1)), id: \.self) { n in
                tabRow(visibleTabIndices(n))
            }
        }
        .frame(height: Self.tabBarHeight - 6)
        .padding(.bottom, 6) // keeps tabBarHeight; the hairline sits in this gap
        .overlay(alignment: .bottom) { Rectangle().fill(Color.panelStroke).frame(height: 1).padding(.bottom, 3) }
    }

    private func tabRow(_ shownTabs: [Int]) -> some View {
        HStack(spacing: 2) {
            ForEach(shownTabs, id: \.self) { i in tabButton(i) }
            Spacer(minLength: 0)
            let hidden = viewModel.state.tabs.indices.filter { !shownTabs.contains($0) }
            if !hidden.isEmpty {
                Menu {
                    ForEach(hidden, id: \.self) { i in Button(title(of: i)) { onSelectTab(i) } }
                } label: {
                    Image(systemName: "ellipsis").font(.themed(12, .semibold)).foregroundColor(DS.textSecondary)
                        .frame(width: 28, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 2)
    }

    private func title(of index: Int) -> String {
        switch viewModel.state.tabs[index] {
        case .category(_, let name): return name
        }
    }

    private func tabButton(_ index: Int) -> some View {
        let selected = index == viewModel.state.selectedTab
        return Button { onSelectTab(index) } label: {
            HStack(spacing: 5) {
                if case .category(let id, _) = viewModel.state.tabs[index], viewModel.isFavorites(id) {
                    Image(systemName: "star.fill").font(.themed(9.5)).foregroundColor(selected ? .accent : DS.textTertiary)
                }
                Text(title(of: index))
                    .font(selected ? DS.Font.columnTitle : DS.Font.bodyStrong)
                    .foregroundColor(selected ? DS.textPrimary : DS.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: CGFloat(7).themedRadius).fill(selected ? Color.ink.opacity(0.09) : .clear))
            .overlay(alignment: .bottom) {
                if selected { Capsule().fill(Color.accent).frame(width: 14, height: 2).offset(y: 1) }
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Moving over a category is enough to switch to it.
        .onHover { inside in if inside && !selected { onSelectTab(index) } }
    }

    // MARK: Rows

    private var rowList: some View {
        let rows = viewModel.state.rows
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: rows.count > PanelGrid.columns * Self.maxVisibleRows) {
                VStack(spacing: 4) {
                    if rows.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: viewModel.state.filter.isEmpty ? "tray" : "magnifyingglass")
                            Text(viewModel.state.filter.isEmpty ? Loc.t("Keine Einträge – in den Einstellungen hinzufügen", "No entries – add some in Settings") : Loc.t("Nichts gefunden", "Nothing found"))
                        }
                        .font(DS.Font.secondary).foregroundColor(DS.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: Self.rowHeight - 4)
                    }
                    // Two columns of 10 (left first), category hits and "All plugins" hits as separate grids.
                    let firstGlobal = rows.firstIndex(where: \.isGlobal) ?? rows.count
                    if firstGlobal > 0 { grid(rows, 0..<firstGlobal) }
                    if firstGlobal < rows.count {
                        globalHeader
                        grid(rows, firstGlobal..<rows.count)
                    }
                }
            }
            .onChange(of: viewModel.state.highlighted) { h in
                if let h { proxy.scrollTo(h) }
            }
        }
    }

    static let globalHeaderHeight: CGFloat = 26
    static let columnWidth: CGFloat = 316
    static let columnSpacing: CGFloat = 6
    static var width: CGFloat { width(columns: PanelGrid.columns) }
    /// One column up to 9 entries, two beyond (`PanelGrid.columnsNeeded`).
    static func width(columns: Int) -> CGFloat {
        columnWidth * CGFloat(columns) + columnSpacing * CGFloat(columns - 1) + padding * 2
    }

    private func grid(_ rows: [PanelRow], _ range: Range<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(PanelGrid.blocks(range).enumerated()), id: \.offset) { _, block in
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    // Empty columns are left out, so a short category stays one column wide.
                    ForEach(Array(block.filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: 4) {
                            ForEach(column, id: \.self) { index in rowView(rows[index], index: index).id(index) }
                        }
                        .frame(width: Self.columnWidth, alignment: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)   // a one-column section sits left in a two-column panel
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

    private func rowView(_ row: PanelRow, index: Int) -> some View {
        let active = viewModel.state.highlighted == index || viewModel.hovered == index
        return Button { onInsert(row) } label: {
            LauncherRow(number: index, symbol: IconCatalog.symbolName(for: row.iconID), title: row.title,
                        active: active, available: row.isAvailable, color: Color(label: row.colorID)) {
                if row.isNew { NewBadge() }
                if row.folderID != nil {
                    Text("\(row.childCount)")
                        .font(DS.Font.badge.monospacedDigit()).foregroundColor(DS.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.ink.opacity(0.07)))
                    Image(systemName: "chevron.right").font(.themed(10, .bold)).foregroundColor(DS.textTertiary)
                }
            }
            .opacity(row.isAvailable ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { inside in
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
