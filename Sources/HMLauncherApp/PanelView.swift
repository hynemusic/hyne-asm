import SwiftUI
import HMLauncherCore

private extension Color {
    static let panelBackground = Color(red: 0.17, green: 0.17, blue: 0.17)
    static let rowBackground = Color(red: 0.24, green: 0.24, blue: 0.24)
    static let rowHighlight = Color(red: 0.42, green: 0.39, blue: 0.35)
    static let accent = Color(red: 0.96, green: 0.70, blue: 0.20)
    static let dimText = Color(white: 0.55)
}

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
            HStack(spacing: 12) {
                Text(index < 9 ? "\(index + 1)" : "")
                    .font(.system(size: 11)).foregroundColor(.dimText).frame(width: 12)
                Image(systemName: IconCatalog.symbolName(for: row.iconID))
                    .font(.system(size: 15)).frame(width: 22)
                Text(row.title).font(.system(size: 15)).lineLimit(1)
                Spacer()
            }
            .foregroundColor(row.isAvailable ? .white : .dimText)
            .opacity(row.isAvailable ? 1 : 0.5)
            .padding(.leading, 10)
            .frame(height: Self.rowHeight - 4)
            .background(active ? Color.rowHighlight : Color.rowBackground)
            .overlay(alignment: .leading) {
                if active { Rectangle().fill(Color.accent).frame(width: 3) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
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
