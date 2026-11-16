import SwiftUI

/// Colours of the panel (modelled on the reference screenshot), shared with the settings window.
extension Color {
    static let panelBackground = Color(red: 0.17, green: 0.17, blue: 0.17)
    static let panelSidebar = Color(red: 0.14, green: 0.14, blue: 0.14)
    static let rowBackground = Color(red: 0.24, green: 0.24, blue: 0.24)
    static let rowHighlight = Color(red: 0.42, green: 0.39, blue: 0.35)
    static let accent = Color(red: 0.96, green: 0.70, blue: 0.20)
    static let dimText = Color(white: 0.55)
}

/// One row as it appears in the panel: number, icon, title, yellow bar when active.
struct LauncherRow<Trailing: View>: View {
    let number: Int?
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var active = false
    var available = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(number.map { $0 < 9 ? "\($0 + 1)" : "" } ?? "")
                .font(.system(size: 11)).foregroundColor(.dimText).frame(width: 12)
            Image(systemName: symbol).font(.system(size: 15)).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.system(size: 10)).foregroundColor(available ? .dimText : .orange).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailing()
        }
        .foregroundColor(available ? .white : .dimText)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 42)
        .background(active ? Color.rowHighlight : Color.rowBackground)
        .overlay(alignment: .leading) {
            if active { Rectangle().fill(Color.accent).frame(width: 3) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }
}

extension LauncherRow where Trailing == EmptyView {
    init(number: Int?, symbol: String, title: String, subtitle: String? = nil, active: Bool = false, available: Bool = true) {
        self.init(number: number, symbol: symbol, title: title, subtitle: subtitle, active: active, available: available) { EmptyView() }
    }
}
