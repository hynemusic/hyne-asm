import SwiftUI
import HMLauncherCore

/// Colours of the panel, shared with the settings window.
/// Brand palette "Signal" from the ASM Double Key logo (docs/logo/final): blue #3D5AFE + coral #FF6B57.
extension Color {
    /// Brand blue #3D5AFE: prominent buttons (white text on it stays readable).
    static let brandBlue = Color(red: 0x3D / 255, green: 0x5A / 255, blue: 0xFE / 255)
    /// Brand coral #FF6B57: accents on the dark panel (active bar, cursor, folder/star icons, text buttons).
    static let brandCoral = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x57 / 255)

    static let panelBackground = Color(red: 0.17, green: 0.17, blue: 0.17)
    static let panelSidebar = Color(red: 0.14, green: 0.14, blue: 0.14)
    static let rowBackground = Color(red: 0.24, green: 0.24, blue: 0.24)
    /// Hovered/selected row: the row grey with ~35 % brand blue mixed in.
    static let rowHighlight = Color(red: 0.24, green: 0.28, blue: 0.50)
    static let accent = brandCoral
    static let dimText = Color(white: 0.55)
}

/// Surfaces of the floating panel, quick search and folder list.
extension Color {
    static let panelSurface = Color(white: 0.115)
    static let panelRow = Color(white: 0.17)
    static let panelStroke = Color.white.opacity(0.09)
}

/// Background, border and shadow shared by the panel, the quick search and the folder side list.
struct PanelChrome: ViewModifier {
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(Color.panelSurface))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.panelStroke))
    }
}

/// One row as it appears in the panel: shortcut key, icon tile, title.
/// Height 42 (+ 4 spacing = `PanelView.rowHeight`); the window layout relies on it.
struct LauncherRow<Trailing: View>: View {
    let number: Int?
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var active = false
    var available = true
    /// Color label: tints the icon tile.
    var color: Color? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let number { keyCap(number) }
            iconTile
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.system(size: 10.5))
                        .foregroundColor(available ? DS.textTertiary : DS.warning).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailing()
        }
        .foregroundColor(available ? DS.textPrimary : DS.textTertiary)
        .padding(.leading, number == nil ? 7 : 6)
        .padding(.trailing, 10)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 8).fill(active ? Color.brandBlue.opacity(0.32) : Color.panelRow))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? Color.brandBlue.opacity(0.75) : Color.white.opacity(0.04)))
        .contentShape(Rectangle())
    }

    /// 1–9 as a small key cap; rows from 10 on keep the slot empty so the icons stay aligned.
    private func keyCap(_ index: Int) -> some View {
        Text(index < 9 ? "\(index + 1)" : "")
            .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundColor(active ? .white : DS.textSecondary)
            .frame(width: 18, height: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(index < 9 ? (active ? Color.accent : Color.white.opacity(0.07)) : .clear))
    }

    private var iconTile: some View {
        Image(systemName: symbol)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundColor(color ?? (active ? .white : DS.textSecondary))
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill((color ?? .white).opacity(color == nil ? 0.06 : 0.18)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder((color ?? .clear).opacity(0.35)))
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
