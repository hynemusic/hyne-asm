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
    let onSelectTab: (Int) -> Void
    let isFavorite: (PanelRow) -> Bool
    let onToggleFavorite: (PanelRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabBar
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
        case .all: return "Alle"
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
                        Text(viewModel.state.filter.isEmpty ? "Keine Einträge – in den Einstellungen hinzufügen" : "Nichts gefunden")
                            .font(.system(size: 12)).foregroundColor(.dimText)
                            .frame(maxWidth: .infinity, minHeight: Self.rowHeight - 4)
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        rowView(row, index: index).id(index)
                    }
                }
            }
            .onChange(of: viewModel.state.highlighted) { h in
                if let h { proxy.scrollTo(h) }
            }
        }
    }

    private func rowView(_ row: PanelRow, index: Int) -> some View {
        let active = viewModel.state.highlighted == index || viewModel.hovered == index
        return Button { onInsert(row) } label: {
            LauncherRow(number: index, symbol: IconCatalog.symbolName(for: row.iconID), title: row.title,
                        active: active, available: row.isAvailable)
                .opacity(row.isAvailable ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { viewModel.hovered = index } else if viewModel.hovered == index { viewModel.hovered = nil }
        }
        .contextMenu {
            Button(isFavorite(row) ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") { onToggleFavorite(row) }
        }
        .help(row.isAvailable ? row.path.joined(separator: " / ") : "Nicht mehr in Live gefunden")
    }
}
