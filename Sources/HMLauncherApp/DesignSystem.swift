import SwiftUI
import HMLauncherCore

/// Design tokens and building blocks for the settings window.
/// The panel in Live keeps its own look (Theme.swift); the settings reuse its brand colours.
enum DS {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static var s: CGFloat { 6 * Palette.current.radiusScale }
        static var m: CGFloat { 8 * Palette.current.radiusScale }
        static var l: CGFloat { 12 * Palette.current.radiusScale }
    }

    // Surfaces from the current theme. Each step is a layer that sits on the one before.
    static var canvas: Color { Palette.current.canvas }       // page background
    static var sidebar: Color { Palette.current.sidebar }     // navigation
    static var surface: Color { Palette.current.surface }     // columns, cards
    static var raised: Color { Palette.current.raised }       // rows and fields inside cards
    static var hover: Color { Palette.current.hover }
    static var hairline: Color { Palette.current.hairline }

    static var textPrimary: Color { Palette.current.textPrimary }
    static var textSecondary: Color { Palette.current.textSecondary }
    static var textTertiary: Color { Palette.current.textTertiary }

    /// Selected navigation item / category: a quiet tint of the strong accent.
    static var selection: Color { Palette.current.accentStrong.opacity(Palette.current.isDark ? 0.30 : 0.16) }
    static var success: Color { Palette.current.success }
    static var warning: Color { Palette.current.warning }

    /// The type scale. Every text in the app uses one of these roles — no other sizes.
    /// Display roles (titles, labels, names, key caps) take the theme's display design (SF Rounded in Retro);
    /// reading roles (body, secondary, caption) always use the standard face. Nothing readable is below 11 pt;
    /// only single-word badges go to 10.
    enum Font {
        private static var display: SwiftUI.Font.Design { Palette.current.displayDesign }
        private static func d(_ size: CGFloat, _ weight: SwiftUI.Font.Weight) -> SwiftUI.Font { .system(size: size, weight: weight, design: display) }

        // Display
        static var pageTitle: SwiftUI.Font { d(24, .bold) }
        static var title: SwiftUI.Font { d(17, .bold) }               // sheet titles, brand
        static var sectionTitle: SwiftUI.Font { d(15, .semibold) }
        static var columnTitle: SwiftUI.Font { d(13, .semibold) }
        static var rowTitle: SwiftUI.Font { d(14, .medium) }          // plugin names in panel-like rows
        static var padTitle: SwiftUI.Font { d(12, .semibold) }        // plugin names on the panel's pads
        static var sectionLabel: SwiftUI.Font { d(11, .semibold) }    // uppercase group labels
        static var badge: SwiftUI.Font { d(10, .semibold) }           // single-word badges, count chips
        static var field: SwiftUI.Font { d(22, .regular) }            // the quick search input
        static func metric(compact: Bool = false) -> SwiftUI.Font { .system(size: compact ? 17 : 26, weight: .bold, design: .rounded).monospacedDigit() }
        // Reading
        static var pageSubtitle: SwiftUI.Font { .system(size: 13) }
        static var body: SwiftUI.Font { .system(size: 13) }
        static var bodyStrong: SwiftUI.Font { .system(size: 13, weight: .medium) }
        static var secondary: SwiftUI.Font { .system(size: 12) }
        static var secondaryStrong: SwiftUI.Font { .system(size: 12, weight: .semibold) }
        static var caption: SwiftUI.Font { .system(size: 11) }
        static var numeric: SwiftUI.Font { .system(size: 11, weight: .semibold).monospacedDigit() }
        // Keys and code
        static var keycap: SwiftUI.Font { .system(size: 11, weight: .semibold, design: .rounded).monospacedDigit() }
        static var keyCombo: SwiftUI.Font { .system(size: 12, weight: .semibold, design: .rounded) }
        static var code: SwiftUI.Font { .system(size: 12, weight: .medium, design: .monospaced) }
    }
}

extension View {
    /// Light or dark controls (text fields, pickers, menus) to match the theme.
    func themedColorScheme() -> some View {
        // Switches, checkboxes and prominent buttons take the theme's accent (orange in Pads), not system blue.
        preferredColorScheme(Palette.current.isDark ? .dark : .light)
            .tint(Color.brandBlue)
            .accentColor(Color.brandBlue)
    }
}

/// Small uppercase label that opens a group of rows ("YOUR PRESETS", "PLUGIN WINDOWS").
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DS.Font.sectionLabel)
            .foregroundColor(DS.textTertiary)
    }
}

/// The pads' surface for settings: a dark plate lit from the top edge. `lit` (a selected row, the chosen
/// category) adds the accent edge and a soft accent glow, like a lit pad; unlit and `filled: false` draws nothing.
struct Plate: ViewModifier {
    var lit: Bool
    var radius: CGFloat = DS.Radius.m
    var filled = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        let show = lit || filled
        return content
            .background {
                if show {
                    shape.fill(LinearGradient(colors: [Palette.current.padTop ?? Color.panelRow.mix(.white, 0.045), Color.panelRow],
                                              startPoint: .top, endPoint: .bottom))
                        .shadow(color: lit ? Color.accent.opacity(0.28) : .clear, radius: 8)
                }
            }
            .overlay {
                if show {
                    shape.strokeBorder(lit ? AnyShapeStyle(Color.accent.opacity(0.55))
                                           : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.07), .clear, .black.opacity(0.3)],
                                                                          startPoint: .top, endPoint: .bottom)),
                                       lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// Selected rows and plates across the settings: see `Plate`.
    func plate(lit: Bool, radius: CGFloat = DS.Radius.m, filled: Bool = false) -> some View {
        modifier(Plate(lit: lit, radius: radius, filled: filled))
    }
}

