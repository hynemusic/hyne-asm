import AppKit
import SwiftUI
import HMLauncherCore

/// Left navigation of the settings window, like System Settings: brand, pages, Live status and language.
struct SettingsSidebar: View {
    @Binding var page: Int
    @ObservedObject var model: AppModel
    let pluginCount: Int

    private struct Item: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let subtitle: String
    }

    private var items: [Item] {
        [
            Item(id: 0, symbol: "square.grid.2x2", title: Loc.t("Bibliothek", "Library"),
                 subtitle: Loc.t("Plugins & Kategorien", "Plugins & categories")),
            Item(id: 3, symbol: "person.2.crop.square.stack", title: Loc.t("Profile", "Profiles"),
                 subtitle: Loc.t("Menüs wechseln & sichern", "Switch & save menus")),
            Item(id: 2, symbol: "square.and.arrow.down", title: Loc.t("LES-Import", "LES Import"),
                 subtitle: Loc.t("Aus menuconfig.ini", "From menuconfig.ini")),
            Item(id: 1, symbol: "command", title: Loc.t("Tastenkürzel", "Shortcuts"),
                 subtitle: Loc.t("Fenster, Suche, Panel", "Windows, search, panel")),
            Item(id: 6, symbol: "slider.horizontal.3", title: Loc.t("Verhalten", "Behavior"),
                 subtitle: Loc.t("Einfügen & Stream Deck", "Inserting & Stream Deck")),
            Item(id: 5, symbol: "text.magnifyingglass", title: Loc.t("Suche formen", "Shape Search"),
                 subtitle: Loc.t("Anpinnen & ausblenden", "Pin & hide results")),
            Item(id: 4, symbol: "chart.bar.xaxis", title: Loc.t("Statistik", "Stats"),
                 subtitle: Loc.t("Was du am meisten nutzt", "What you use most")),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.top, 44) // room for the window's traffic lights
                .padding(.horizontal, DS.Space.l)
                .padding(.bottom, Palette.current.logoColors.isEmpty ? DS.Space.xl : DS.Space.m)
            if !Palette.current.logoColors.isEmpty {
                LogoStripe(height: 3).padding(.horizontal, DS.Space.l).padding(.bottom, DS.Space.l)
            }
            VStack(spacing: 2) {
                ForEach(items) { item in navRow(item) }
            }
            .padding(.horizontal, DS.Space.s)
            Spacer()
            footer
                .padding(DS.Space.l)
        }
        .background(DS.sidebar)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("HYNE ASM").font(DS.Font.sectionTitle).fontWeight(.bold).foregroundColor(DS.textPrimary)
                Text("Ableton Shortcuts Manager").font(DS.Font.caption).foregroundColor(DS.textTertiary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func navRow(_ item: Item) -> some View {
        let selected = page == item.id
        return Button { page = item.id } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.themed(13, .medium))
                    .foregroundColor(selected ? .onBrandBlue : DS.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(selected ? Color.brandBlue : DS.raised))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                    Text(item.subtitle).font(DS.Font.caption).foregroundColor(DS.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: DS.Radius.m).fill(selected ? DS.selection : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.isConnected ? DS.success : DS.textTertiary)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.isConnected ? Loc.t("Mit Live verbunden", "Connected to Live") : Loc.t("Live nicht verbunden", "Live not connected"))
                        .font(DS.Font.caption.weight(.medium)).foregroundColor(DS.textSecondary)
                    Text(model.isConnected
                         ? "Live \(model.liveVersion ?? "") · \(pluginCount) " + Loc.t("Einträge", "items")
                         : Loc.t("In Live ASMbridge wählen", "Select ASMbridge in Live"))
                        .font(DS.Font.caption).foregroundColor(DS.textTertiary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            ThemeButton(theme: $model.config.theme)
            Picker(selection: $model.config.language) {
                Text(Loc.t("Automatisch", "Automatic")).tag(Language?.none)
                Text("Deutsch").tag(Language?.some(.de))
                Text("English").tag(Language?.some(.en))
            } label: {
                Image(systemName: "globe").foregroundColor(DS.textTertiary)
            }
            .controlSize(.small)
            .help(Loc.t("Sprache", "Language"))
        }
    }
}

/// Sidebar button showing the current theme; opens previews of all themes.
struct ThemeButton: View {
    @Binding var theme: AppTheme
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 8) {
                ThemeSwatch(palette: Palette.make(theme)).frame(width: 30, height: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Loc.t("Design", "Theme")).font(DS.Font.caption).foregroundColor(DS.textTertiary)
                    Text(theme.title).font(DS.Font.caption.weight(.semibold)).foregroundColor(DS.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.themed(9, .semibold)).foregroundColor(DS.textTertiary)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: DS.Radius.m).fill(DS.raised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text(Loc.t("Design wählen", "Choose a theme")).font(DS.Font.columnTitle).foregroundColor(DS.textPrimary)
                ForEach(AppTheme.allCases, id: \.self) { t in
                    Button { theme = t; open = false } label: { card(t) }.buttonStyle(.plain)
                }
            }
            .padding(DS.Space.l)
            .frame(width: 300)
        }
    }

    private func card(_ t: AppTheme) -> some View {
        let p = Palette.make(t)
        let chosen = t == theme
        return HStack(spacing: DS.Space.m) {
            ThemeSwatch(palette: p).frame(width: 74, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.system(size: 13, weight: .semibold, design: p.displayDesign)).foregroundColor(DS.textPrimary)
                Text(t.subtitle).font(DS.Font.caption).foregroundColor(DS.textTertiary)
            }
            Spacer()
            if chosen { Image(systemName: "checkmark.circle.fill").foregroundColor(.brandBlue) }
        }
        .padding(DS.Space.s)
        .background(RoundedRectangle(cornerRadius: DS.Radius.m).fill(chosen ? DS.selection : DS.raised.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.m).stroke(chosen ? Color.brandBlue.opacity(0.6) : DS.hairline))
        .contentShape(Rectangle())
    }
}

/// A tiny picture of a theme: its panel with two rows, a highlighted one and the accents.
struct ThemeSwatch: View {
    let palette: Palette

    var body: some View {
        GeometryReader { geo in
            let r = 6 * palette.radiusScale
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: r).fill(palette.panelSurface)
                if !palette.logoColors.isEmpty {
                    HStack(spacing: 0) { ForEach(Array(palette.logoColors.enumerated()), id: \.offset) { Rectangle().fill($0.element) } }
                        .frame(height: 2.5)
                }
                RoundedRectangle(cornerRadius: r).strokeBorder(palette.panelStroke)
                VStack(alignment: .leading, spacing: geo.size.height * 0.08) {
                    HStack(spacing: 3) {
                        Capsule().fill(palette.accent).frame(width: geo.size.width * 0.18, height: 2.5)
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: r * 0.5).fill(palette.accentStrong.opacity(0.45))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1).fill(palette.accent).frame(width: 3).padding(2)
                        }
                    RoundedRectangle(cornerRadius: r * 0.5).fill(palette.panelRow)
                }
                .padding(geo.size.width * 0.09)
            }
        }
    }
}
