import SwiftUI
import HMLauncherCore

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
    /// Color label, drawn as a small bar at the left edge.
    var color: Color? = nil
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
            if let color {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 24).padding(.leading, 4)
            }
        }
        .overlay(alignment: .leading) {
            if active { Rectangle().fill(Color.accent).frame(width: 3) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }
}

extension LauncherRow where Trailing == EmptyView {
    init(number: Int?, symbol: String, title: String, subtitle: String? = nil, active: Bool = false, available: Bool = true, color: Color? = nil) {
        self.init(number: number, symbol: symbol, title: title, subtitle: subtitle, active: active, available: available, color: color) { EmptyView() }
    }
}

/// Inline rename field with its own text state: keystrokes only redraw this field, not the whole settings window.
/// Focuses itself, commits on Return or when focus leaves, cancels on Esc.
struct InlineNameField: View {
    let initial: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String
    @State private var done = false
    @FocusState private var focused: Bool

    init(initial: String, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onCommit = onCommit
        self.onCancel = onCancel
        _text = State(initialValue: initial)
    }

    var body: some View {
        TextField("", text: $text, onCommit: commit)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onExitCommand { done = true; onCancel() }
            .onAppear { DispatchQueue.main.async { focused = true } }
            .onChange(of: focused) { isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        guard !done else { return }
        done = true
        let name = text.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name == initial { onCancel() } else { onCommit(name) }
    }
}

extension Color {
    /// The label color for a `ColorPalette` id (nil for none/unknown).
    init?(label id: String?) {
        guard let def = ColorPalette.color(id) else { return nil }
        self.init(red: def.red, green: def.green, blue: def.blue)
    }
}

/// A colored dot for menus (menus draw template images grey, so this one is not a template).
func colorDot(_ def: ColorDef) -> Image {
    let size = NSSize(width: 12, height: 12)
    let image = NSImage(size: size, flipped: false) { rect in
        NSColor(red: def.red, green: def.green, blue: def.blue, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        return true
    }
    image.isTemplate = false
    return Image(nsImage: image)
}

/// "Color ▸" submenu: the palette, "None", and optionally "Like the rule" (own color removed).
struct ColorMenu: View {
    let title: String
    var current: String? = nil
    var allowInherit = true
    let onPick: (String?) -> Void

    var body: some View {
        Menu(title) {
            ForEach(ColorPalette.all, id: \.id) { def in
                Button { onPick(def.id) } label: {
                    Label { Text(def.label + (current == def.id ? "  ✓" : "")) } icon: { colorDot(def) }
                }
            }
            Divider()
            Button(Loc.t("Keine Farbe", "No Color")) { onPick(ColorPalette.noneID) }
            if allowInherit {
                Button(Loc.t("Farbe zurücksetzen (Regel)", "Reset Color (use rule)")) { onPick(nil) }
            }
        }
    }
}
