import SwiftUI
import UniformTypeIdentifiers
import HMLauncherCore

/// Drag payload for entries dragged out of the right-hand list (onto a category). Its own type, so rows that
/// accept plugin URIs (text) from the browser don't react while entries are reordered.
let entriesDragType = UTType(exportedAs: "local.hm.launcher.entries")

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var catalog: PluginCatalog
    @State private var search = ""
    @State private var selectedCategory: UUID?
    @State private var expanded: Set<String> = []
    @State private var renamingCategory: UUID?
    /// Grouping ~3,300 items costs ~30 ms; recompute only when items or search change, not on every redraw.
    @State private var groups: [PluginGroup] = []
    @State private var variants: [String: PluginVariantGroup] = [:]
    @State private var collapsed: Set<UUID> = []
    @State private var selection: Set<UUID> = []
    @State private var selectionAnchor: UUID?
    @State private var bulkIcons = false
    @State private var dropCategory: UUID?
    /// Held without observing it: drag updates redraw only the rows (which observe it), not the whole window.
    @State private var dropState = DropState()

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
                Text(model.isConnected ? Loc.t("Lade Plugin-Liste …", "Loading plugin list …") : Loc.t("Nicht mit Live verbunden – Live öffnen und ASMbridge als Control Surface wählen.", "Not connected to Live – open Live and choose ASMbridge as a control surface."))
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

    /// One row per plugin (its best format); the other formats are kept for the badges and "Add as …".
    private func regroup(_ items: [PluginItem]) {
        let collapsed = PluginVariants.collapse(items)
        variants = Dictionary(collapsed.map { ($0.preferred.uri, $0) }, uniquingKeysWith: { a, _ in a })
        groups = PluginGrouping.groups(collapsed.map(\.preferred), search: search)
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
        .contextMenu {
            if let rule = folderRule(group) {
                ColorMenu(title: folderRuleTitle(rule), current: model.config.colorRule(rule), allowInherit: false) { picked in
                    model.config.setColorRule(picked == ColorPalette.noneID ? nil : picked, for: rule)
                }
            }
        }
    }

    /// Manufacturer folders and Live's device groups can carry a color rule.
    private func folderRule(_ group: PluginGroup) -> ColorRule? {
        guard let first = group.items.first else { return nil }
        if first.source == .plugins {
            return group.title == PluginGrouping.otherVST2 ? nil : .vendor(group.title)
        }
        return ColorRule.forItem(first).first
    }

    private func folderRuleTitle(_ rule: ColorRule) -> String {
        switch rule {
        case .liveDevices: return Loc.t("Farbe für alle Live-Devices", "Color for All Live Devices")
        case .vendor(let v): return Loc.t("Farbe für alle von \(v)", "Color for All by \(v)")
        }
    }

    private func pluginRow(_ item: PluginItem) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color(label: model.config.colorID(for: item)) ?? .clear).frame(width: 4, height: 14)
            Text(item.name).font(.system(size: 13)).lineLimit(1)
            Spacer()
            ForEach(variants[item.uri]?.formats ?? [PluginGrouping.formatLabel(item)], id: \.self) { format in
                Text(format)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.rowBackground).cornerRadius(3)
                    .foregroundColor(format == PluginGrouping.formatLabel(item) ? .white : .dimText)
            }
        }
        .padding(.leading, 18).padding(.trailing, 4).padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { add(item, to: categoryID) }
        .onDrag { NSItemProvider(object: item.uri as NSString) }
        .contextMenu {
            Button(Loc.t("Zu „\(category?.name ?? "")“ hinzufügen", "Add to “\(category?.name ?? "")”")) { add(item, to: categoryID) }
            if let others = variants[item.uri]?.variants.dropFirst(), !others.isEmpty {
                ForEach(Array(others), id: \.uri) { v in
                    Button(Loc.t("Als \(PluginGrouping.formatLabel(v)) hinzufügen", "Add as \(PluginGrouping.formatLabel(v))")) { add(v, to: categoryID) }
                }
            }
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
                InlineNameField(initial: c.name,
                                onCommit: { model.config.renameCategory(c.id, to: $0); renamingCategory = nil },
                                onCancel: { renamingCategory = nil })
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
        .overlay { if dropCategory == c.id && c.id != categoryID { RoundedRectangle(cornerRadius: 4).stroke(Color.accent, lineWidth: 2) } }
        .onDrop(of: [entriesDragType, .text], isTargeted: Binding(get: { dropCategory == c.id }, set: { dropCategory = $0 ? c.id : nil })) {
            dropOnCategory($0, c.id)
        }
        .contextMenu {
            Button(Loc.t("Umbenennen", "Rename")) { startRenaming(c.id) }.disabled(c.isFavorites)
            Button(Loc.t("Neuer Ordner", "New Folder")) { selectedCategory = c.id; newFolder(in: c.id) }
            Button(Loc.t("Löschen", "Delete"), role: .destructive) {
                model.config.deleteCategory(c.id)
                if selectedCategory == c.id { selectedCategory = nil }
            }
            .disabled(c.isFavorites)
        }
    }

    private func startRenaming(_ id: UUID) {
        renamingCategory = id
    }

    // MARK: Entries (looks like the panel)

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                header(category?.name ?? "")
                Button { newFolder() } label: { Label(Loc.t("Ordner", "Folder"), systemImage: "folder.badge.plus") }
                    .buttonStyle(.borderless).foregroundColor(.accent)
                    .help(Loc.t("Neuen Ordner in dieser Kategorie anlegen", "Create a new folder in this category"))
                Spacer()
                Text(Loc.t("So erscheint es im Panel", "This is how it looks in the panel")).font(.caption).foregroundColor(.dimText)
            }
            if let category {
                if category.entries.isEmpty {
                    Text(Loc.t("Noch leer – Plugins links doppelklicken oder hierher ziehen.", "Empty – double-click plugins on the left or drag them here."))
                        .font(.callout).foregroundColor(.dimText)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                // Always occupies its slot: a bar that appears on the first click would shift the list under
                // the mouse and cancel the drag that click starts.
                selectionBar(category)
                List(selection: $selection) {
                    let rows = flatRows(category)
                    ForEach(rows) { row in
                        entryRow(row, in: category)
                            .tag(row.id)
                            // Own drag & drop instead of List.onMove: onMove keeps its drag data private, so entries
                            // could never be dropped onto a category. This payload works for rows and categories alike.
                            .onDrag { dragPayload(for: row.id) } preview: {
                                // Just a count next to the cursor instead of a shrunken copy of the row.
                                DragCountBadge(count: selection.contains(row.id) ? selection.count : 1)
                            }
                            .onDrop(of: [entriesDragType, .text], delegate: RowDropDelegate(
                                row: SettingsViewRow(id: row.id, isFolder: row.entry.isFolder), drop: dropState,
                                perform: { spot, providers in dropOnRow(row, spot, providers, in: category) }))
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 2, leading: row.folderID == nil ? 0 : 28, bottom: 2, trailing: 0))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onDrop(of: [entriesDragType, .text], isTargeted: nil) { providers in
                    // Empty area below the rows: entries move to the end, browser plugins are added.
                    if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(entriesDragType.identifier) }) {
                        loadEntryIDs(p) { model.config.moveEntries($0, toFolder: nil, before: nil, in: category.id) }
                        return true
                    }
                    return drop(providers, into: category.id)
                }
                .onDeleteCommand { removeSelection() }
                .onChange(of: categoryID) { _ in selection = []; selectionAnchor = nil }
                Text(Loc.t("⇧-Klick wählt mehrere, ⌘-Klick einzelne dazu · ⌘G gruppiert · Ziehen sortiert (auch in/aus Ordnern) · Rechtsklick für Icon, Name und Ordner",
                           "⇧-click selects a range, ⌘-click adds single ones · ⌘G groups · drag to reorder (also in/out of folders) · right-click for icon, name and folders"))
                    .font(.caption).foregroundColor(.dimText)
            }
        }
        .padding(12)
    }

    // MARK: Folders

    private struct FlatRow: Identifiable {
        let entry: Entry
        let index: Int          // position inside its container (top level or folder)
        let folderID: UUID?     // set for plugins shown inside an expanded folder
        var id: UUID { entry.id }
    }

    private func flatRows(_ category: HMLauncherCore.Category) -> [FlatRow] {
        category.entries.enumerated().flatMap { i, e -> [FlatRow] in
            let top = FlatRow(entry: e, index: i, folderID: nil)
            guard e.isFolder, !collapsed.contains(e.id) else { return [top] }
            return [top] + (e.children ?? []).enumerated().map { FlatRow(entry: $1, index: $0, folderID: e.id) }
        }
    }

    // MARK: Selection (⇧ range, ⌘ toggle)

    /// Rows carry their own drag (`onDrag`), which keeps clicks from reaching the List's native selection,
    /// so clicks on a row select here. The List binding still handles clicks on the row margins and ⌫.
    private func select(_ id: UUID, rows: [FlatRow]) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor = selectionAnchor,
           let a = rows.firstIndex(where: { $0.id == anchor }), let b = rows.firstIndex(where: { $0.id == id }) {
            selection = Set(rows[min(a, b)...max(a, b)].map(\.id))
        } else if flags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            selectionAnchor = id
        } else {
            selection = [id]
            selectionAnchor = id
        }
    }

    /// Dragging a selected row carries the whole selection.
    private func dragPayload(for id: UUID) -> NSItemProvider {
        let ids = selection.contains(id) ? model.config.orderedEntryIDs(in: categoryID).filter(selection.contains) : [id]
        EntryDrag.ids = ids
        let provider = NSItemProvider()
        let data = Data(ids.map(\.uuidString).joined(separator: ",").utf8)
        provider.registerDataRepresentation(forTypeIdentifier: entriesDragType.identifier, visibility: .ownProcess) { done in
            done(data, nil)
            return nil
        }
        return provider
    }

    /// Uses the ids remembered at drag start right away. Loading them from the item provider is asynchronous
    /// and AppKit only delivers after its drop animation, which made every drop visibly wait.
    private func loadEntryIDs(_ provider: NSItemProvider, _ then: @escaping ([UUID]) -> Void) {
        if let ids = EntryDrag.ids {
            EntryDrag.ids = nil
            then(ids)
            return
        }
        provider.loadDataRepresentation(forTypeIdentifier: entriesDragType.identifier) { data, _ in
            guard let data, let text = String(data: data, encoding: .utf8) else { return }
            let ids = text.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
            DispatchQueue.main.async { then(ids) }
        }
    }

    /// Drop on a row: before/after it in its container, or into a folder. Entries move, browser plugins are added.
    private func dropOnRow(_ row: FlatRow, _ spot: DropSpot, _ providers: [NSItemProvider], in category: HMLauncherCore.Category) -> Bool {
        let folder: UUID? = spot == .into ? row.entry.id : row.folderID
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(entriesDragType.identifier) }) {
            loadEntryIDs(p) { ids in
                guard !ids.contains(row.id) else { return } // dropped onto itself
                model.config.moveEntries(ids, toFolder: folder, before: anchor(for: row, spot, excluding: Set(ids), in: category.id), in: category.id)
            }
            return true
        }
        for p in providers {
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let uri = obj as? String else { return }
                DispatchQueue.main.async {
                    if let item = catalog.items.first(where: { $0.uri == uri }) { model.config.addEntry(item, to: category.id, folder: folder) }
                }
            }
        }
        return true
    }

    /// The entry the dropped ones go in front of (nil = end of the container).
    private func anchor(for row: FlatRow, _ spot: DropSpot, excluding moving: Set<UUID>, in categoryID: UUID) -> UUID? {
        switch spot {
        case .into: return nil
        case .before: return row.id
        case .after:
            let container = row.folderID.flatMap { model.config.findEntry($0, in: categoryID)?.children }
                ?? model.config.categories.first { $0.id == categoryID }?.entries ?? []
            guard let i = container.firstIndex(where: { $0.id == row.id }) else { return nil }
            return container[(i + 1)...].first { !moving.contains($0.id) }?.id
        }
    }

    /// Entries from the right-hand list move into the category; plugin URIs from the browser are added.
    private func dropOnCategory(_ providers: [NSItemProvider], _ target: UUID) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(entriesDragType.identifier) }) else {
            return drop(providers, into: target)
        }
        let source = categoryID
        loadEntryIDs(provider) { ids in
            model.config.moveEntries(ids, toCategory: target, from: source)
            selection = []
        }
        return true
    }

    private func moveSelection(toCategory target: UUID) {
        model.config.moveEntries(model.config.orderedEntryIDs(in: categoryID).filter(selection.contains), toCategory: target, from: categoryID)
        selection = []
    }

    private func groupSelection() {
        guard let folder = model.config.groupEntries(Array(selection), in: categoryID, named: Loc.t("Neue Gruppe", "New Group")) else { return }
        selection = [folder]
        collapsed.remove(folder)
        renamingEntry = folder
    }

    private func removeSelection() {
        for id in selection { model.config.removeEntry(id, from: categoryID) }
        selection = []
    }

    private func setColorForSelection(_ color: String?) {
        for id in selection { model.config.setColor(color, entry: id, in: categoryID) }
    }

    private func setIconForSelection(_ icon: String) {
        for id in selection { model.config.setIcon(icon, entry: id, in: categoryID) }
    }

    private func moveSelection(toFolder folder: UUID?) {
        model.config.moveEntries(model.config.orderedEntryIDs(in: categoryID).filter(selection.contains),
                                 toFolder: folder, before: nil, in: categoryID)
    }

    @ViewBuilder
    private func selectionBar(_ category: HMLauncherCore.Category) -> some View {
        if selection.isEmpty {
            Text(Loc.t("Klick wählt aus · ⇧/⌘-Klick für mehrere · ⌘G gruppiert", "Click selects · ⇧/⌘-click for several · ⌘G groups"))
                .font(.caption).foregroundColor(.dimText)
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .leading)
                .padding(.horizontal, 10)
        } else {
            activeSelectionBar(category)
        }
    }

    private func activeSelectionBar(_ category: HMLauncherCore.Category) -> some View {
        let folders = category.entries.filter { $0.isFolder && !selection.contains($0.id) }
        return HStack(spacing: 10) {
            Text(Loc.t("\(selection.count) ausgewählt", "\(selection.count) selected")).font(.system(size: 12, weight: .semibold))
            Button { groupSelection() } label: { Label(Loc.t("Gruppieren", "Group"), systemImage: "folder.badge.plus") }
                .keyboardShortcut("g", modifiers: .command)
                .help(Loc.t("Ausgewählte Plugins in einen neuen Ordner (⌘G)", "Put the selected plugins into a new folder (⌘G)"))
            Button { bulkIcons = true } label: { Label("Icon", systemImage: "paintpalette") }
                .popover(isPresented: $bulkIcons) { IconPicker(selected: "") { setIconForSelection($0); bulkIcons = false } }
            ColorMenu(title: Loc.t("Farbe", "Color"), onPick: setColorForSelection)
                .fixedSize()
            Menu(Loc.t("In Ordner", "To Folder")) {
                ForEach(folders) { f in Button(f.title) { moveSelection(toFolder: f.id) } }
                Divider()
                Button(Loc.t("Aus Ordnern nehmen", "Take Out of Folders")) { moveSelection(toFolder: nil) }
            }
            .fixedSize()
            Menu(Loc.t("In Kategorie", "To Category")) {
                ForEach(model.config.categories.filter { $0.id != category.id }) { c in
                    Button(c.name) { moveSelection(toCategory: c.id) }
                }
            }
            .fixedSize()
            Button(role: .destructive) { removeSelection() } label: { Label(Loc.t("Entfernen", "Remove"), systemImage: "trash") }
            Spacer()
            Button(Loc.t("Auswahl aufheben", "Deselect")) { selection = [] }
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.borderless)
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color.rowHighlight)
        .overlay(alignment: .leading) { Rectangle().fill(Color.accent).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func newFolder(in categoryID: UUID? = nil) {
        let id = categoryID ?? self.categoryID
        let folder = model.config.addFolder(named: Loc.t("Neuer Ordner", "New Folder"), to: id)
        collapsed.remove(folder)
        renamingEntry = folder
    }

    @State private var renamingEntry: UUID?

    private func entryRow(_ row: FlatRow, in category: HMLauncherCore.Category) -> some View {
        let entry = row.entry
        let folders = category.entries.filter(\.isFolder)
        let multi = selection.contains(entry.id) && selection.count > 1
        return EntryRow(
            index: row.index, entry: entry,
            isSelected: selection.contains(entry.id),
            selectionCount: multi ? selection.count : 1,
            onSelect: { select(entry.id, rows: flatRows(category)) },
            onGroup: groupSelection,
            available: entry.isFolder || catalog.items.isEmpty || catalog.index.resolve(entry) != nil,
            isExpanded: !collapsed.contains(entry.id),
            folders: folders.map { ($0.id, $0.title) },
            inFolder: row.folderID != nil,
            startRenaming: Binding(get: { renamingEntry == entry.id }, set: { if !$0 { renamingEntry = nil } }),
            onToggle: { if collapsed.contains(entry.id) { collapsed.remove(entry.id) } else { collapsed.insert(entry.id) } },
            onIcon: { icon in multi ? setIconForSelection(icon) : model.config.setIcon(icon, entry: entry.id, in: category.id) },
            onName: { name in
                if entry.isFolder { if let name { model.config.renameFolder(entry.id, in: category.id, to: name) } }
                else { model.config.setDisplayName(name, entry: entry.id, in: category.id) }
            },
            onRemove: { multi ? removeSelection() : model.config.removeEntry(entry.id, from: category.id) },
            onMoveTo: { folder in multi ? moveSelection(toFolder: folder) : model.config.moveEntry(entry.id, toFolder: folder, in: category.id) },
            categories: model.config.categories.filter { $0.id != category.id }.map { ($0.id, $0.name) },
            onMoveToCategory: { target in
                if multi { moveSelection(toCategory: target) } else { model.config.moveEntries([entry.id], toCategory: target, from: category.id) }
            },
            color: Color(label: model.config.colorID(for: entry)),
            ownColor: entry.colorID,
            rules: entry.isFolder ? [] : ColorRule.forItem(catalog.index.resolve(entry)
                ?? PluginItem(uri: entry.uri, name: entry.name, source: entry.source, path: entry.path)),
            ruleColor: { model.config.colorRule($0) },
            onColor: { color in multi ? setColorForSelection(color) : model.config.setColor(color, entry: entry.id, in: category.id) },
            onRuleColor: { model.config.setColorRule($1, for: $0) },
            onDissolve: { model.config.dissolveFolder(entry.id, in: category.id) },
            drop: dropState)
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
    let isSelected: Bool
    let selectionCount: Int
    let onSelect: () -> Void
    let onGroup: () -> Void
    let available: Bool
    let isExpanded: Bool
    let folders: [(UUID, String)]
    let inFolder: Bool
    @Binding var startRenaming: Bool
    let onToggle: () -> Void
    let onIcon: (String) -> Void
    let onName: (String?) -> Void
    let onRemove: () -> Void
    let onMoveTo: (UUID?) -> Void
    let categories: [(UUID, String)]
    let onMoveToCategory: (UUID) -> Void
    let color: Color?
    let ownColor: String?
    let rules: [ColorRule]
    let ruleColor: (ColorRule) -> String?
    let onColor: (String?) -> Void
    let onRuleColor: (ColorRule, String?) -> Void
    let onDissolve: () -> Void
    @ObservedObject var drop: DropState
    private var dropSpot: DropSpot? { drop.marker?.id == entry.id ? drop.marker?.spot : nil }
    @State private var showIcons = false
    @State private var renaming = false
    @State private var name = ""
    @State private var hovered = false

    var body: some View {
        LauncherRow(number: index, symbol: IconCatalog.symbolName(for: entry.iconID), title: entry.title,
                    subtitle: subtitle, active: isSelected || hovered || dropSpot == .into, available: available, color: color) {
            if entry.isFolder {
                Text("\(entry.children?.count ?? 0)").font(.caption).foregroundColor(.dimText)
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless).foregroundColor(.dimText)
            }
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
                // Focuses itself, so typing (and ⌫) goes into the name, not to the list's delete command.
                InlineNameField(initial: name,
                                onCommit: { new in renaming = false; onName(!entry.isFolder && new == entry.name ? nil : new) },
                                onCancel: { renaming = false })
                    .padding(.leading, 76).padding(.trailing, 40)
            }
        }
        .onHover { hovered = $0 }
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
        .overlay(alignment: dropSpot == .after ? .bottom : .top) {
            if dropSpot == .before || dropSpot == .after {
                Rectangle().fill(Color.accent).frame(height: 3).offset(y: dropSpot == .before ? -3 : 3)
            }
        }
        .overlay { if dropSpot == .into { RoundedRectangle(cornerRadius: 5).stroke(Color.accent, lineWidth: 2) } }
        .onChange(of: startRenaming) { start in
            if start { name = entry.title; renaming = true; startRenaming = false }
        }
        .onAppear { if startRenaming { name = entry.title; renaming = true; startRenaming = false } }
        .contextMenu { menu }
    }

    @ViewBuilder private var menu: some View {
        if selectionCount > 1 {
            Text(Loc.t("\(selectionCount) ausgewählt", "\(selectionCount) selected"))
            Button(Loc.t("Gruppieren (⌘G)", "Group (⌘G)"), action: onGroup)
            Button(Loc.t("Icon für alle wählen …", "Choose Icon for All …")) { showIcons = true }
            ColorMenu(title: Loc.t("Farbe für alle", "Color for All"), onPick: onColor)
            if !folders.isEmpty {
                Menu(Loc.t("In Ordner verschieben", "Move to Folder")) {
                    ForEach(folders, id: \.0) { id, title in Button(title) { onMoveTo(id) } }
                }
            }
            Button(Loc.t("Aus Ordnern nehmen", "Take Out of Folders")) { onMoveTo(nil) }
            categoryMenu
            Divider()
            Button(Loc.t("Alle entfernen", "Remove All"), role: .destructive, action: onRemove)
        } else {
            singleMenu
        }
    }

    @ViewBuilder private var colorMenus: some View {
        ColorMenu(title: Loc.t("Farbe", "Color"), current: ownColor, allowInherit: !entry.isFolder, onPick: onColor)
        ForEach(rules, id: \.self) { rule in
            ColorMenu(title: ruleTitle(rule), current: ruleColor(rule), allowInherit: false) { picked in
                onRuleColor(rule, picked == ColorPalette.noneID ? nil : picked)
            }
        }
    }

    private func ruleTitle(_ rule: ColorRule) -> String {
        switch rule {
        case .liveDevices: return Loc.t("Farbe für alle Live-Devices", "Color for All Live Devices")
        case .vendor(let v): return Loc.t("Farbe für alle von \(v)", "Color for All by \(v)")
        }
    }

    @ViewBuilder private var singleMenu: some View {
        Button(Loc.t("Icon wählen …", "Choose Icon …")) { showIcons = true }
        colorMenus
        if entry.isFolder {
            Button(Loc.t("Umbenennen …", "Rename …")) { name = entry.title; renaming = true }
            Button(isExpanded ? Loc.t("Zuklappen", "Collapse") : Loc.t("Aufklappen", "Expand"), action: onToggle)
            Divider()
            categoryMenu
            Divider()
            Button(Loc.t("Ordner auflösen", "Dissolve Folder"), action: onDissolve)
            Button(Loc.t("Ordner löschen", "Delete Folder"), role: .destructive, action: onRemove)
        } else {
            Button(Loc.t("Anzeigename ändern …", "Change Display Name …")) { name = entry.displayName ?? entry.name; renaming = true }
            if entry.displayName != nil { Button(Loc.t("Originalnamen verwenden", "Use Original Name")) { onName(nil) } }
            Divider()
            let targets = folders
            if !targets.isEmpty {
                Menu(Loc.t("In Ordner verschieben", "Move to Folder")) {
                    ForEach(targets, id: \.0) { id, title in Button(title) { onMoveTo(id) } }
                }
            }
            if inFolder { Button(Loc.t("Aus Ordner nehmen", "Take Out of Folder")) { onMoveTo(nil) } }
            categoryMenu
            Divider()
            Button(Loc.t("Entfernen", "Remove"), role: .destructive, action: onRemove)
        }
    }

    @ViewBuilder private var categoryMenu: some View {
        if !categories.isEmpty {
            Menu(Loc.t("In Kategorie verschieben", "Move to Category")) {
                ForEach(categories, id: \.0) { id, name in Button(name) { onMoveToCategory(id) } }
            }
        }
    }

    private var subtitle: String? {
        if entry.isFolder { return Loc.t("Ordner", "Folder") }
        guard available else { return Loc.t("Nicht mehr in Live gefunden", "No longer found in Live") }
        let path = entry.path.joined(separator: " / ")
        return entry.displayName == nil ? path : "\(entry.name) · \(path)"
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
                section(Loc.t("Schnellsuche", "Quick Search"),
                        note: Loc.t("Öffnet das Suchfenster in der Bildschirmmitte, nur wenn Live vorne ist. Hinweis: macOS nutzt ⌃Leertaste evtl. für den Sprachwechsel.",
                                    "Opens the search window in the middle of the screen, only while Live is in front. Note: macOS may use ⌃Space for switching input languages."),
                        reset: { shortcuts.quickSearch = ShortcutSettings.default.quickSearch }) {
                    row(Loc.t("Schnellsuche öffnen", "Open quick search"), combos: $shortcuts.quickSearch, maxCount: 2, requireModifier: true)
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

// MARK: - Row drop handling

enum DropSpot: Equatable { case before, after, into }

struct DropMarker: Equatable {
    let id: UUID
    let spot: DropSpot
}

@MainActor
final class DropState: ObservableObject {
    @Published var marker: DropMarker?
}

/// Upper/lower half of a plugin row = before/after it; a folder row takes drops *into* it, except its top edge.
private struct RowDropDelegate: DropDelegate {
    let row: SettingsViewRow
    let drop: DropState
    let perform: (DropSpot, [NSItemProvider]) -> Bool

    private func spot(_ info: DropInfo) -> DropSpot {
        let y = info.location.y
        if row.isFolder { return y < 10 ? .before : .into }
        return y < 21 ? .before : .after
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [entriesDragType, .text]) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let m = DropMarker(id: row.id, spot: spot(info))
        if drop.marker != m { drop.marker = m }
        return DropProposal(operation: info.hasItemsConforming(to: [entriesDragType]) ? .move : .copy)
    }

    func dropExited(info: DropInfo) {
        if drop.marker?.id == row.id { drop.marker = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let s = spot(info)
        drop.marker = nil
        return perform(s, info.itemProviders(for: [entriesDragType, .text]))
    }
}

/// What the drop delegate needs to know about a row.
struct SettingsViewRow {
    let id: UUID
    let isFolder: Bool
}

/// The entries of the drag in progress (set when it starts, consumed by the drop) — in-process and synchronous.
@MainActor
enum EntryDrag {
    static var ids: [UUID]?
}

/// Drag preview: a small yellow badge with the number of entries being dragged.
private struct DragCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(Capsule().fill(Color.accent))
    }
}
