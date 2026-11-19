import AppKit
import SwiftUI
import HMLauncherCore

/// Colours of the panel and the settings, taken from the current theme (`Palette`).
/// Original theme = the pad look: warm black #121110, pads #262421→#1D1C1A, Ableton orange #FF8C1A.
extension Color {
    /// Prominent buttons, selection (brand blue in the original theme).
    static var brandBlue: Color { Palette.current.accentStrong }
    /// Highlights: active marks, caret, folder/star icons, text buttons (brand coral in the original theme).
    static var brandCoral: Color { Palette.current.accent }
    /// Text on `brandBlue`.
    static var onBrandBlue: Color { Palette.current.onAccentStrong }
    /// Text on `brandCoral`/`accent`.
    static var onAccent: Color { Palette.current.onAccent }
    /// White on dark themes, black on the light one — for small neutral tints.
    static var ink: Color { Palette.current.ink }

    static var panelBackground: Color { Palette.current.surface }
    static var panelSidebar: Color { Palette.current.sidebar }
    static var rowBackground: Color { Palette.current.raised }
    static var rowHighlight: Color { Palette.current.accentStrong.opacity(0.35) }
    static var accent: Color { brandCoral }
    static var dimText: Color { Palette.current.textTertiary }
}

/// Surfaces of the floating panel, quick search and folder list.
extension Color {
    static var panelSurface: Color { Palette.current.panelSurface }
    static var panelRow: Color { Palette.current.panelRow }
    static var panelStroke: Color { Palette.current.panelStroke }
}

/// Background, border and shadow shared by the panel, the quick search and the folder side list.
struct PanelChrome: ViewModifier {
    var radius: CGFloat = 12 * Palette.current.radiusScale
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(Color.panelSurface))
            .overlay(alignment: .top) { LogoStripe() }
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
    /// The panel's resize grip changes it; everywhere else 42.
    var height: CGFloat = 42
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
                Text(title).font(DS.Font.rowTitle).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(DS.Font.caption)
                        .foregroundColor(available ? DS.textTertiary : DS.warning).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailing()
        }
        .foregroundColor(available ? DS.textPrimary : DS.textTertiary)
        .padding(.leading, number == nil ? 7 : 6)
        .padding(.trailing, 10)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: CGFloat(8).themedRadius).fill(active ? Color.brandBlue.opacity(0.32) : Color.panelRow))
        .overlay(RoundedRectangle(cornerRadius: CGFloat(8).themedRadius).strokeBorder(active ? Color.brandBlue.opacity(0.75) : Color.ink.opacity(0.04)))
        .contentShape(Rectangle())
    }

    private func keyCap(_ index: Int) -> some View { EntryKeyCap(index: index, active: active) }

    private var iconTile: some View {
        Image(systemName: symbol)
            .font(.themed(13.5, .medium))
            .foregroundColor(color ?? (active ? DS.textPrimary : DS.textSecondary))
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: CGFloat(7).themedRadius).fill((color ?? .ink).opacity(color == nil ? 0.06 : 0.18)))
            .overlay(RoundedRectangle(cornerRadius: CGFloat(7).themedRadius).strokeBorder((color ?? .clear).opacity(0.35)))
    }
}

/// 1–9 as a small key cap; entries from 10 on keep the slot empty so icons stay aligned.
/// Retro: the key caps cycle through the PlayStation logo colours (dark text on the yellow one).
struct EntryKeyCap: View {
    let index: Int
    var active = false

    var body: some View {
        let logo = Palette.current.logoColors
        let fill: Color = index >= 9 ? .clear
            : !logo.isEmpty ? logo[index % logo.count].opacity(active ? 1 : 0.85)
            : active ? .accent : .ink.opacity(0.07)
        let text: Color = !logo.isEmpty ? (index % logo.count == 1 ? .black : .white) : (active ? .onAccent : DS.textSecondary)
        return Text(index < 9 ? "\(index + 1)" : "")
            .font(DS.Font.keycap)
            .foregroundColor(text)
            .frame(width: 18, height: 18)
            .background(RoundedRectangle(cornerRadius: CGFloat(5).themedRadius).fill(fill))
    }
}

/// One entry as a pad of the panel's 3×3 blocks, styled like a lit hardware pad: a dark pad with a soft top
/// highlight, key number top left, badges top right, icon and name centred, and a stripe along the bottom.
/// The color label colors only the icon and the stripe (which glows); unlabeled pads get a dim stripe.
/// Hover or the keyboard highlight lights the whole pad in its label color (the accent when it has none).
struct LauncherPad<Badges: View>: View {
    let number: Int?
    let symbol: String
    let title: String
    var height: CGFloat = 66
    var active = false
    var available = true
    var color: Color? = nil
    @ViewBuilder var badges: () -> Badges

