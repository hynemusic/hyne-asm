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
                      subtitle: Loc.t("Wie HYNE ASM in Live einfügt – und wie andere Geräte es steuern.",
                                      "How HYNE ASM inserts into Live – and how other devices control it."),
                      maxWidth: 780) { EmptyView() } content: {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                insertCard
                hintsCard
                streamDeckCard
            }
            .padding(.bottom, DS.Space.l)
        }
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
                    warning(Loc.t("Dein Live-Script ist veraltet – Menü → „Live-Script installieren …“, dann Live neu starten. Bis dahin landet alles am Ende und nur auf der ausgewählten Spur.",
                                  "Your Live script is out of date – menu → “Install Live Script …”, then restart Live. Until then everything goes to the end, on the selected track only."))
                } else if model.config.insert.position == .afterSelected, model.capabilities?.moveDevice == false {
                    warning(Loc.t("Diese Live-Version kann Devices nicht verschieben – es landet am Ende.",
                                  "This Live version can't move devices – it goes to the end."))
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
                warning(Loc.t("Diese Live-Version meldet keine Mehrfachauswahl – es wird nur die ausgewählte Spur verwendet.",
                              "This Live version doesn't report multi-selection – only the selected track is used."))
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
                    Text(Loc.t("Listet Panel-Einträge, die du fast nie einfügst – zum Aufräumen.", "Lists panel entries you hardly ever insert – to tidy up."))
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
                }
            }
            .toggleStyle(.switch)
            divider
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text(Loc.t("So richtest du eine Taste ein", "Set up a key")).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                step(1, Loc.t("Zieh in der Stream-Deck-App die Aktion „Website“ (System) auf eine Taste.",
                              "In the Stream Deck app, drag the “Website” action (System) onto a key."))
                step(2, Loc.t("Füg einen Link ein – Rechtsklick auf einen Eintrag in der Bibliothek → „Stream-Deck-Link kopieren“, oder einen von unten.",
                              "Paste a link – right-click an entry in the Library → “Copy Stream Deck Link”, or one from below."))
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
        case .off: return Loc.t("Aus – nur dieser Mac könnte sie erreichen (127.0.0.1).", "Off – only this Mac could reach it (127.0.0.1).")
        case .listening: return Loc.t("Bereit auf 127.0.0.1:\(RemoteCommand.httpPort) – nur von diesem Mac erreichbar.", "Ready on 127.0.0.1:\(RemoteCommand.httpPort) – reachable from this Mac only.")
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
        let link = command.link(http: true).absoluteString
        return HStack(spacing: DS.Space.s) {
            Text(title).font(DS.Font.body).foregroundColor(DS.textPrimary).frame(width: 220, alignment: .leading)
            Text(link).font(DS.Font.code).foregroundColor(DS.textTertiary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(copied == link ? Loc.t("Kopiert", "Copied") : Loc.t("Kopieren", "Copy")) {
                StreamDeckLink.copy(command)
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
                .background(RoundedRectangle(cornerRadius: DS.Radius.l).fill(DS.surface))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).stroke(DS.hairline))
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
    static func copy(_ command: RemoteCommand) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command.link(http: true).absoluteString, forType: .string)
    }
}
