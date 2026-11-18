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
                 subtitle: Loc.t("Plugins, Presets & Kategorien", "Plugins, presets & categories")),
            Item(id: 1, symbol: "command", title: Loc.t("Tastenkürzel", "Shortcuts"),
                 subtitle: Loc.t("Fenster, Suche, Panel", "Windows, search, panel")),
            Item(id: 3, symbol: "clock.arrow.circlepath", title: Loc.t("Versionen", "Versions"),
                 subtitle: Loc.t("Sichern & teilen", "Save & share")),
            Item(id: 2, symbol: "square.and.arrow.down", title: Loc.t("LES-Import", "LES Import"),
                 subtitle: Loc.t("menuconfig.ini übernehmen", "Bring over menuconfig.ini")),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.top, 44) // room for the window's traffic lights
                .padding(.horizontal, DS.Space.l)
                .padding(.bottom, DS.Space.xl)
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
                Text("HYNE ASM").font(.system(size: 14, weight: .bold)).foregroundColor(DS.textPrimary)
                Text("Ableton Shortcuts Manager").font(.system(size: 10.5)).foregroundColor(DS.textTertiary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func navRow(_ item: Item) -> some View {
        let selected = page == item.id
        return Button { page = item.id } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(selected ? .white : DS.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(selected ? Color.brandBlue : DS.raised))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                    Text(item.subtitle).font(.system(size: 10.5)).foregroundColor(DS.textTertiary).lineLimit(1)
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
                         : Loc.t("ASMbridge als Control Surface wählen", "Choose ASMbridge as control surface"))
                        .font(.system(size: 10)).foregroundColor(DS.textTertiary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
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