    /// Text and marks on a lit pad.
    private static var onLit: Color { Palette.current.onLitPad }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(8).themedRadius)
        let lit = color ?? Color.accent
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.themed(17, .medium))
                .foregroundColor(active ? Self.onLit.opacity(0.75) : (color ?? DS.textTertiary))
                .frame(height: 20)
            Text(title)
                .font(DS.Font.padTitle)
                .foregroundColor(active ? Self.onLit : (available ? DS.textPrimary : DS.textTertiary))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .overlay(alignment: .topLeading) {
            if let number, number < 9 {
                Text("\(number + 1)")
                    .font(DS.Font.numeric)
                    .foregroundColor(active ? Self.onLit.opacity(0.65) : DS.textTertiary)
                    .padding(.top, 5).padding(.leading, 7)
            }
        }
        .overlay(alignment: .topTrailing) { HStack(spacing: 3) { badges() }.padding(5) }
        .overlay(alignment: .bottom) { PadStripe(active: active, color: color).padding(.bottom, 6) }
        .modifier(PadSurface(active: active, lit: lit, shape: shape))
    }
}

/// The pads' body, shared by grid pads and list rows: a dark top-lit plate, or filled with `lit` (with a glow)
/// while active. Light catches the top edge and a shade runs along the bottom, so it reads as raised.
struct PadSurface<S: InsettableShape>: ViewModifier {
    let active: Bool
    let lit: Color
    let shape: S

    func body(content: Content) -> some View {
        content
            .background {
                if active {
                    shape.fill(lit)
                } else {
                    shape.fill(LinearGradient(colors: [Palette.current.padTop ?? Color.panelRow.mix(.white, 0.045), Color.panelRow],
                                              startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(active ? 0.35 : 0.07), .clear, .black.opacity(0.35)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: active ? lit.opacity(0.45) : .clear, radius: 9)
            .contentShape(shape)
    }
}

/// The color label as a short stripe centred at the bottom: a soft glow in the label's color, dim when
/// there is none.
struct PadStripe: View {
    let active: Bool
    let color: Color?
    var width: CGFloat = 28
    var height: CGFloat = 2

    var body: some View {
        let fill: Color = active ? Palette.current.onLitPad.opacity(0.3) : (color ?? Palette.current.padStripe)
        Capsule()
            .fill(fill)
            .frame(width: width, height: height)
            .shadow(color: active || color == nil ? .clear : (color ?? .clear).opacity(0.45), radius: 3)
    }
}

/// One entry as a row of the panel's list style: the same plate, stripe and lit state as a pad, laid out
/// left to right — key number, icon in the label color, name, badges.
struct LauncherListRow<Badges: View>: View {
    let number: Int?
    let symbol: String
    let title: String
    var height: CGFloat = 42
    var active = false
    var available = true
    var color: Color? = nil
    /// Second line under the name (quick search: where the result comes from).
    var subtitle: String? = nil
    /// The list has a key column (panel); without one (quick search) the icon starts the row.
    var showsNumber = true
    @ViewBuilder var badges: () -> Badges

    private static var onLit: Color { Palette.current.onLitPad }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(8).themedRadius)
        HStack(spacing: 9) {
            if showsNumber {
                Text(number.map { $0 < 9 ? "\($0 + 1)" : "" } ?? "")
                    .font(DS.Font.numeric)
                    .foregroundColor(active ? Self.onLit.opacity(0.65) : DS.textTertiary)
                    .frame(width: 12, alignment: .leading)
            }
            Image(systemName: symbol)
                .font(.themed(15, .medium))
                .foregroundColor(active ? Self.onLit.opacity(0.75) : (color ?? DS.textTertiary))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.Font.padTitle)
                    .foregroundColor(active ? Self.onLit : (available ? DS.textPrimary : DS.textTertiary))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.caption)
                        .foregroundColor(active ? Self.onLit.opacity(0.7) : (available ? DS.textTertiary : DS.warning))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) { badges() }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .overlay(alignment: .bottom) { PadStripe(active: active, color: color, width: 24).padding(.bottom, 4) }
        .modifier(PadSurface(active: active, lit: color ?? Color.accent, shape: shape))
    }
}

extension Color {
    /// This color blended toward `other` by `amount` (0–1).
    func mix(_ other: Color, _ amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        return Color(red: a.redComponent + (b.redComponent - a.redComponent) * amount,
                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * amount,
                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * amount)
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

