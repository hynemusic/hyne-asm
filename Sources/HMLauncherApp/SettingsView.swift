import SwiftUI
import UniformTypeIdentifiers
import HMLauncherCore

/// Drag payload for entries dragged out of the right-hand list (onto a category). Its own type, so rows that
/// accept plugin URIs (text) from the browser don't react while entries are reordered.
let entriesDragType = UTType(exportedAs: "local.hm.launcher.entries")
let categoryDragType = UTType(exportedAs: "local.hm.launcher.category")
/// Several folders/plugins dragged out of the browser at once.
let browserDragType = UTType(exportedAs: "local.hm.launcher.browser")

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
    /// Groups without the search filter: a selected folder always adds all of its plugins.
    @State private var allGroups: [String: PluginGroup] = [:]
    /// Browser selection: "g:<group title>" for folders, "i:<uri>" for plugins.
    @State private var browserSel: Set<String> = Set((ProcessInfo.processInfo.environment["HM_BROWSER_SELECT"] ?? "") // developer aid
        .split(separator: ",").map(String.init))
    @State private var browserAnchor: String?
    @State private var collapsed: Set<UUID> = []
    @State private var selection: Set<UUID> = []
    @State private var selectionAnchor: UUID?
    @State private var bulkIcons = false
    @State private var dropCategory: UUID?
    /// Set by "Assign Shortcut …": the Shortcuts page opens with this plugin waiting for its keys.
    @State private var shortcutRequest: PluginItem?
    /// Where a dragged category would land: in front of this category (nil id = end of the list).
    @State private var categoryMarker: CategoryMarker?
    /// Held without observing it: drag updates redraw only the rows (which observe it), not the whole window.
    @State private var dropState = DropState()

    private var categoryID: UUID { selectedCategory ?? model.config.favoritesID }
    private var category: HMLauncherCore.Category? { model.config.categories.first { $0.id == categoryID } }

    @State private var page = Int(ProcessInfo.processInfo.environment["HM_SETTINGS_PAGE"] ?? "") ?? 0
    /// Lives here so the import preview survives switching pages.
    @StateObject private var importer = LESImportModel()

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(page: $page, model: model, pluginCount: catalog.items.count)
                .frame(width: 216)
                .hairline(.trailing)
            Group {
                switch page {
                case 0: pluginsPage
                case 2: LESImportPage(model: model, catalog: catalog, importer: importer, onDone: { page = 0 })
                case 3: VersionsPage(model: model)
                case 4: StatsPage(model: model, catalog: catalog)
                case 5: SearchTuningPage(model: model, catalog: catalog)
                default: ShortcutsPage(model: model, catalog: catalog, request: $shortcutRequest)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DS.canvas)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.canvas)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .foregroundColor(.white)
    }

    private var pluginsPage: some View {
        VStack(spacing: 0) {
            // Native split view: drag the dividers to give a column more room.
            HSplitView {
                pluginBrowser.frame(minWidth: 260, idealWidth: 380, maxWidth: .infinity, maxHeight: .infinity).background(DS.surface)
                categoryList.frame(minWidth: 180, idealWidth: 240, maxWidth: .infinity, maxHeight: .infinity).background(DS.surface)
                // Darkest surface: the panel preview stands out like it does over Live.
                entryList.frame(minWidth: 340, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity).background(DS.canvas)
            }
        }
    }

    // MARK: Installed plugins

    private var pluginBrowser: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            ColumnHeader(title: Loc.t("Plugins & Presets", "Plugins & Presets"), count: catalog.items.isEmpty ? nil : groups.reduce(0) { $0 + $1.items.count }) {
                IconButton(symbol: "arrow.clockwise", help: Loc.t("Liste aus Live neu laden", "Reload list from Live")) { model.refreshCatalog() }
            }
            SearchField(placeholder: Loc.t("Plugins und Presets suchen", "Search plugins and presets"), text: $search)
            if catalog.items.isEmpty {
                Text(model.isConnected ? Loc.t("Lade Plugin-Liste …", "Loading plugin list …") : Loc.t("Nicht mit Live verbunden – Live öffnen und ASMbridge als Control Surface wählen.", "Not connected to Live – open Live and choose ASMbridge as a control surface."))
                    .font(.callout).foregroundColor(.dimText)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { i, group in
                        if i == 0 || BrowserSection(group) != BrowserSection(groups[i - 1]) {
                            SectionLabel(text: BrowserSection(group).title)
                                .padding(.top, i == 0 ? 2 : DS.Space.l)
                                .padding(.bottom, DS.Space.xs)
                                .padding(.leading, DS.Space.xs)
                        }
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
            if browserSel.isEmpty {
                HintText(text: Loc.t("Doppelklick oder ziehen fügt zu „\(category?.name ?? "")“ hinzu · ⇧/⌘-Klick wählt mehrere, auch ganze Ordner · Presets auch aus dem Finder.",
                                     "Double-click or drag to add to “\(category?.name ?? "")” · ⇧/⌘-click selects several, also whole folders · presets also from Finder."))
            } else {
                browserSelectionBar
            }
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.top, DS.Space.l)
        .padding(.bottom, DS.Space.l)
    }

    /// One row per plugin (its best format); the other formats are kept for the badges and "Add as …".
    private func regroup(_ items: [PluginItem]) {
        let collapsed = PluginVariants.collapse(items)
        variants = Dictionary(collapsed.map { ($0.preferred.uri, $0) }, uniquingKeysWith: { a, _ in a })
        groups = PluginGrouping.groups(collapsed.map(\.preferred), search: search)
        if search.isEmpty || allGroups.isEmpty {
            let all = search.isEmpty ? groups : PluginGrouping.groups(collapsed.map(\.preferred), search: "")
            allGroups = Dictionary(all.map { ($0.title, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    private func folderHeader(_ group: PluginGroup) -> some View {
        let open = !search.isEmpty || expanded.contains(group.title)
        let id = "g:" + group.title
        let selected = browserSel.contains(id)
        return Button {
            if !browserClick(id) {
                if expanded.contains(group.title) { expanded.remove(group.title) } else { expanded.insert(group.title) }
            }
        } label: {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .foregroundColor(DS.textTertiary)
                    .frame(width: 10)
                Image(systemName: BrowserSection(group).symbol)
                    .font(.system(size: 12))
                    .foregroundColor(open ? .accent : DS.textSecondary)
                    .frame(width: 16)
                Text(BrowserSection.displayTitle(group))
                    .font(DS.Font.body)
                    .foregroundColor(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s)
                Text("\(group.items.count)").font(DS.Font.caption.monospacedDigit()).foregroundColor(DS.textTertiary)
            }
            .padding(.horizontal, DS.Space.s)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(selected ? DS.selection : .clear))
            .contentShape(Rectangle())
            .modifier(HoverHighlight())
        }
        .buttonStyle(.plain)
        .onDrag { browserDragPayload(for: id) } preview: { DragCountBadge(count: dragSelection(for: id).pluginCount) }
        .contextMenu {
            addMenu(for: id)
            Divider()
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
        let id = "i:" + item.uri
        let selected = browserSel.contains(id)
        return HStack(spacing: DS.Space.s) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color(label: model.config.colorID(for: item)) ?? .clear).frame(width: 3, height: 14)
            Text(item.name).font(DS.Font.body).foregroundColor(DS.textSecondary).lineLimit(1)
            Spacer(minLength: DS.Space.s)
            ForEach(variants[item.uri]?.formats ?? [PluginGrouping.formatLabel(item)], id: \.self) { format in
                let preferred = format == PluginGrouping.formatLabel(item)
                Text(format)
                    .font(DS.Font.badge)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(preferred ? DS.hover : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(DS.hairline))
                    .foregroundColor(preferred ? DS.textPrimary : DS.textTertiary)
            }
        }
        .padding(.leading, 26).padding(.trailing, DS.Space.s)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(selected ? DS.selection : .clear))
        .contentShape(Rectangle())
        .modifier(HoverHighlight())
        .onTapGesture(count: 2) { add(item, to: categoryID) }
        .simultaneousGesture(TapGesture().onEnded {
            if !browserClick(id) { browserSel = [id] } // plain click selects just this one
        })
        .onDrag {
            browserSel.contains(id) && browserSel.count > 1 ? browserDragPayload(for: id) : NSItemProvider(object: item.uri as NSString)
        } preview: { DragCountBadge(count: browserSel.contains(id) ? dragSelection(for: id).pluginCount : 1) }
        .contextMenu {
            if browserSel.contains(id) && browserSel.count > 1 {
                addMenu(for: id)
                Divider()
            }
            Button(Loc.t("Zu „\(category?.name ?? "")“ hinzufügen", "Add to “\(category?.name ?? "")”")) { add(item, to: categoryID) }
            if let others = variants[item.uri]?.variants.dropFirst(), !others.isEmpty {
                ForEach(Array(others), id: \.uri) { v in
                    Button(Loc.t("Als \(PluginGrouping.formatLabel(v)) hinzufügen", "Add as \(PluginGrouping.formatLabel(v))")) { add(v, to: categoryID) }
                }
            }
            if categoryID != model.config.favoritesID {
                Button(Loc.t("Zu Favoriten hinzufügen", "Add to Favorites")) { add(item, to: model.config.favoritesID) }
            }
            Divider()
            Button(model.config.itemShortcut(for: item).map { Loc.t("Tastenkürzel ändern (\(KeyNames.describe($0.combo))) …", "Change Shortcut (\(KeyNames.describe($0.combo))) …") }
                   ?? Loc.t("Tastenkürzel zuweisen …", "Assign Shortcut …")) { requestShortcut(item) }
        }
        .help(item.path.joined(separator: " / "))
    }

    private func add(_ item: PluginItem, to id: UUID) { model.config.addEntry(item, to: id) }

    // MARK: Browser multi-selection (folders and plugins)

    /// Rows in the order they are drawn, for ⇧-click ranges.
    private var browserOrder: [String] {
        groups.flatMap { g -> [String] in
            let open = !search.isEmpty || expanded.contains(g.title)
            return ["g:" + g.title] + (open ? g.items.map { "i:" + $0.uri } : [])
        }
    }

    /// ⇧ selects the range from the last clicked row, ⌘ toggles one. Returns false for a plain click
    /// (which only remembers the row as the start of a later range).
    private func browserClick(_ id: String) -> Bool {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor = browserAnchor, let a = browserOrder.firstIndex(of: anchor), let b = browserOrder.firstIndex(of: id) {
            browserSel.formUnion(browserOrder[min(a, b)...max(a, b)])
            return true
        }
        if flags.contains(.command) || flags.contains(.shift) {
            if browserSel.contains(id) { browserSel.remove(id) } else { browserSel.insert(id) }
            browserAnchor = id
            return true
        }
        browserAnchor = id
        browserSel = []
        return false
    }

    /// The current selection as folders + plugins (a folder always brings all of its plugins).
    private func selection(of ids: Set<String>) -> BrowserSelection {
        var result = BrowserSelection()
        let byURI = Dictionary(variants.values.map { ($0.preferred.uri, $0.preferred) }, uniquingKeysWith: { a, _ in a })
        for id in browserOrder.filter(ids.contains) + ids.filter({ !browserOrder.contains($0) }).sorted() {
            if id.hasPrefix("g:"), let g = allGroups[String(id.dropFirst(2))] {
                result.folders.append(.init(title: BrowserSection.displayTitle(g), items: g.items))
            } else if id.hasPrefix("i:"), let item = byURI[String(id.dropFirst(2))] {
                result.items.append(item)
            }
        }
        return result
    }

    /// Dragging a selected row carries the whole selection; an unselected folder carries just itself.
    private func dragSelection(for id: String) -> BrowserSelection {
        selection(of: browserSel.contains(id) ? browserSel : [id])
    }

    private func browserDragPayload(for id: String) -> NSItemProvider {
        BrowserDrag.selection = dragSelection(for: id)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: browserDragType.identifier, visibility: .ownProcess) { done in
            done(Data("selection".utf8), nil)
            return nil
        }
        return provider
    }

    private func addSelection(_ sel: BrowserSelection, to target: UUID, folder: UUID? = nil, asFolders: Bool = true) {
        model.config.add(sel, to: target, folder: folder, asFolders: asFolders)
        selectedCategory = target
        browserSel = []
    }

    /// "Add to …" menu for a row: the selection if the row is part of it, else the row alone.
    @ViewBuilder
    private func addMenu(for id: String) -> some View {
        let sel = dragSelection(for: id)
        let label = sel.folders.count + sel.items.count > 1
            ? Loc.t("\(sel.folders.count + sel.items.count) ausgewählte", "\(sel.folders.count + sel.items.count) selected")
            : (sel.folders.first?.title ?? sel.items.first?.name ?? "")
        Button(Loc.t("„\(label)“ zu „\(category?.name ?? "")“ hinzufügen", "Add “\(label)” to “\(category?.name ?? "")”")) { addSelection(sel, to: categoryID) }
        Menu(Loc.t("Zu Kategorie hinzufügen", "Add to Category")) {
            ForEach(model.config.categories) { c in Button(c.name) { addSelection(sel, to: c.id) } }
        }
        if !sel.folders.isEmpty {
            Button(Loc.t("Ohne Ordner hinzufügen (einzeln)", "Add Without Folders (loose)")) { addSelection(sel, to: categoryID, asFolders: false) }
        }
    }

    private var browserSelectionBar: some View {
        let sel = selection(of: browserSel)
        let parts = [sel.folders.isEmpty ? nil : Loc.t("\(sel.folders.count) Ordner", "\(sel.folders.count) folder\(sel.folders.count == 1 ? "" : "s")"),
                     sel.items.isEmpty ? nil : Loc.t("\(sel.items.count) Plugins", "\(sel.items.count) plugin\(sel.items.count == 1 ? "" : "s")")]
        return HStack(spacing: DS.Space.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(parts.compactMap { $0 }.joined(separator: " · ")).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                Text(Loc.t("\(sel.pluginCount) Einträge insgesamt", "\(sel.pluginCount) entries in total")).font(.system(size: 10.5)).foregroundColor(DS.textTertiary)
            }
            Spacer(minLength: DS.Space.s)
            Button(Loc.t("Zu „\(category?.name ?? "")“", "Add to “\(category?.name ?? "")”")) { addSelection(sel, to: categoryID) }
                .buttonStyle(.borderedProminent).tint(.brandBlue).controlSize(.small)
            Menu {
                ForEach(model.config.categories.filter { $0.id != categoryID }) { c in
                    Button(Loc.t("Zu „\(c.name)“", "To “\(c.name)”")) { addSelection(sel, to: c.id) }
                }
                if !sel.folders.isEmpty {
                    Divider()
                    Button(Loc.t("Zu „\(category?.name ?? "")“ ohne Ordner", "To “\(category?.name ?? "")” without folders")) { addSelection(sel, to: categoryID, asFolders: false) }
                }
                Divider()
                Button(Loc.t("Auswahl aufheben", "Deselect")) { browserSel = [] }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, DS.Space.m)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: DS.Radius.m).fill(DS.selection))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.m).stroke(Color.brandBlue.opacity(0.5)))
    }

    // MARK: Categories

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            ColumnHeader(title: Loc.t("Kategorien", "Categories"), count: model.config.categories.count) {
                IconButton(symbol: "plus", help: Loc.t("Neue Kategorie", "New category")) {
                    let id = model.config.addCategory(named: Loc.t("Neue Kategorie", "New Category"))
                    selectedCategory = id
                    startRenaming(id)
                }
            }
            HintText(text: Loc.t("Ziehen sortiert · Doppelklick benennt um", "Drag to reorder · double-click to rename"), icon: nil)
            List {
                ForEach(model.config.categories) { c in
                    categoryRow(c)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.top, DS.Space.l)
        .padding(.bottom, DS.Space.l)
    }

    @ViewBuilder
    private func categoryRow(_ c: HMLauncherCore.Category) -> some View {
        let selected = c.id == categoryID
        HStack(spacing: DS.Space.s) {
            Image(systemName: c.isFavorites ? "star.fill" : "folder")
                .font(.system(size: 12))
                .foregroundColor(c.isFavorites || selected ? .accent : DS.textTertiary).frame(width: 16)
            if renamingCategory == c.id {
                InlineNameField(initial: c.name,
                                onCommit: { model.config.renameCategory(c.id, to: $0); renamingCategory = nil },
                                onCancel: { renamingCategory = nil })
            } else {
                Text(c.name).font(selected ? DS.Font.bodyStrong : DS.Font.body)
                    .foregroundColor(selected ? DS.textPrimary : DS.textSecondary).lineLimit(1)
            }
            Spacer()
            Text("\(c.entries.count)").font(DS.Font.caption.monospacedDigit()).foregroundColor(DS.textTertiary)
        }
        .padding(.horizontal, DS.Space.s)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(selected ? DS.selection : .clear))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if !c.isFavorites { startRenaming(c.id) } }
        .simultaneousGesture(TapGesture().onEnded { selectedCategory = c.id })
        .overlay { if dropCategory == c.id && c.id != categoryID { RoundedRectangle(cornerRadius: 4).stroke(Color.accent, lineWidth: 2) } }
        .overlay(alignment: categoryMarker?.after == true ? .bottom : .top) {
            if categoryMarker?.id == c.id { Rectangle().fill(Color.accent).frame(height: 3).offset(y: categoryMarker?.after == true ? 3 : -3) }
        }
        .modifier(CategoryDragSource(enabled: !c.isFavorites, id: c.id, name: c.name))
        .onDrop(of: [categoryDragType, browserDragType, entriesDragType, .fileURL, .text], delegate: CategoryDropDelegate(
            category: c.id, isFavorites: c.isFavorites,
            marker: $categoryMarker, entryTarget: $dropCategory,
            moveCategory: { moveDraggedCategory(before: $0) },
            dropEntries: { dropOnCategory($0, c.id) },
            nextCategory: categoryAfter(c.id)))
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

    private func categoryAfter(_ id: UUID) -> UUID? {
        let cats = model.config.categories
        guard let i = cats.firstIndex(where: { $0.id == id }), i + 1 < cats.count else { return nil }
        return cats[i + 1].id
    }

    /// Moves the category being dragged in front of `anchor` (nil = to the end).
    private func moveDraggedCategory(before anchor: UUID?) {
        guard let id = CategoryDrag.id else { return }
        CategoryDrag.id = nil
        model.config.moveCategory(id, before: anchor)
    }

    private func requestShortcut(_ item: PluginItem) {
        shortcutRequest = item
        page = 1
    }

    private func startRenaming(_ id: UUID) {
        renamingCategory = id
    }

    // MARK: Entries (looks like the panel)

    private var entryList: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            ColumnHeader(title: category?.name ?? "", count: category?.entries.count) {
                Label(Loc.t("Panel-Vorschau", "Panel preview"), systemImage: "eye")
                    .font(DS.Font.caption).foregroundColor(DS.textTertiary)
                    .help(Loc.t("So erscheint die Kategorie im Panel in Live", "This is how the category looks in the panel in Live"))
                IconButton(symbol: "folder.badge.plus", help: Loc.t("Neuen Ordner in dieser Kategorie anlegen", "Create a new folder in this category")) { newFolder() }
            }
            if let category {
                if category.entries.isEmpty {
                    VStack(spacing: DS.Space.s) {
                        Image(systemName: "tray").font(.system(size: 26)).foregroundColor(DS.textTertiary)
                        Text(Loc.t("Noch leer", "Empty")).font(DS.Font.bodyStrong).foregroundColor(DS.textSecondary)
                        Text(Loc.t("Plugins links doppelklicken oder hierher ziehen.", "Double-click plugins on the left or drag them here."))
                            .font(DS.Font.caption).foregroundColor(DS.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
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
                            .onDrop(of: [browserDragType, entriesDragType, .fileURL, .text], delegate: RowDropDelegate(
                                row: SettingsViewRow(id: row.id, isFolder: row.entry.isFolder), drop: dropState,
                                perform: { spot, providers in dropOnRow(row, spot, providers, in: category) }))
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 2, leading: row.folderID == nil ? 0 : 28, bottom: 2, trailing: 0))
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onDrop(of: [browserDragType, entriesDragType, .fileURL, .text], isTargeted: nil) { providers in
                    // Empty area below the rows: entries move to the end, browser plugins are added.
                    if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(entriesDragType.identifier) }) {
                        loadEntryIDs(p) { model.config.moveEntries($0, toFolder: nil, before: nil, in: category.id) }
                        return true
                    }
                    return drop(providers, into: category.id)
                }
                .onDeleteCommand { removeSelection() }
                .onChange(of: categoryID) { _ in selection = []; selectionAnchor = nil }
                HintText(text: Loc.t("Ziehen sortiert, auch in und aus Ordnern · Rechtsklick für Icon, Name und Farbe",
                                     "Drag to reorder, also in and out of folders · right-click for icon, name and color"))
            }
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.top, DS.Space.l)
        .padding(.bottom, DS.Space.l)
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
        if takeBrowserDrop(providers, into: category.id, folder: spot == .into ? row.entry.id : row.folderID) { return true }
        if importFiles(providers, into: category.id, folder: folder) { return true }
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
            HStack(spacing: DS.Space.l) {
                keyHint("⇧", Loc.t("Bereich", "range"))
                keyHint("⌘", Loc.t("einzeln", "single"))
                keyHint("⌘G", Loc.t("gruppieren", "group"))
                keyHint("⌫", Loc.t("entfernen", "remove"))
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .leading)
            .padding(.horizontal, DS.Space.s)
        } else {
            activeSelectionBar(category)
        }
    }

    /// "⌘G group" — a key cap and what it does.
    private func keyHint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 17)
                .background(RoundedRectangle(cornerRadius: 4).fill(DS.raised))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(DS.hairline))
            Text(text).font(DS.Font.caption).foregroundColor(DS.textTertiary)
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
        .foregroundColor(DS.textPrimary)
        .padding(.horizontal, DS.Space.m)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: DS.Radius.m).fill(DS.selection))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.m).stroke(Color.brandBlue.opacity(0.5)))
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
            drop: dropState,
            onShortcut: entry.isFolder ? nil : { requestShortcut(catalog.index.resolve(entry) ?? PluginItem(uri: entry.uri, name: entry.name, source: entry.source, path: entry.path)) },
            shortcutLabel: entry.isFolder ? nil : model.config.itemShortcut(for: catalog.index.resolve(entry)
                ?? PluginItem(uri: entry.uri, name: entry.name, source: entry.source, path: entry.path)).map { KeyNames.describe($0.combo) })
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.system(size: 15, weight: .semibold))
    }

    // MARK: Presets from Finder

    /// Handles a drop of files from Finder. Returns false when the drop holds no files (then it's a plugin URI).
    private func importFiles(_ providers: [NSItemProvider], into categoryID: UUID, folder: UUID?) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for p in files {
            group.enter()
            _ = p.loadObject(ofClass: NSURL.self) { obj, _ in
                if let url = obj as? URL { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { importPresets(urls, into: categoryID, folder: folder) }
        return true
    }

    /// Presets Live already lists are added right away. Others are copied into the User Library (after asking),
    /// then added as soon as Live has picked them up.
    private func importPresets(_ urls: [URL], into categoryID: UUID, folder: UUID?) {
        let presets = urls.filter(PresetFormat.isPresetFile)
        if presets.isEmpty {
            alert(Loc.t("Keine Presets", "No presets"),
                  Loc.t("Ziehen kannst du .adg, .adv, .vstpreset, .aupreset, .fxp, .fxb und .amxd.",
                        "You can drag in .adg, .adv, .vstpreset, .aupreset, .fxp, .fxb and .amxd files."))
            return
        }
        Task { @MainActor in
            var missing = addMatches(presets, into: categoryID, folder: folder)
            if missing.isEmpty { return }
            try? await catalog.refresh() // the list may just be older than the file
            missing = addMatches(missing, into: categoryID, folder: folder)
            if missing.isEmpty { return }

            let library = PresetImport.userLibraryURL
            let names = missing.map(\.lastPathComponent).joined(separator: "\n")
            guard confirm(Loc.t("In die User Library kopieren?", "Copy into the User Library?"),
                          Loc.t("Live kennt diese Presets noch nicht:\n\(names)\n\nHYNE ASM kopiert sie nach „User Library/Presets/HYNE ASM“, damit Live sie laden kann. Die Originale bleiben, wo sie sind.",
                                "Live doesn't know these presets yet:\n\(names)\n\nHYNE ASM copies them to “User Library/Presets/HYNE ASM” so Live can load them. The originals stay where they are."),
                          ok: Loc.t("Kopieren", "Copy")) else { return }
            var copies: [URL] = []
            for file in missing {
                let target = PresetImport.isInside(file, library) ? file : PresetImport.copyDestination(for: file)
                if target != file {
                    do {
                        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try FileManager.default.copyItem(at: file, to: target)
                    } catch {
                        alert(Loc.t("Kopieren fehlgeschlagen", "Copy failed"), "\(file.lastPathComponent): \(error.localizedDescription)")
                        continue
                    }
                }
                copies.append(target)
            }
            // Live scans the User Library on its own; give it a few seconds.
            for _ in 0..<12 where !copies.isEmpty {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                try? await catalog.refresh()
                copies = addMatches(copies, into: categoryID, folder: folder)
            }
            if !copies.isEmpty {
                alert(Loc.t("Noch nicht in Live", "Not in Live yet"),
                      Loc.t("Live hat \(copies.map(\.lastPathComponent).joined(separator: ", ")) noch nicht eingelesen. Die Datei liegt in „User Library/Presets/HYNE ASM“ – lade die Liste gleich mit ↻ neu und füg sie dann hinzu.",
                            "Live hasn't picked up \(copies.map(\.lastPathComponent).joined(separator: ", ")) yet. The file is in “User Library/Presets/HYNE ASM” – reload the list with ↻ in a moment and add it then."))
            }
        }
    }

    /// Adds every file Live lists and returns the ones it doesn't (yet).
    private func addMatches(_ files: [URL], into categoryID: UUID, folder: UUID?) -> [URL] {
        files.filter { file in
            guard let item = PresetImport.match(file, in: catalog.items) else { return true }
            model.config.addEntry(item, to: categoryID, folder: folder)
            return false
        }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    private func confirm(_ title: String, _ text: String, ok: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: ok)
        a.addButton(withTitle: Loc.t("Abbrechen", "Cancel"))
        return a.runModal() == .alertFirstButtonReturn
    }

    /// A browser selection (several folders/plugins) dropped onto the list, a row or a category.
    private func takeBrowserDrop(_ providers: [NSItemProvider], into categoryID: UUID, folder: UUID?) -> Bool {
        guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier(browserDragType.identifier) }),
              let sel = BrowserDrag.selection else { return false }
        BrowserDrag.selection = nil
        addSelection(sel, to: categoryID, folder: folder)
        return true
    }

    private func drop(_ providers: [NSItemProvider], into categoryID: UUID) -> Bool {
        if takeBrowserDrop(providers, into: categoryID, folder: nil) { return true }
        if importFiles(providers, into: categoryID, folder: nil) { return true }
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
    /// "Shortcut …": opens the Shortcuts page with this plugin ready to record.
    var onShortcut: (() -> Void)? = nil
    var shortcutLabel: String? = nil
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
            if let onShortcut {
                Button(shortcutLabel.map { Loc.t("Tastenkürzel ändern (\($0)) …", "Change Shortcut (\($0)) …") } ?? Loc.t("Tastenkürzel zuweisen …", "Assign Shortcut …"), action: onShortcut)
            }
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
                        Text(Loc.t("Auch belegt", "Also used")).font(.system(size: 10.5)).foregroundColor(DS.warning)
                        ConflictBadge(title: Loc.t("\(combo.map(KeyNames.describe) ?? "") ist auch belegt", "\(combo.map(KeyNames.describe) ?? "") is also used"),
                                      lines: owner.components(separatedBy: " · "))
                    }
                } else if pending {
                    Text(Loc.t("Klick auf + und drück die Tasten", "Click + and press the keys")).font(.system(size: 10.5)).foregroundColor(.accent)
                } else if resolved == nil, !catalog.items.isEmpty {
                    Text(Loc.t("Nicht mehr in Live gefunden", "No longer found in Live")).font(.system(size: 10.5)).foregroundColor(DS.warning)
                } else {
                    Text(UsageKind(item.source).title).font(.system(size: 10.5)).foregroundColor(DS.textTertiary)
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
                Label { Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(DS.textPrimary) }
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

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [browserDragType, entriesDragType, .fileURL, .text]) }

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
        return perform(s, info.itemProviders(for: [browserDragType, entriesDragType, .fileURL, .text]))
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

