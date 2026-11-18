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
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 12
    }

    // Surfaces, darkest to lightest. Each step is a layer that sits on the one before.
    static let canvas = Color(white: 0.105)      // page background
    static let sidebar = Color(white: 0.135)     // navigation
    static let surface = Color(white: 0.145)     // columns, cards
    static let raised = Color(white: 0.195)      // rows and fields inside cards
    static let hover = Color(white: 0.235)
    static let hairline = Color.white.opacity(0.07)

    static let textPrimary = Color(white: 0.94)
    static let textSecondary = Color(white: 0.68)
    static let textTertiary = Color(white: 0.56)

    /// Selected navigation item / category: a quiet brand-blue tint.
    static let selection = Color.brandBlue.opacity(0.30)
    static let success = Color(red: 0.30, green: 0.80, blue: 0.50)
    static let warning = Color(red: 1.0, green: 0.75, blue: 0.30)

    enum Font {
        static let pageTitle = SwiftUI.Font.system(size: 22, weight: .bold)
        static let pageSubtitle = SwiftUI.Font.system(size: 13)
        static let columnTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let bodyStrong = SwiftUI.Font.system(size: 13, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 11)
        static let sectionLabel = SwiftUI.Font.system(size: 10.5, weight: .semibold)
        static let badge = SwiftUI.Font.system(size: 9.5, weight: .semibold)
    }
}

/// Small uppercase label that opens a group of rows ("YOUR PRESETS", "PLUGIN WINDOWS").
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(DS.Font.sectionLabel)
            .tracking(0.7)
            .foregroundColor(DS.textTertiary)
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
            .font(DS.Font.badge.monospacedDigit())
            .foregroundColor(DS.textSecondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(DS.raised))
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
        .help(help)
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
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: DS.Radius.l).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).stroke(DS.hairline))
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.warning)
                    ForEach(lines, id: \.self) { line in
                        Text("• " + line).font(.system(size: 12)).foregroundColor(DS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(minWidth: 220, maxWidth: 340, alignment: .leading)
            }
            .accessibilityLabel(title + ": " + lines.joined(separator: ", "))
    }
}
