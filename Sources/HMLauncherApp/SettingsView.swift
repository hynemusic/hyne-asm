import SwiftUI
import HMLauncherCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var catalog: PluginCatalog
    @State private var search = ""
    @State private var selectedCategory: UUID?
    @State private var selectedEntry: UUID?
    @State private var renaming: UUID?

    private var category: HMLauncherCore.Category? {
        model.config.categories.first { $0.id == (selectedCategory ?? model.config.favoritesID) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                pluginBrowser.frame(minWidth: 300)
                categoryList.frame(minWidth: 200, maxWidth: 260)
                entryList.frame(minWidth: 360)
            }
            Divider()
            ShortcutSettingsView(shortcuts: $model.config.shortcuts).padding(12)
        }
    }

    // MARK: Installed plugins

    private var groupedItems: [(String, [PluginItem])] {
        let filtered = catalog.items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        let groups = Dictionary(grouping: filtered) { item -> String in
            switch item.source {
            case .plugins: return "Plugins · " + (item.path.first ?? "?")
            case .instruments: return "Live · Instruments"
            case .audioEffects: return "Live · Audio Effects"
            case .midiEffects: return "Live · MIDI Effects"
            case .maxForLive: return "Live · Max for Live"
            }
        }
        return groups.keys.sorted().map { key in
            (key, groups[key]!.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    private var pluginBrowser: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Plugins suchen", text: $search).textFieldStyle(.roundedBorder)
                Button { model.refreshCatalog() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Plugin-Liste aus Live neu laden")
            }
            if catalog.items.isEmpty {
                Text(model.isConnected ? "Lade Plugin-Liste …" : "Nicht mit Live verbunden – Live öffnen und HMLauncherBridge als Control Surface wählen.")
                    .foregroundColor(.secondary).font(.callout)
            }
            List {
                ForEach(groupedItems, id: \.0) { group, items in
                    Section(group) {
                        ForEach(items, id: \.uri) { item in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                Text(item.path.joined(separator: " / ")).font(.caption).foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { add(item) }
                            .onDrag { NSItemProvider(object: item.uri as NSString) }
                            .contextMenu { Button("Zu „\(category?.name ?? "")“ hinzufügen") { add(item) } }
                        }
                    }
                }
            }
            Text("Doppelklick oder ziehen, um zur gewählten Kategorie hinzuzufügen.").font(.caption).foregroundColor(.secondary)
        }
        .padding(10)
    }

    private func add(_ item: PluginItem) {
        model.config.addEntry(item, to: category?.id ?? model.config.favoritesID)
    }

    // MARK: Categories

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kategorien").font(.headline)
            List(selection: $selectedCategory) {
                ForEach(model.config.categories) { c in
                    categoryRow(c).tag(c.id)
                }
                .onMove { from, to in
                    guard let f = from.first else { return }
                    model.config.moveCategory(from: f, to: to > f ? to - 1 : to)
                }
            }
            HStack {
                Button { selectedCategory = model.config.addCategory(named: "Neue Kategorie"); renaming = selectedCategory } label: { Image(systemName: "plus") }
                Button { if let id = selectedCategory { model.config.deleteCategory(id); selectedCategory = nil } } label: { Image(systemName: "minus") }
                    .disabled(category?.isFavorites ?? true)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private func categoryRow(_ c: HMLauncherCore.Category) -> some View {
        if renaming == c.id {
            TextField("Name", text: Binding(
                get: { c.name },
                set: { model.config.renameCategory(c.id, to: $0) }
            ), onCommit: { renaming = nil })
        } else {
            HStack {
                if c.isFavorites { Image(systemName: "star.fill").foregroundColor(.yellow) }
                Text(c.name)
                Spacer()
                Text("\(c.entries.count)").foregroundColor(.secondary)
            }
            .onTapGesture(count: 2) { if !c.isFavorites { renaming = c.id } }
            .onDrop(of: [.text], isTargeted: nil) { providers in drop(providers, into: c.id) }
        }
    }

    // MARK: Entries

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category?.name ?? "").font(.headline)
            if let category {
                List(selection: $selectedEntry) {
                    ForEach(Array(category.entries.enumerated()), id: \.element.id) { index, entry in
                        EntryRow(index: index, entry: entry,
                                 available: EntryResolver.resolve(entry, in: catalog.items) != nil || catalog.items.isEmpty,
                                 onIcon: { model.config.setIcon($0, entry: entry.id, in: category.id) },
                                 onName: { model.config.setDisplayName($0, entry: entry.id, in: category.id) },
                                 onRemove: { model.config.removeEntry(entry.id, from: category.id) })
                            .tag(entry.id)
                    }
                    .onMove { from, to in
                        guard let f = from.first else { return }
                        model.config.moveEntry(in: category.id, from: f, to: to > f ? to - 1 : to)
                    }
                }
                .onDeleteCommand {
                    if let id = selectedEntry { model.config.removeEntry(id, from: category.id) }
                }
                .onDrop(of: [.text], isTargeted: nil) { providers in drop(providers, into: category.id) }
                Text("Ziehen zum Sortieren · Entf entfernt · Plätze 1–9 per Zifferntaste im Panel").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(10)
    }

    private func drop(_ providers: [NSItemProvider], into categoryID: UUID) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let uri = object as? String else { return }
                Task { @MainActor in
                    if let item = catalog.items.first(where: { $0.uri == uri }) {
                        model.config.addEntry(item, to: categoryID)
                    }
                }
            }
        }
        return true
    }
}