/// The browser selection being dragged (set when the drag starts, taken by the drop).
@MainActor
enum BrowserDrag {
    static var selection: BrowserSelection?
}

/// The category being dragged (set when the drag starts) — in-process and synchronous like `EntryDrag`.
@MainActor
enum CategoryDrag {
    static var id: UUID?
}

struct CategoryMarker: Equatable {
    let id: UUID
    let after: Bool
}

/// Lets every category except Favorites be dragged by its row.
private struct CategoryDragSource: ViewModifier {
    let enabled: Bool
    let id: UUID
    let name: String

    func body(content: Content) -> some View {
        if enabled {
            content.onDrag {
                CategoryDrag.id = id
                EntryDrag.ids = nil
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: categoryDragType.identifier, visibility: .ownProcess) { done in
                    done(Data(id.uuidString.utf8), nil)
                    return nil
                }
                return provider
            } preview: {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accent))
            }
        } else {
            content
        }
    }
}

/// A category row takes two kinds of drops: another category (reorder: upper half = before, lower half = after)
/// and plugins/entries (they move into this category).
private struct CategoryDropDelegate: DropDelegate {
    let category: UUID
    let isFavorites: Bool
    @Binding var marker: CategoryMarker?
    @Binding var entryTarget: UUID?
    let moveCategory: (UUID?) -> Void
    let dropEntries: ([NSItemProvider]) -> Bool

