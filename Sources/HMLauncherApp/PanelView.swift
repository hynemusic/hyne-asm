import SwiftUI
import HMLauncherCore

struct PanelView: View {
    static let rowHeight: CGFloat = 46
    static let tabBarHeight: CGFloat = 38
    static let filterHeight: CGFloat = 28
    static let padding: CGFloat = 8
    static let maxVisibleRows = 10
    static let maxVisibleTabs = 3

    @ObservedObject var viewModel: PanelViewModel
    let onInsert: (PanelRow) -> Void
    let onCloseFolder: () -> Void
    let onSelectTab: (Int) -> Void
    let isFavorite: (PanelRow) -> Bool
    let onToggleFavorite: (PanelRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            if let folder = viewModel.state.openFolderName {
                Button(action: onCloseFolder) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text(categoryTitle).foregroundColor(.dimText)
                        Text("/").foregroundColor(.dimText)
                        Image(systemName: "folder.fill").foregroundColor(.accent)
                        Text(folder).fontWeight(.semibold)
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .frame(height: Self.filterHeight)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Loc.t("Zurück (Esc)", "Back (Esc)"))
            }
            if !viewModel.state.filter.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.dimText)
                    Text(viewModel.state.filter).foregroundColor(.white)
                    Spacer()
                }
                .font(.system(size: 13))
                .frame(height: Self.filterHeight)
                .padding(.horizontal, 10)
            }
            rowList
        }
        .padding(Self.padding)
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Tabs

    private var visibleTabIndices: [Int] {
        let count = viewModel.state.tabs.count
        var shown = Array(0..<min(Self.maxVisibleTabs, count))
        let sel = viewModel.state.selectedTab
        if !shown.contains(sel) { shown[shown.count - 1] = sel }
        return shown
    }

    private var tabBar: some View {
        HStack(spacing: 14) {
            ForEach(visibleTabIndices, id: \.self) { i in tabButton(i) }
            Spacer(minLength: 0)
            let hidden = viewModel.state.tabs.indices.filter { !visibleTabIndices.contains($0) }
            if !hidden.isEmpty {
                Menu {
                    ForEach(hidden, id: \.self) { i in Button(title(of: i)) { onSelectTab(i) } }
                } label: {
                    Text("⋯").font(.system(size: 15, weight: .semibold)).foregroundColor(.dimText)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.tabBarHeight)
    }

    private func title(of index: Int) -> String {
        switch viewModel.state.tabs[index] {
        case .category(_, let name): return name
        case .all: return Loc.t("Alle", "All")
        }
    }

    private func tabButton(_ index: Int) -> some View {
        let selected = index == viewModel.state.selectedTab
        return Button { onSelectTab(index) } label: {
            VStack(spacing: 4) {
                Text(title(of: index))
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? .white : .dimText)
                    .lineLimit(1)
                Rectangle().fill(selected ? Color.accent : .clear).frame(height: 2)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    // MARK: Rows

    private var rowList: some View {
        let rows = viewModel.state.rows
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: rows.count > Self.maxVisibleRows) {
                VStack(spacing: 4) {
                    if rows.isEmpty {
                        Text(viewModel.state.filter.isEmpty ? Loc.t("Keine Einträge – in den Einstellungen hinzufügen", "No entries – add some in Settings") : Loc.t("Nichts gefunden", "Nothing found"))
                            .font(.system(size: 12)).foregroundColor(.dimText)
                            .frame(maxWidth: .infinity, minHeight: Self.rowHeight - 4)
                    }
                    let firstGlobal = rows.firstIndex(where: \.isGlobal)
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index == firstGlobal { globalHeader }
                        rowView(row, index: index).id(index)
                    }
                }
            }
            .onChange(of: viewModel.state.highlighted) { h in
                if let h { proxy.scrollTo(h) }
            }
        }
    }

    static let globalHeaderHeight: CGFloat = 26

    private var globalHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 10))
            Text(Loc.t("Alle Plugins", "All plugins")).font(.system(size: 11, weight: .semibold))
            Rectangle().fill(Color.dimText.opacity(0.4)).frame(height: 1)
        }
        .foregroundColor(.dimText)
        .padding(.horizontal, 6)
        .frame(height: Self.globalHeaderHeight)
    }

    private var categoryTitle: String {
        if case .category(_, let name) = viewModel.state.tabs[viewModel.state.selectedTab] { return name }
        return ""
    }

    private func rowView(_ row: PanelRow, index: Int) -> some View {
        let active = viewModel.state.highlighted == index || viewModel.hovered == index
        return Button { onInsert(row) } label: {
            LauncherRow(number: index, symbol: IconCatalog.symbolName(for: row.iconID), title: row.title,
                        active: active, available: row.isAvailable) {
                if row.folderID != nil {
                    Text("\(row.childCount)").font(.system(size: 11)).foregroundColor(.dimText)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(.dimText)
                }
            }
            .opacity(row.isAvailable ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { viewModel.hovered = index } else if viewModel.hovered == index { viewModel.hovered = nil }
        }
        .contextMenu {
            if row.folderID == nil {
            Button(isFavorite(row) ? Loc.t("Aus Favoriten entfernen", "Remove from Favorites") : Loc.t("Zu Favoriten hinzufügen", "Add to Favorites")) { onToggleFavorite(row) }
            }
        }
        .help(row.isAvailable ? row.path.joined(separator: " / ") : Loc.t("Nicht mehr in Live gefunden", "No longer found in Live"))
    }
}