/// Title + one-line explanation at the top of a page, with optional actions on the right.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.l) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(title).font(DS.Font.pageTitle).foregroundColor(DS.textPrimary)
                if let subtitle {
                    Text(subtitle).font(DS.Font.pageSubtitle).foregroundColor(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Space.l)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Header of a column in the Library page: title, a count chip and actions.
struct ColumnHeader<Trailing: View>: View {
    let title: String
    var count: Int? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Text(title).font(DS.Font.columnTitle).foregroundColor(DS.textPrimary).lineLimit(1)
            if let count { CountChip(count: count) }
            Spacer(minLength: DS.Space.s)
            trailing()
        }
        .frame(height: 28)
    }
}

struct CountChip: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(DS.Font.numeric)
            .foregroundColor(DS.textTertiary)
            .padding(.horizontal, 2)
    }
}

/// Short help text below a list or control.
struct HintText: View {
    let text: String
    var icon: String? = "info.circle"
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10)) }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(DS.Font.caption)
        .foregroundColor(DS.textTertiary)
    }
}

/// Icon-only toolbar button with a hover background.
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(hovering ? DS.textPrimary : DS.textSecondary)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(hovering ? DS.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .tooltip(help)
        .accessibilityLabel(help)
    }
}

/// Search field with a magnifier and a clear button, styled for the dark surfaces.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(DS.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundColor(DS.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.t("Suche leeren", "Clear search"))
            }
        }
        .padding(.horizontal, DS.Space.s)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(DS.raised))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.s).stroke(DS.hairline))
    }
}

extension View {
    /// A card: surface colour, rounded corners, hairline border.
    func dsCard(padding: CGFloat = DS.Space.l) -> some View {
        self.padding(padding).plate(lit: false, radius: DS.Radius.l, filled: true)
    }

    /// Hairline on one edge (column separators, header underlines).
    func hairline(_ edge: Edge) -> some View {
        overlay(alignment: edge == .top ? .top : edge == .bottom ? .bottom : edge == .leading ? .leading : .trailing) {
            if edge == .top || edge == .bottom {
                Rectangle().fill(DS.hairline).frame(height: 1)
            } else {
                Rectangle().fill(DS.hairline).frame(width: 1)
            }
        }
    }
}

/// Subtle background while the pointer is over a row.
struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(hovering ? DS.raised : .clear))
            .onHover { hovering = $0 }
    }
}

/// Frame of a single-column settings page: header on top, content centred with a readable maximum width.
struct PageContainer<Trailing: View, Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var maxWidth: CGFloat = 860
    var scrolls = true
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            PageHeader(title: title, subtitle: subtitle, trailing: trailing)
            if scrolls {
                ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                content()
            }
        }
        .frame(maxWidth: maxWidth, alignment: .topLeading)
        .padding(.horizontal, DS.Space.xxl)
        .padding(.top, 40)
        .padding(.bottom, DS.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.canvas)
    }
}

/// Orange warning icon; hovering it opens a small bubble saying what clashes. A popover instead of `.help`,
/// because tooltips never show in views that redraw on hover (the shortcut overview does that constantly).
struct ConflictBadge: View {
    let title: String
    let lines: [String]
    @State private var hovering = false

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundColor(DS.warning)
            .padding(3)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .popover(isPresented: $hovering, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(title, systemImage: "exclamationmark.triangle.fill")
                        .font(DS.Font.secondaryStrong)
                        .foregroundColor(DS.warning)
                    ForEach(lines, id: \.self) { line in
                        Text("• " + line).font(DS.Font.secondary).foregroundColor(DS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(minWidth: 220, maxWidth: 340, alignment: .leading)
            }
            .accessibilityLabel(title + ": " + lines.joined(separator: ", "))
    }
}

/// Text cursor for the panel filter and the quick search (keys arrive through the event tap, so there is no real
/// text field). A drawn bar in the accent colour that blinks like macOS's caret; it stays solid with Reduce Motion.
struct TextCaret: View {
    let height: CGFloat
    @State private var visible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accent)
            .frame(width: 2, height: height)
            .opacity(visible ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.5).delay(0.35).repeatForever(autoreverses: true)) { visible = false }
            }
            .accessibilityHidden(true)
    }
}

/// ⌘A selection: the text on a tinted highlight, like a selected macOS text field.
struct SelectedText: ViewModifier {
    let isSelected: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, isSelected ? 2 : 0)
            .background(RoundedRectangle(cornerRadius: 3).fill(isSelected ? Color.brandBlue.opacity(0.45) : .clear))
    }
}

/// "NEW" next to a newly installed plugin or preset.
struct NewBadge: View {
    var body: some View {
        Text(Loc.t("NEU", "NEW"))
            .font(DS.Font.badge)
            .foregroundColor(.onAccent)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.accent))
            .accessibilityLabel(Loc.t("Neu", "New"))
    }
}