private struct EntryRow: View {
    let index: Int
    let entry: Entry
    let available: Bool
    let onIcon: (String) -> Void
    let onName: (String?) -> Void
    let onRemove: () -> Void
    @State private var showIcons = false
    @State private var name = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(index < 9 ? "\(index + 1)" : "").foregroundColor(.secondary).frame(width: 14)
            Button { showIcons.toggle() } label: {
                Image(systemName: IconCatalog.symbolName(for: entry.iconID)).frame(width: 22)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showIcons) { iconGrid }
            VStack(alignment: .leading, spacing: 1) {
                TextField(entry.name, text: $name, onCommit: { onName(name) })
                    .textFieldStyle(.plain)
                    .onAppear { name = entry.displayName ?? "" }
                Text(available ? entry.path.joined(separator: " / ") : "Nicht mehr in Live gefunden")
                    .font(.caption).foregroundColor(available ? .secondary : .orange)
            }
            Spacer()
            Button(action: onRemove) { Image(systemName: "xmark.circle") }.buttonStyle(.borderless)
        }
        .opacity(available ? 1 : 0.6)
    }

    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(64)), count: 4), spacing: 8) {
            ForEach(IconCatalog.all, id: \.id) { icon in
                Button { onIcon(icon.id); showIcons = false } label: {
                    VStack(spacing: 4) {
                        Image(systemName: icon.symbolName).font(.system(size: 18))
                        Text(icon.label).font(.caption2)
                    }
                    .frame(width: 60, height: 48)
                    .background(icon.id == entry.iconID ? Color.accentColor.opacity(0.25) : .clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
    }
}

// MARK: - Close-window shortcuts

struct ShortcutSettingsView: View {
    @Binding var shortcuts: ShortcutSettings

    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            Text("Plugin-Fenster").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Fokussiertes schließen", isOn: Binding(
                    get: { shortcuts.closeFocused != nil },
                    set: { shortcuts.closeFocused = $0 ? ShortcutSettings.default.closeFocused : nil }))
                if let combo = shortcuts.closeFocused {
                    KeyRecorder(combo: combo) { shortcuts.closeFocused = $0 }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Alle schließen", isOn: Binding(
                    get: { !shortcuts.closeAll.isEmpty },
                    set: { shortcuts.closeAll = $0 ? ShortcutSettings.default.closeAll : [] }))
                HStack {
                    ForEach(Array(shortcuts.closeAll.enumerated()), id: \.offset) { i, combo in
                        KeyRecorder(combo: combo) { shortcuts.closeAll[i] = $0 }
                    }
                }
            }
            Spacer()
        }
    }
}

/// Shows a key combo; click, then press the new combo (Esc alone cancels).
struct KeyRecorder: View {
    let combo: KeyCombo
    let onChange: (KeyCombo) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Tasten drücken …" : KeyNames.describe(combo)) { recording ? stop() : start() }
            .frame(minWidth: 90)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = EventTapController.modifiers(event.cgEvent?.flags ?? [])
            if !(event.keyCode == 53 && mods.isEmpty), !mods.isEmpty {
                onChange(KeyCombo(keyCode: event.keyCode, modifiers: mods))
            }
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
        53: "Esc", 36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func describe(_ combo: KeyCombo) -> String {
        var s = ""
        if combo.modifiers.contains(.ctrl) { s += "⌃" }
        if combo.modifiers.contains(.alt) { s += "⌥" }
        if combo.modifiers.contains(.shift) { s += "⇧" }
        if combo.modifiers.contains(.cmd) { s += "⌘" }
        return s + (names[combo.keyCode] ?? "Key \(combo.keyCode)")
    }
}
