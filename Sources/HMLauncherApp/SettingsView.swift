import SwiftUI
import HMLauncherCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var catalog: PluginCatalog
    @State private var search = ""
    @State private var selectedCategory: UUID?
    @State private var expanded: Set<String> = []
    @State private var renamingCategory: UUID?
    @State private var categoryName = ""

    private var categoryID: UUID { selectedCategory ?? model.config.favoritesID }
    private var category: HMLauncherCore.Category? { model.config.categories.first { $0.id == categoryID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                pluginBrowser.frame(minWidth: 300, idealWidth: 340).background(Color.panelSidebar)
                Divider()
                categoryList.frame(width: 220).background(Color.panelSidebar)
                Divider()
                entryList.frame(minWidth: 380).background(Color.panelBackground)
            }
            Divider()
            ShortcutSettingsView(shortcuts: $model.config.shortcuts)
                .padding(12)
                .background(Color.panelSidebar)
        }
        .preferredColorScheme(.dark)
        .foregroundColor(.white)
    }

    // MARK: Installed plugins

    private var pluginBrowser: some View {
        let groups = PluginGrouping.groups(catalog.items, search: search)
        return VStack(alignment: .leading, spacing: 8) {
            header("Plugins")
            HStack {
                TextField("Suchen", text: $search).textFieldStyle(.roundedBorder)
                Button { model.refreshCatalog() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Plugin-Liste aus Live neu laden")
            }
            if catalog.items.isEmpty {
                Text(model.isConnected ? "Lade Plugin-Liste …" : "Nicht mit Live verbunden – Live öffnen und HMLauncherBridge als Control Surface wählen.")
                    .font(.callout).foregroundColor(.dimText)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(groups) { group in
                        folderHeader(group)
                        if !search.isEmpty || expanded.contains(group.title) {
                            ForEach(group.items, id: \.uri) { item in pluginRow(item) }
                        }
                    }
                }
            }
            Text("Doppelklick oder ziehen fügt zu „\(category?.name ?? "")“ hinzu.")
                .font(.caption).foregroundColor(.dimText)
        }
        .padding(12)
    }

    private func folderHeader(_ group: PluginGroup) -> some View {
        let open = !search.isEmpty || expanded.contains(group.title)
        return Button {
            if expanded.contains(group.title) { expanded.remove(group.title) } else { expanded.insert(group.title) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold)).frame(width: 10)
                Image(systemName: group.title.hasPrefix("Live") ? "square.stack.3d.up" : "folder").foregroundColor(.accent)
                Text(group.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(group.items.count)").font(.caption).foregroundColor(.dimText)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!search.isEmpty)
    }

    private func pluginRow(_ item: PluginItem) -> some View {
        HStack(spacing: 8) {
            Text(item.name).font(.system(size: 13)).lineLimit(1)
            Spacer()
            Text(PluginGrouping.formatLabel(item))
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.rowBackground).cornerRadius(3)
                .foregroundColor(.dimText)
        }
        .padding(.leading, 26).padding(.trailing, 4).padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { add(item, to: categoryID) }
        .onDrag { NSItemProvider(object: item.uri as NSString) }
        .contextMenu {
            Button("Zu „\(category?.name ?? "")“ hinzufügen") { add(item, to: categoryID) }
            if categoryID != model.config.favoritesID {
                Button("Zu Favoriten hinzufügen") { add(item, to: model.config.favoritesID) }
            }
        }
        .help(item.path.joined(separator: " / "))
    }

    private func add(_ item: PluginItem, to id: UUID) { model.config.addEntry(item, to: id) }

    // MARK: Categories

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Kategorien")
            List {
                ForEach(model.config.categories) { c in
                    categoryRow(c)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                }
                .onMove { from, to in
                    guard let f = from.first else { return }
                    model.config.moveCategory(from: f, to: to > f ? to - 1 : to)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            Button {
                let id = model.config.addCategory(named: "Neue Kategorie")
                selectedCategory = id
                startRenaming(id)
            } label: { Label("Kategorie", systemImage: "plus") }
            .buttonStyle(.borderless)
        }
        .padding(12)
    }

    @ViewBuilder
    private func categoryRow(_ c: HMLauncherCore.Category) -> some View {
        let selected = c.id == categoryID
        HStack(spacing: 8) {
            Image(systemName: c.isFavorites ? "star.fill" : "folder").foregroundColor(c.isFavorites ? .accent : .dimText).frame(width: 16)
            if renamingCategory == c.id {
                TextField("Name", text: $categoryName, onCommit: { finishRenaming(c.id) })
                    .textFieldStyle(.roundedBorder)
                    .onExitCommand { renamingCategory = nil }
            } else {
                Text(c.name).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
            }
            Spacer()
            Text("\(c.entries.count)").font(.caption).foregroundColor(.dimText)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(selected ? Color.rowHighlight : Color.clear)
        .overlay(alignment: .leading) { if selected { Rectangle().fill(Color.accent).frame(width: 3) } }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { selectedCategory = c.id }
        .onTapGesture(count: 2) { if !c.isFavorites { startRenaming(c.id) } }
        .onDrop(of: [.text], isTargeted: nil) { drop($0, into: c.id) }
        .contextMenu {
            Button("Umbenennen") { startRenaming(c.id) }.disabled(c.isFavorites)
            Button("Löschen", role: .destructive) {
                model.config.deleteCategory(c.id)
                if selectedCategory == c.id { selectedCategory = nil }
            }
            .disabled(c.isFavorites)
        }
    }

    private func startRenaming(_ id: UUID) {
        categoryName = model.config.categories.first { $0.id == id }?.name ?? ""
        renamingCategory = id
    }

    private func finishRenaming(_ id: UUID) {
        let name = categoryName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { model.config.renameCategory(id, to: name) }
        renamingCategory = nil
    }

    // MARK: Entries (looks like the panel)

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                header(category?.name ?? "")
                Spacer()
                Text("So erscheint es im Panel").font(.caption).foregroundColor(.dimText)
            }
            if let category {
                if category.entries.isEmpty {
                    Text("Noch leer – Plugins links doppelklicken oder hierher ziehen.")
                        .font(.callout).foregroundColor(.dimText)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                List {
                    ForEach(Array(category.entries.enumerated()), id: \.element.id) { index, entry in
                        EntryRow(index: index, entry: entry,
                                 available: catalog.items.isEmpty || EntryResolver.resolve(entry, in: catalog.items) != nil,
                                 onIcon: { model.config.setIcon($0, entry: entry.id, in: category.id) },
                                 onName: { model.config.setDisplayName($0, entry: entry.id, in: category.id) },
                                 onRemove: { model.config.removeEntry(entry.id, from: category.id) })
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    }
                    .onMove { from, to in
                        guard let f = from.first else { return }
                        model.config.moveEntry(in: category.id, from: f, to: to > f ? to - 1 : to)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onDrop(of: [.text], isTargeted: nil) { drop($0, into: category.id) }
                Text("Ziehen sortiert · Klick aufs Icon oder Rechtsklick für Icon und Name · 1–9 = Zifferntasten im Panel")
                    .font(.caption).foregroundColor(.dimText)
            }
        }
        .padding(12)
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.system(size: 15, weight: .semibold))
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
    @State private var renaming = false
    @State private var name = ""
    @State private var hovered = false

    var body: some View {
        LauncherRow(number: index, symbol: IconCatalog.symbolName(for: entry.iconID), title: entry.title,
                    subtitle: available ? subtitle : "Nicht mehr in Live gefunden", active: hovered, available: available) {
            if hovered {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundColor(.dimText).help("Entfernen")
            }
        }
        .overlay(alignment: .leading) {
            // Click target over the icon opens the icon list.
            Color.clear.frame(width: 34, height: 42).padding(.leading, 30).contentShape(Rectangle())
                .onTapGesture { showIcons = true }
                .popover(isPresented: $showIcons, arrowEdge: .leading) { IconPicker(selected: entry.iconID) { onIcon($0); showIcons = false } }
        }
        .overlay {
            if renaming {
                TextField(entry.name, text: $name, onCommit: commitName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.leading, 76).padding(.trailing, 40)
                    .onExitCommand { renaming = false }
            }
        }
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Icon wählen …") { showIcons = true }
            Button("Anzeigename ändern …") { name = entry.displayName ?? entry.name; renaming = true }
            if entry.displayName != nil { Button("Originalnamen verwenden") { onName(nil) } }
            Divider()
            Button("Entfernen", role: .destructive, action: onRemove)
        }
    }

    private var subtitle: String {
        let path = entry.path.joined(separator: " / ")
        return entry.displayName == nil ? path : "\(entry.name) · \(path)"
    }

    private func commitName() {
        onName(name == entry.name ? nil : name)
        renaming = false
    }
}

private struct IconPicker: View {
    let selected: String
    let onPick: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 6), count: 6), spacing: 6) {
                ForEach(IconCatalog.all, id: \.id) { icon in
                    Button { onPick(icon.id) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: icon.symbolName).font(.system(size: 18))
                            Text(icon.label).font(.system(size: 10)).lineLimit(1)
                        }
                        .frame(width: 70, height: 54)
                        .background(icon.id == selected ? Color.rowHighlight : Color.rowBackground)
                        .overlay(alignment: .bottom) {
                            if icon.id == selected { Rectangle().fill(Color.accent).frame(height: 2) }
                        }
                        .cornerRadius(5)
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .frame(width: 470, height: 380)
        .background(Color.panelBackground)
        .preferredColorScheme(.dark)
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
