import AppKit
import SwiftUI
import UniformTypeIdentifiers
import HMLauncherCore

// MARK: - Shortcuts

struct ShortcutsPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var catalog: PluginCatalog
    @Binding var request: PluginItem?
    @State private var picking = false
    @State private var showKnown = false

    var body: some View {
        PageContainer(title: Loc.t("Tastenkürzel", "Shortcuts"),
                      subtitle: Loc.t("Klick auf ein Kürzel und drück die neue Kombination. Alle Kürzel wirken nur, wenn Live vorne ist.",
                                      "Click a shortcut and press the new combination. All shortcuts only work while Live is in front."),
                      maxWidth: 780) {
            Button { showKnown = true } label: { Label(Loc.t("Ableton- & macOS-Kürzel", "Ableton & macOS Shortcuts"), systemImage: "keyboard") }
                .help(Loc.t("Standardkürzel von Live und macOS anzeigen", "Show Live's and macOS's default shortcuts"))
        } content: {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                pluginShortcutsSection
                section(Loc.t("Plugin-Fenster", "Plugin Windows"), symbol: "macwindow.on.rectangle",
                        note: Loc.t("Kürzel brauchen ⌘, ⌃ oder ⌥.", "Shortcuts need ⌘, ⌃ or ⌥."),
                        reset: { model.config.shortcuts = .default }) {
                    row(Loc.t("Fokussiertes Plugin-Fenster schließen", "Close focused plugin window"),
                        combos: Binding(get: { model.config.shortcuts.closeFocused.map { [$0] } ?? [] },
                                        set: { model.config.shortcuts.closeFocused = $0.last }),
                        maxCount: 1, requireModifier: true)
                    divider
                    row(Loc.t("Alle Plugin-Fenster schließen", "Close all plugin windows"), combos: $model.config.shortcuts.closeAll, maxCount: 4, requireModifier: true)
                }
                section(Loc.t("Schnellsuche", "Quick Search"), symbol: "magnifyingglass",
                        note: Loc.t("Öffnet das Suchfenster in der Bildschirmmitte. macOS nutzt ⌃Leertaste evtl. für den Sprachwechsel.",
                                    "Opens the search window in the middle of the screen. macOS may use ⌃Space for switching input languages."),
                        reset: { model.config.shortcuts.quickSearch = ShortcutSettings.default.quickSearch }) {
                    row(Loc.t("Schnellsuche öffnen", "Open quick search"), combos: $model.config.shortcuts.quickSearch, maxCount: 2, requireModifier: true)
                }
                section(Loc.t("Im Panel", "In the Panel"), symbol: "rectangle.grid.1x2",
                        note: Loc.t("Fest: 1–9 fügen die Zeile ein, Tippen filtert, ⌫ löscht im Filter.", "Fixed: 1–9 insert that row, typing filters, ⌫ deletes in the filter."),
                        reset: { model.config.panelKeys = .default }) {
                    ForEach(Array(PanelKeyAction.allCases.enumerated()), id: \.element) { i, action in
                        if i > 0 { divider }
                        row(action.label, combos: Binding(get: { model.config.panelKeys[action] }, set: { model.config.panelKeys[action] = $0 }),
                            maxCount: 4, requireModifier: false)
                    }
                }
            }
            .padding(.bottom, DS.Space.l)
        }
    }

    // MARK: Plugin shortcuts

    private var pluginShortcutsSection: some View {
        section(Loc.t("Plugin-Kürzel", "Plugin Shortcuts"), symbol: "bolt",
                note: Loc.t("Fügt ein Plugin, Rack oder Preset sofort in die ausgewählte Spur ein – ganz ohne Panel. Kürzel brauchen ⌘, ⌃ oder ⌥.",
                            "Inserts a plugin, rack or preset straight into the selected track – no panel needed. Shortcuts need ⌘, ⌃ or ⌥."),
                resetTitle: Loc.t("Kürzel hinzufügen …", "Add Shortcut …"), reset: { picking = true }) {
            if let pending = request {
                itemRow(pending, combo: nil, id: nil, pending: true)
                if !model.config.itemShortcuts.isEmpty { divider }
            }
            ForEach(Array(model.config.itemShortcuts.enumerated()), id: \.element.id) { i, shortcut in
                if i > 0 { divider }
                itemRow(shortcut.item, combo: shortcut.combo, id: shortcut.id, pending: false)
            }
            if request == nil && model.config.itemShortcuts.isEmpty {
                Text(Loc.t("Noch keine. Klick oben auf „Kürzel hinzufügen …“ oder in der Bibliothek per Rechtsklick „Tastenkürzel zuweisen …“.",
                           "None yet. Click “Add Shortcut …” above, or right-click a plugin in the Library and choose “Assign Shortcut …”."))
                    .font(DS.Font.caption).foregroundColor(DS.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.l)
            }
        }
        .sheet(isPresented: $showKnown) { knownSheet }
        .popover(isPresented: $picking, arrowEdge: .top) {
            ItemPicker(items: catalog.items, title: Loc.t("Kürzel für …", "Shortcut for …")) { item in
                request = item
                picking = false
            }
        }
    }

    private func itemRow(_ item: PluginItem, combo: KeyCombo?, id: UUID?, pending: Bool) -> some View {
        let owner = combo.map { KeyboardLayout.conflicts($0, config: model.config, ignoring: id) }.flatMap { $0.isEmpty ? nil : $0.joined(separator: " · ") }
        let resolved = catalog.items.first { $0.uri == item.uri } ?? catalog.items.first { $0.name == item.name && $0.source == item.source }
        return HStack(spacing: DS.Space.s) {
            Image(systemName: IconCatalog.symbolName(for: IconGuesser.guess(resolved ?? item)))
                .font(.system(size: 12)).foregroundColor(DS.textSecondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(DS.raised))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(DS.Font.body).foregroundColor(DS.textPrimary).lineLimit(1)
                if let owner {
                    HStack(spacing: 2) {
                        Text(Loc.t("Auch belegt", "Also used")).font(DS.Font.caption).foregroundColor(DS.warning)
                        ConflictBadge(title: Loc.t("\(combo.map(KeyNames.describe) ?? "") ist auch belegt", "\(combo.map(KeyNames.describe) ?? "") is also used"),
                                      lines: owner.components(separatedBy: " · "))
                    }
                } else if pending {
                    Text(Loc.t("Klick auf + und drück die Tasten", "Click + and press the keys")).font(DS.Font.caption).foregroundColor(.accent)
                } else if resolved == nil, !catalog.items.isEmpty {
                    Text(Loc.t("Nicht mehr in Live gefunden", "No longer found in Live")).font(DS.Font.caption).foregroundColor(DS.warning)
                } else {
                    Text(UsageKind(item.source).title).font(DS.Font.caption).foregroundColor(DS.textTertiary)
                }
            }
            Spacer(minLength: DS.Space.l)
            KeyRecorder(combo: combo, requireModifier: true,
                        onChange: { newCombo in
                            guard KeyboardLayout.confirm(newCombo, config: model.config, ignoring: id) else { return }
                            model.config.setItemShortcut(newCombo, for: item)
                            if pending { request = nil }
                        },
                        onRemove: combo == nil ? nil : { model.config.setItemShortcut(nil, for: item) })
            if pending {
                IconButton(symbol: "xmark", help: Loc.t("Abbrechen", "Cancel")) { request = nil }
            }
        }
        .padding(.horizontal, DS.Space.l)
        .frame(height: 48)
        .background(pending ? Color.accent.opacity(0.07) : .clear)
    }

    private var knownSheet: some View {
        KnownShortcutsSheet(config: model.config) { showKnown = false }
    }

    private var divider: some View { Rectangle().fill(DS.hairline).frame(height: 1).padding(.leading, DS.Space.l) }

    private func section<Content: View>(_ title: String, symbol: String, note: String,
                                        resetTitle: String = Loc.t("Standard wiederherstellen", "Restore Defaults"),
                                        reset: @escaping () -> Void,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Label { Text(title).font(DS.Font.sectionTitle).foregroundColor(DS.textPrimary) }
                    icon: { Image(systemName: symbol).foregroundColor(.accent) }
                Spacer()
                Button(resetTitle, action: reset)
                    .buttonStyle(.borderless).font(DS.Font.caption).foregroundColor(DS.textSecondary)
            }
            Text(note).font(DS.Font.caption).foregroundColor(DS.textTertiary)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: DS.Radius.l).fill(DS.surface))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).stroke(DS.hairline))
                .padding(.top, DS.Space.xs)
        }
    }

    private func row(_ label: String, combos: Binding<[KeyCombo]>, maxCount: Int, requireModifier: Bool) -> some View {
        let clashes = requireModifier ? combos.wrappedValue.flatMap { c in
            KnownShortcuts.conflicts(with: c, keyCode: KeyboardLayout.keyCode(for:)).map { "\(KeyNames.describe(c)) – \($0.app == .live ? "Ableton Live" : "macOS"): \($0.title)" }
        } : []
        return HStack(spacing: DS.Space.s) {
            Text(label).font(DS.Font.body).foregroundColor(DS.textPrimary)
            if !clashes.isEmpty {
                ConflictBadge(title: Loc.t("Auch belegt", "Also used"), lines: clashes)
            }
            Spacer(minLength: DS.Space.l)
            if combos.wrappedValue.isEmpty {
                Text(Loc.t("aus", "off")).font(DS.Font.caption).foregroundColor(DS.textTertiary)
            }
            ForEach(Array(combos.wrappedValue.enumerated()), id: \.offset) { i, combo in
                KeyRecorder(combo: combo, requireModifier: requireModifier,
                            onChange: { new in
                                guard new == combo || !requireModifier || KeyboardLayout.confirm(new, config: model.config) else { return }
                                combos.wrappedValue[i] = new
                            },
                            onRemove: { combos.wrappedValue.remove(at: i) })
            }
            if combos.wrappedValue.count < maxCount {
                KeyRecorder(combo: nil, requireModifier: requireModifier,
                            onChange: { new in
                                guard !requireModifier || KeyboardLayout.confirm(new, config: model.config) else { return }
                                combos.wrappedValue.append(new)
                            }, onRemove: nil)
            }
        }
        .padding(.horizontal, DS.Space.l)
        .frame(height: 48)
    }
}

