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
    /// Grouping ~3,300 items costs ~30 ms; recompute only when items or search change, not on every redraw.
    @State private var groups: [PluginGroup] = []

    private var categoryID: UUID { selectedCategory ?? model.config.favoritesID }
    private var category: HMLauncherCore.Category? { model.config.categories.first { $0.id == categoryID } }

    @State private var page = 0
    /// Lives here so the import preview survives switching pages.
    @StateObject private var importer = LESImportModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $page) {
                Text(Loc.t("Plugins & Kategorien", "Plugins & Categories")).tag(0)
                Text(Loc.t("LES-Import", "LES Import")).tag(2)
                Text(Loc.t("Versionen", "Versions")).tag(3)
                Text(Loc.t("Tastenkürzel", "Shortcuts")).tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 520)
            .padding(10)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Picker("", selection: $model.config.language) {
                    Text(Loc.t("Automatisch", "Automatic")).tag(Language?.none)
                    Text("Deutsch").tag(Language?.some(.de))
                    Text("English").tag(Language?.some(.en))
                }
                .frame(width: 130)
                .padding(.trailing, 12)
                .help(Loc.t("Sprache", "Language"))
            }
            Divider()
            switch page {
            case 0: pluginsPage
            case 2: LESImportPage(model: model, catalog: catalog, importer: importer, onDone: { page = 0 })
            case 3: VersionsPage(model: model)
            default: ShortcutsPage(shortcuts: $model.config.shortcuts, panelKeys: $model.config.panelKeys)
            }
        }
        .background(Color.panelSidebar)
        .preferredColorScheme(.dark)
        .foregroundColor(.white)
    }

    private var pluginsPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                pluginBrowser.frame(minWidth: 300, idealWidth: 340).background(Color.panelSidebar)
                Divider()
                categoryList.frame(width: 220).background(Color.panelSidebar)
                Divider()
                entryList.frame(minWidth: 380).background(Color.panelBackground)
            }
        }
    }

    // MARK: Installed plugins

    private var pluginBrowser: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Plugins")
            HStack {
                TextField(Loc.t("Suchen", "Search"), text: $search).textFieldStyle(.roundedBorder)
                Button { model.refreshCatalog() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(Loc.t("Plugin-Liste aus Live neu laden", "Reload plugin list from Live"))
            }
            if catalog.items.isEmpty {
                Text(model.isConnected ? Loc.t("Lade Plugin-Liste …", "Loading plugin list …") : Loc.t("Nicht mit Live verbunden – Live öffnen und HMLauncherBridge als Control Surface wählen.", "Not connected to Live – open Live and choose HMLauncherBridge as a control surface."))
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
            .onAppear { regroup(catalog.items) }
            .onChange(of: search) { _ in regroup(catalog.items) }
            .onReceive(catalog.$items.dropFirst()) { regroup($0) }
            Text(Loc.t("Doppelklick oder ziehen fügt zu „\(category?.name ?? "")“ hinzu.", "Double-click or drag to add to “\(category?.name ?? "")”."))
                .font(.caption).foregroundColor(.dimText)
        }
        .padding(12)
    }

    private func regroup(_ items: [PluginItem]) {
        groups = PluginGrouping.groups(items, search: search)
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
            Button(Loc.t("Zu „\(category?.name ?? "")“ hinzufügen", "Add to “\(category?.name ?? "")”")) { add(item, to: categoryID) }
            if categoryID != model.config.favoritesID {
                Button(Loc.t("Zu Favoriten hinzufügen", "Add to Favorites")) { add(item, to: model.config.favoritesID) }
            }
        }
        .help(item.path.joined(separator: " / "))
    }

    private func add(_ item: PluginItem, to id: UUID) { model.config.addEntry(item, to: id) }

    // MARK: Categories

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(Loc.t("Kategorien", "Categories"))
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
                let id = model.config.addCategory(named: Loc.t("Neue Kategorie", "New Category"))
                selectedCategory = id
                startRenaming(id)
            } label: { Label(Loc.t("Kategorie", "Category"), systemImage: "plus") }
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
        .onTapGesture(count: 2) { if !c.isFavorites { startRenaming(c.id) } }
        .simultaneousGesture(TapGesture().onEnded { selectedCategory = c.id })
        .onDrop(of: [.text], isTargeted: nil) { drop($0, into: c.id) }
        .contextMenu {
            Button(Loc.t("Umbenennen", "Rename")) { startRenaming(c.id) }.disabled(c.isFavorites)
            Button(Loc.t("Löschen", "Delete"), role: .destructive) {
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
                Text(Loc.t("So erscheint es im Panel", "This is how it looks in the panel")).font(.caption).foregroundColor(.dimText)
            }
            if let category {
                if category.entries.isEmpty {
                    Text(Loc.t("Noch leer – Plugins links doppelklicken oder hierher ziehen.", "Empty – double-click plugins on the left or drag them here."))
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
                Text(Loc.t("Ziehen sortiert · Klick aufs Icon oder Rechtsklick für Icon und Name · 1–9 = Zifferntasten im Panel", "Drag to reorder · click the icon or right-click for icon and name · 1–9 = number keys in the panel"))
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
                    subtitle: available ? subtitle : Loc.t("Nicht mehr in Live gefunden", "No longer found in Live"), active: hovered, available: available) {
            if hovered {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundColor(.dimText).help(Loc.t("Entfernen", "Remove"))
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
            Button(Loc.t("Icon wählen …", "Choose Icon …")) { showIcons = true }
            Button(Loc.t("Anzeigename ändern …", "Change Display Name …")) { name = entry.displayName ?? entry.name; renaming = true }
            if entry.displayName != nil { Button(Loc.t("Originalnamen verwenden", "Use Original Name")) { onName(nil) } }
            Divider()
            Button(Loc.t("Entfernen", "Remove"), role: .destructive, action: onRemove)
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

// MARK: - Shortcuts

struct ShortcutsPage: View {
    @Binding var shortcuts: ShortcutSettings
    @Binding var panelKeys: PanelKeyBindings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section(Loc.t("Plugin-Fenster", "Plugin Windows"), note: Loc.t("Nur aktiv, wenn Live vorne ist. Kürzel brauchen ⌘, ⌃ oder ⌥.", "Only active while Live is in front. Shortcuts need ⌘, ⌃ or ⌥."),
                        reset: { shortcuts = .default }) {
                    row(Loc.t("Fokussiertes Plugin-Fenster schließen", "Close focused plugin window"),
                        combos: Binding(get: { shortcuts.closeFocused.map { [$0] } ?? [] },
                                        set: { shortcuts.closeFocused = $0.last }),
                        maxCount: 1, requireModifier: true)
                    row(Loc.t("Alle Plugin-Fenster schließen", "Close all plugin windows"), combos: $shortcuts.closeAll, maxCount: 4, requireModifier: true)
                }
                section(Loc.t("Im Panel", "In the Panel"), note: Loc.t("Fest: 1–9 fügen die Zeile ein, Tippen filtert, ⌫ löscht im Filter.", "Fixed: 1–9 insert that row, typing filters, ⌫ deletes in the filter."),
                        reset: { panelKeys = .default }) {
                    ForEach(PanelKeyAction.allCases, id: \.self) { action in
                        row(action.label, combos: Binding(get: { panelKeys[action] }, set: { panelKeys[action] = $0 }),
                            maxCount: 4, requireModifier: false)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.panelBackground)
    }

    private func section<Content: View>(_ title: String, note: String, reset: @escaping () -> Void,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(Loc.t("Standard wiederherstellen", "Restore Defaults"), action: reset).buttonStyle(.borderless).foregroundColor(.accent)
            }
            Text(note).font(.caption).foregroundColor(.dimText)
            VStack(spacing: 4) { content() }
        }
    }

    private func row(_ label: String, combos: Binding<[KeyCombo]>, maxCount: Int, requireModifier: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13)).frame(width: 260, alignment: .leading)
            ForEach(Array(combos.wrappedValue.enumerated()), id: \.offset) { i, combo in
                KeyRecorder(combo: combo, requireModifier: requireModifier,
                            onChange: { combos.wrappedValue[i] = $0 },
                            onRemove: { combos.wrappedValue.remove(at: i) })
            }
            if combos.wrappedValue.count < maxCount {
                KeyRecorder(combo: nil, requireModifier: requireModifier,
                            onChange: { combos.wrappedValue.append($0) }, onRemove: nil)
            }
            if combos.wrappedValue.isEmpty {
                Text(Loc.t("aus", "off")).font(.caption).foregroundColor(.dimText)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(Color.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 5))
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
                    .font(.system(size: 12, weight: .medium, design: .rounded))
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