    private func isCategoryDrag(_ info: DropInfo) -> Bool { info.hasItemsConforming(to: [categoryDragType]) }

    /// Favorites is always first, so a category dropped on it lands right after it.
    private func after(_ info: DropInfo) -> Bool { isFavorites || info.location.y >= 15 }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [categoryDragType, browserDragType, entriesDragType, .fileURL, .text]) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isCategoryDrag(info) {
            let m = CategoryMarker(id: category, after: after(info))
            if marker != m { marker = m }
            if entryTarget != nil { entryTarget = nil }
            return DropProposal(operation: .move)
        }
        if entryTarget != category { entryTarget = category }
        return DropProposal(operation: info.hasItemsConforming(to: [entriesDragType]) ? .move : .copy)
    }

    func dropExited(info: DropInfo) {
        if marker?.id == category { marker = nil }
        if entryTarget == category { entryTarget = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        marker = nil
        entryTarget = nil
        if isCategoryDrag(info) {
            moveCategory(after(info) ? nextCategory : category)
            return true
        }
        return dropEntries(info.itemProviders(for: [browserDragType, entriesDragType, .fileURL, .text]))
    }

    /// Filled in by the list: the category below this one (nil = this is the last one).
    var nextCategory: UUID?
}

/// Which part of the settings browser a group belongs to; the browser draws a label where the part changes.
private enum BrowserSection: Equatable {
    case presets, live, vendors

    init(_ group: PluginGroup) {
        if group.title.hasPrefix(PresetFormat.groupPrefix) { self = .presets }
        else if group.title.hasPrefix("Live · ") { self = .live }
        else { self = .vendors }
    }

    var title: String {
        switch self {
        case .presets: return Loc.t("Eigene Presets", "Your Presets")
        case .live: return Loc.t("Live-Devices", "Live Devices")
        case .vendors: return Loc.t("Plugins nach Hersteller", "Plugins by Manufacturer")
        }
    }

    var symbol: String {
        switch self {
        case .presets: return "doc.on.doc"
        case .live: return "square.stack.3d.up"
        case .vendors: return "folder"
        }
    }

    /// The group title without the section prefix the label already says.
    static func displayTitle(_ group: PluginGroup) -> String {
        for prefix in [PresetFormat.groupPrefix, "Live · "] where group.title.hasPrefix(prefix) {
            return String(group.title.dropFirst(prefix.count))
        }
        return group.title
    }
}