/// Click, then press the new combo. Clicking again cancels. `combo == nil` shows a "+" to add one.
struct KeyRecorder: View {
    let combo: KeyCombo?
    let requireModifier: Bool
    let onChange: (KeyCombo) -> Void
    let onRemove: (() -> Void)?
    @State private var recording = false
    @State private var hint: String?
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 2) {
            Button { recording ? stop() : start() } label: {
                Text(recording ? (hint ?? Loc.t("Taste drücken …", "Press keys …")) : combo.map(KeyNames.describe) ?? "+")
                    .font(DS.Font.keyCombo)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(minWidth: combo == nil && !recording ? 26 : 64)
                    .background(recording ? Color.rowHighlight : Color.panelSidebar)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(recording ? Color.accent : Color.clear))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help(combo == nil ? Loc.t("Kürzel hinzufügen", "Add shortcut") : Loc.t("Klicken und neue Taste drücken", "Click, then press the new keys"))
            if let onRemove, combo != nil, !recording {
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.borderless).foregroundColor(.dimText).help(Loc.t("Entfernen", "Remove"))
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        hint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = EventTapController.modifiers(event.cgEvent?.flags ?? [])
            if requireModifier && mods.isDisjoint(with: [.cmd, .ctrl, .alt]) {
                hint = Loc.t("⌘, ⌃ oder ⌥ dazu", "add ⌘, ⌃ or ⌥")
                return nil
            }
            onChange(KeyCombo(keyCode: event.keyCode, modifiers: mods))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

enum KeyNames {
    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N",
        46: "M", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        27: "ß", 24: "´", 33: "Ü", 30: "+", 39: "Ä", 41: "Ö", 42: "#", 43: ",", 47: ".", 44: "-", 50: "<",
        53: "Esc", 36: "↩", 76: "⌅", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
    ]

    static func describe(_ combo: KeyCombo) -> String {
        var s = ""
        if combo.modifiers.contains(.ctrl) { s += "⌃" }
        if combo.modifiers.contains(.alt) { s += "⌥" }
        if combo.modifiers.contains(.shift) { s += "⇧" }
        if combo.modifiers.contains(.cmd) { s += "⌘" }
        return s + (names[combo.keyCode] ?? Loc.t("Taste \(combo.keyCode)", "Key \(combo.keyCode)"))
    }
}
