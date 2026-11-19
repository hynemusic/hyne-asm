import AppKit
import SwiftUI
import HMLauncherCore

/// Settings page "Behavior": where inserted items land, multi-track inserts, Stats hints and the Stream Deck link.
struct BehaviorPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var server: StreamDeckServer
    @State private var copied: String?

    var body: some View {
        PageContainer(title: Loc.t("Verhalten", "Behavior"),
                      subtitle: Loc.t("Wie das Panel aussieht, wo Plugins in Live landen und was andere Geräte auslösen können.",
                                      "How the panel looks, where plugins land in Live and what other devices can trigger."),
                      maxWidth: 780) { EmptyView() } content: {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                panelCard
                insertCard
                hintsCard
                streamDeckCard
            }
            .padding(.bottom, DS.Space.l)
        }
    }

    // MARK: Panel

    private var panelCard: some View {
        card(Loc.t("Panel", "Panel"), symbol: "square.grid.3x3") {
            HStack(alignment: .center, spacing: DS.Space.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.t("Kategorien", "Categories")).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                    caption(Loc.t("Als Tabs über den Pads oder als Liste links daneben.", "Tabs above the pads, or a list beside them."))
                }
                Spacer(minLength: DS.Space.m)
                Picker("", selection: $model.config.categoryPlacement) {
                    Text(Loc.t("Oben", "Top")).tag(CategoryPlacement.top)
                    Text(Loc.t("Links", "Left")).tag(CategoryPlacement.left)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            divider
            HStack(alignment: .center, spacing: DS.Space.l) {
                VStack(alignment: .leading, spacing: 2) {
                    let grid = model.config.panelGrid
                    Text(Loc.t("Größe", "Size")).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                    caption(Loc.t("\(grid.columns) × \(grid.rows) – \(grid.pageSize) Pads pro Seite. Mehr Einträge kommen auf weitere Seiten; die Tasten 1–9 gelten für die ersten neun der Seite.",
                                  "\(grid.columns) × \(grid.rows) – \(grid.pageSize) pads per page. More entries go on further pages; keys 1–9 pick the page's first nine."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DS.Space.m)
                gridPreview
                VStack(alignment: .trailing, spacing: DS.Space.xs) {
                    sizeStepper(Loc.t("Spalten", "Columns"), value: $model.config.panelGrid.columns)
                    sizeStepper(Loc.t("Reihen", "Rows"), value: $model.config.panelGrid.rows)
                }
            }
        }
    }

    private func sizeStepper(_ label: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: PanelGridSize.range) {
            HStack(spacing: 6) {
                Text(label).font(DS.Font.secondary).foregroundColor(DS.textSecondary)
                Text("\(value.wrappedValue)").font(DS.Font.bodyStrong.monospacedDigit()).foregroundColor(DS.textPrimary)
                    .frame(minWidth: 14, alignment: .trailing)
            }
        }
        .fixedSize()
    }

    /// Tiny picture of one panel page: the chosen columns × rows, the first nine lit like keyed pads.
    private var gridPreview: some View {
        let grid = model.config.panelGrid
        return VStack(spacing: 2) {
            ForEach(0..<grid.rows, id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(0..<grid.columns, id: \.self) { c in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(r * grid.columns + c < 9 ? Color.accent.opacity(0.7) : DS.textTertiary.opacity(0.35))
                            .frame(width: 8, height: 7)
                    }
                }
            }
        }
        .padding(6)
        .frame(minWidth: 84, minHeight: 64)
        .plate(lit: false, radius: DS.Radius.s, filled: true)
        .accessibilityHidden(true)
    }

    // MARK: Inserting

    private var insertCard: some View {
        card(Loc.t("Einfügen", "Inserting"), symbol: "plus.square.on.square") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text(Loc.t("Wo landen Plugins, Racks und Ketten?", "Where do plugins, racks and chains land?")).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                Picker("", selection: $model.config.insert.position) {
                    Text(Loc.t("Am Ende der Kette", "End of the chain")).tag(InsertPosition.end)
                    Text(Loc.t("Hinter dem ausgewählten Device", "After the selected device")).tag(InsertPosition.afterSelected)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
                if scriptOutdated {
                    warning(Loc.t("Dein Live-Script ist veraltet. Wähl im Menü „Live-Script installieren …“ und starte Live neu. Bis dahin landet alles am Ende und nur auf der ausgewählten Spur.",
                                  "Your Live script is out of date. Choose “Install Live Script …” in the menu, then restart Live. Until then everything goes to the end, on the selected track only."))
                } else if model.config.insert.position == .afterSelected, model.capabilities?.moveDevice == false {
                    warning(Loc.t("Diese Live-Version kann Devices nicht verschieben, also landet alles am Ende.",
                                  "This Live version can't move devices, so everything goes to the end."))
                } else {
                    caption(Loc.t("Ohne ausgewähltes Device landet es am Ende.", "With no device selected it goes to the end."))
                }
            }
            divider
            Toggle(isOn: $model.config.insert.allSelectedTracks) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.t("Auf alle ausgewählten Spuren einfügen", "Insert on all selected tracks")).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                    Text(Loc.t("Sind in Live mehrere Spuren markiert, bekommt jede eine eigene Instanz.",
                               "With several tracks selected in Live, each one gets its own instance."))
                        .font(DS.Font.caption).foregroundColor(DS.textTertiary)
                }
            }
            .toggleStyle(.switch)
            if !scriptOutdated, model.config.insert.allSelectedTracks, model.capabilities?.multiSelect == false {
                warning(Loc.t("Diese Live-Version meldet keine Mehrfachauswahl, also nur die ausgewählte Spur.",
                              "This Live version doesn't report multi-selection, so only the selected track is used."))
            }
        }
    }

    /// Connected to a Live script older than version 4 (no chains, positions or multi-track inserts).
    private var scriptOutdated: Bool {
        guard model.isConnected, let v = model.scriptVersion else { return false }
        return (Int(v) ?? 0) < 4
    }

    // MARK: Hints

    private var hintsCard: some View {
        card(Loc.t("Hinweise", "Hints"), symbol: "lightbulb") {
            Toggle(isOn: $model.config.showRarelyUsed) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.t("Kaum genutzte Einträge in der Statistik zeigen", "Show rarely used entries on Stats")).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                    Text(Loc.t("Listet Panel-Einträge, die du fast nie einfügst, damit du aufräumen kannst.", "Lists panel entries you hardly ever insert, so you can tidy up."))
                        .font(DS.Font.caption).foregroundColor(DS.textTertiary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: Stream Deck

    private var streamDeckCard: some View {
        card("Stream Deck", symbol: "square.grid.3x2") {
            Toggle(isOn: $model.config.streamDeckEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.t("Stream-Deck-Verbindung", "Stream Deck connection")).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                    Text(statusText).font(DS.Font.caption).foregroundColor(statusColor)
                    Text(Loc.t("Jeder Link enthält einen geheimen Schlüssel, damit Webseiten im Browser die Verbindung nicht nutzen können.",
                               "Every link carries a secret key, so web pages in your browser can't use the connection."))
                        .font(DS.Font.caption).foregroundColor(DS.textTertiary)
                }
            }
            .toggleStyle(.switch)
            divider
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text(Loc.t("So richtest du eine Taste ein", "Set up a key")).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                step(1, Loc.t("Zieh in der Stream-Deck-App die Aktion „Website“ (System) auf eine Taste.",
                              "In the Stream Deck app, drag the “Website” action (System) onto a key."))
                step(2, Loc.t("Füg einen Link ein: Rechtsklick auf einen Eintrag in der Bibliothek, dann „Stream-Deck-Link kopieren“. Oder nimm einen von unten.",
                              "Paste a link. Right-click an entry in the Library and choose “Copy Stream Deck Link”, or use one from below."))
                step(3, Loc.t("Häkchen bei „Im Hintergrund aufrufen“ setzen, damit sich kein Browser öffnet.",
                              "Tick “Access in background” so no browser opens."))
            }
            divider
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                SectionLabel(text: Loc.t("Fertige Links", "Ready-made links"))
                linkRow(Loc.t("Schnellsuche öffnen", "Open quick search"), .quickSearch)
                linkRow(Loc.t("Panel an der Maus öffnen", "Open the panel at the mouse"), .panel)
                linkRow(Loc.t("Nächstes Profil", "Next profile"), .nextProfile)
                linkRow(Loc.t("Alle Plugin-Fenster schließen", "Close all plugin windows"), .closePluginWindows)
                linkRow(Loc.t("Tempo 128", "Tempo 128"), .action(LiveAction(kind: .setTempo, value: 128)))
                caption(Loc.t("Ohne Stream Deck gehen dieselben Befehle als hyneasm://-Link (z. B. aus Apple Kurzbefehle).",
                              "Without a Stream Deck the same commands work as hyneasm:// links (e.g. from Apple Shortcuts)."))
            }
        }
    }

    private var statusText: String {
        switch server.state {
        case .off: return Loc.t("Aus. Eingeschaltet erreicht sie nur dieser Mac (127.0.0.1).", "Off. When on, only this Mac can reach it (127.0.0.1).")
        case .listening: return Loc.t("Läuft auf 127.0.0.1:\(RemoteCommand.httpPort). Nur dieser Mac erreicht sie.", "Running on 127.0.0.1:\(RemoteCommand.httpPort). Only this Mac can reach it.")
        case .failed(let message): return Loc.t("Konnte nicht starten: ", "Couldn't start: ") + message
        }
    }

    private var statusColor: Color {
        switch server.state {
        case .listening: return DS.success
        case .failed: return DS.warning
        case .off: return DS.textTertiary
        }
    }

    private func linkRow(_ title: String, _ command: RemoteCommand) -> some View {
        let link = command.link(http: true, token: model.config.streamDeckToken).absoluteString
        return HStack(spacing: DS.Space.s) {
            Text(title).font(DS.Font.body).foregroundColor(DS.textPrimary).frame(width: 220, alignment: .leading)
            Text(link).font(DS.Font.code).foregroundColor(DS.textTertiary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(copied == link ? Loc.t("Kopiert", "Copied") : Loc.t("Kopieren", "Copy")) {
                StreamDeckLink.copy(command, token: model.config.streamDeckToken)
                copied = link
            }
            .controlSize(.small)
        }
        .frame(height: 30)
    }

    // MARK: Building blocks

    private func card<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Label { Text(title).font(DS.Font.sectionTitle).foregroundColor(DS.textPrimary) } icon: { Image(systemName: symbol).foregroundColor(.accent) }
            VStack(alignment: .leading, spacing: DS.Space.m) { content() }
                .padding(DS.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .plate(lit: false, radius: DS.Radius.l, filled: true)
        }
    }

    private var divider: some View { Rectangle().fill(DS.hairline).frame(height: 1) }
    private func caption(_ text: String) -> some View { Text(text).font(DS.Font.caption).foregroundColor(DS.textTertiary) }
    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill").font(DS.Font.caption).foregroundColor(DS.warning)
    }
    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text("\(n)").font(DS.Font.keycap).foregroundColor(DS.textSecondary)
                .frame(width: 18, height: 18).background(RoundedRectangle(cornerRadius: 5).fill(DS.raised))
            Text(text).font(DS.Font.secondary).foregroundColor(DS.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Copies a command's Stream Deck link (HTTP form) to the clipboard.
enum StreamDeckLink {
    static func copy(_ command: RemoteCommand, token: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command.link(http: true, token: token).absoluteString, forType: .string)
    }
}
