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
    @State private var actionsOpen = Dev.env("HM_BROWSER_SELECT")?.contains("a:") == true // developer aid opens it
    @State private var renamingCategory: UUID?
    /// Grouping ~3,300 items costs ~30 ms; recompute only when items or search change, not on every redraw.
    @State private var groups: [PluginGroup] = []
    @State private var variants: [String: PluginVariantGroup] = [:]
    /// Groups without the search filter: a selected folder always adds all of its plugins.
    @State private var allGroups: [String: PluginGroup] = [:]
    /// Browser selection: "g:<group title>" for folders, "i:<uri>" for plugins.
    @State private var browserSel: Set<String> = Set((Dev.env("HM_BROWSER_SELECT") ?? "") // developer aid
        .split(separator: ",").map(String.init))
    @State private var browserAnchor: String?
    @State private var collapsed: Set<UUID> = []
    @State private var selection: Set<UUID> = []
    @State private var selectionAnchor: UUID?
    @State private var bulkIcons = false
    @State private var dropCategory: UUID?
    /// Open chain builder: nil id = new chain in the current category.
    @State private var chainEditor: ChainEditTarget?
    /// Set by "Assign Shortcut …": the Shortcuts page opens with this plugin waiting for its keys.
    @State private var shortcutRequest: PluginItem?
    /// Where a dragged category would land: in front of this category (nil id = end of the list).
    @State private var categoryMarker: CategoryMarker?
    /// Held without observing it: drag updates redraw only the rows (which observe it), not the whole window.
    @State private var dropState = DropState()

    private var categoryID: UUID { selectedCategory ?? model.config.favoritesID }
    private var category: HMLauncherCore.Category? { model.config.categories.first { $0.id == categoryID } }

    @State private var page = Int(Dev.env("HM_SETTINGS_PAGE") ?? "") ?? 0
    /// Lives here so the import preview survives switching pages.
    @StateObject private var importer = LESImportModel()

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(page: $page, model: model, pluginCount: catalog.items.count)
                .frame(width: 232)
                .hairline(.trailing)
                .id(Palette.theme) // a new theme redraws everything (colours are read while drawing)
            Group {
                switch page {
                case 0: pluginsPage
                case 2: LESImportPage(model: model, catalog: catalog, importer: importer, onDone: { page = 0 }, onBack: { page = 3 })
                case 3: VersionsPage(model: model, onOpenLESImport: { page = 2 })
                case 4: StatsPage(model: model, catalog: catalog)
                case 5: SearchTuningPage(model: model, catalog: catalog)
                case 6: BehaviorPage(model: model, server: model.streamDeck)
                default: ShortcutsPage(model: model, catalog: catalog, request: $shortcutRequest)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DS.canvas)
            .id(Palette.theme)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.canvas)
        .ignoresSafeArea()
        .themedColorScheme()
        .foregroundColor(DS.textPrimary)
        .environment(\.locale, Loc.locale) // "1,455" in English even on a German Mac
        .onReceive(model.$settingsPageRequest) { request in
            guard let request else { return }
            page = request
            DispatchQueue.main.async { model.settingsPageRequest = nil }
        }
    }

    private var pluginsPage: some View {
        libraryColumns
            .sheet(item: $chainEditor) { target in chainSheet(target) }
    }

    private func chainSheet(_ target: ChainEditTarget) -> some View {
        let existing = target.entryID.flatMap { id in category?.entries.flatMap { [$0] + ($0.children ?? []) }.first { $0.id == id } }
        return ChainBuilderSheet(items: catalog.items, name: existing?.title ?? "", steps: existing?.chain ?? [],
                                 onSave: { name, steps in
                                     if let id = target.entryID {
                                         model.config.updateChain(id, in: categoryID, name: name, steps: steps)
                                     } else {
                                         model.config.addChain(named: name, steps: steps, to: categoryID)
                                     }
                                     chainEditor = nil
                                 },
                                 onCancel: { chainEditor = nil })
    }

    private var libraryColumns: some View {
        VStack(spacing: 0) {
            // Native split view: drag the dividers to give a column more room.
            HSplitView {
                pluginBrowser.frame(minWidth: 260, idealWidth: 380, maxWidth: .infinity, maxHeight: .infinity).background(DS.surface)
                categoryList.frame(minWidth: 150, idealWidth: 190, maxWidth: 340, maxHeight: .infinity).background(DS.surface)
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
                    .font(DS.Font.body).foregroundColor(DS.textTertiary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    let fresh = newItems
                    if !fresh.isEmpty {
                        HStack(spacing: 6) {
                            SectionLabel(text: Loc.t("Neu installiert", "Newly installed"))
                            NewBadge()
                        }
                        .padding(.top, 2).padding(.bottom, DS.Space.xs).padding(.leading, DS.Space.xs)
                        ForEach(fresh, id: \.uri) { item in pluginRow(item) }
                        Spacer().frame(height: DS.Space.m)
                    }
                    SectionLabel(text: Loc.t("Live", "Live"))
                        .padding(.top, 2).padding(.bottom, DS.Space.xs).padding(.leading, DS.Space.xs)
                    LiveActionsGroup(search: search, categoryName: category?.name ?? "", open: $actionsOpen,
                                     selected: browserSel,
                                     onClick: { id in if !browserClick(id) { browserSel = [id] } },
                                     onAdd: { model.config.addAction($0, to: categoryID) },
                                     dragPayload: { browserDragPayload(for: $0) },
                                     dragCount: { dragSelection(for: $0).pluginCount },
                                     onAddSelection: { addSelection(dragSelection(for: $0), to: categoryID) })
                    .padding(.bottom, DS.Space.m)
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
                HintText(text: Loc.t("Doppelklick oder ziehen fügt hinzu · ⇧/⌘ wählt mehrere · Presets auch aus dem Finder",
                                     "Double-click or drag to add · ⇧/⌘ selects several · presets also from Finder"))
            } else {
                browserSelectionBar
            }
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.top, DS.Space.l)
        .padding(.bottom, DS.Space.l)
    }

    /// Newly installed items (best format), newest name first; filtered by the search like the groups.
    private var newItems: [PluginItem] {
        guard !model.newURIs.isEmpty else { return [] }
        return variants.values.map(\.preferred)
            .filter { model.newURIs.contains($0.uri) && (search.isEmpty || SearchMatcher.score($0.name, search) != nil) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
            .plate(lit: selected, radius: DS.Radius.s)
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
            if model.newURIs.contains(item.uri) { NewBadge() }
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
        .plate(lit: selected, radius: DS.Radius.s)
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
                    Button(Loc.t("Als \(PluginVariants.label(v)) hinzufügen", "Add as \(PluginVariants.label(v))")) { add(v, to: categoryID) }
                }
            }
            if categoryID != model.config.favoritesID {
                Button(Loc.t("Zu Favoriten hinzufügen", "Add to Favorites")) { add(item, to: model.config.favoritesID) }
            }
            Divider()
            Button(Loc.t("Stream-Deck-Link kopieren", "Copy Stream Deck Link")) { StreamDeckLink.copy(.insert(name: item.name), token: model.config.streamDeckToken) }
            Button(model.config.itemShortcut(for: item).map { Loc.t("Tastenkürzel ändern (\(KeyNames.describe($0.combo))) …", "Change Shortcut (\(KeyNames.describe($0.combo))) …") }
                   ?? Loc.t("Tastenkürzel zuweisen …", "Assign Shortcut …")) { requestShortcut(item) }
        }
        .help(item.path.joined(separator: " / "))
    }

    private func add(_ item: PluginItem, to id: UUID) { model.config.addEntry(item, to: id) }

    // MARK: Browser multi-selection (folders and plugins)

    /// Rows in the order they are drawn, for ⇧-click ranges.
    private var browserOrder: [String] {
        LiveActionsGroup.order(search: search, open: actionsOpen) + groups.flatMap { g -> [String] in
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
            } else if id.hasPrefix("a:"), let kind = LiveActionKind(rawValue: String(id.dropFirst(2))) {
                result.actions.append(LiveAction(kind: kind))
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
        let n = sel.folders.count + sel.items.count + sel.actions.count
        let label = n > 1
            ? Loc.t("\(n) ausgewählte", "\(n) selected")
            : (sel.folders.first?.title ?? sel.items.first?.name ?? sel.actions.first?.title ?? "")
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
                     sel.items.isEmpty ? nil : Loc.t("\(sel.items.count) Plugins", "\(sel.items.count) plugin\(sel.items.count == 1 ? "" : "s")"),
                     sel.actions.isEmpty ? nil : Loc.t("\(sel.actions.count) Live-Aktion\(sel.actions.count == 1 ? "" : "en")",
                                                      "\(sel.actions.count) Live action\(sel.actions.count == 1 ? "" : "s")")]
        return HStack(spacing: DS.Space.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(parts.compactMap { $0 }.joined(separator: " · ")).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                Text(Loc.t("\(sel.pluginCount) Einträge insgesamt", "\(sel.pluginCount) entries in total")).font(DS.Font.caption).foregroundColor(DS.textTertiary)
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
        .plate(lit: true, radius: DS.Radius.m)
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
            .help(Loc.t("Ziehen sortiert · Doppelklick benennt um", "Drag to reorder · double-click to rename"))
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
        .plate(lit: selected, radius: DS.Radius.s)
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
                IconButton(symbol: "link.badge.plus", help: Loc.t("Neue Kette", "New chain")) {
                    chainEditor = ChainEditTarget(entryID: nil)
                }
                IconButton(symbol: "folder.badge.plus", help: Loc.t("Neuer Ordner", "New folder")) { newFolder() }
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
                entryGrid(category)
                .onChange(of: categoryID) { _ in selection = []; selectionAnchor = nil }
                HintText(text: Loc.t("Ziehen sortiert · Rechtsklick für Icon, Name, Farbe", "Drag to reorder · right-click for icon, name, color"))
            }
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.top, DS.Space.l)
        .padding(.bottom, DS.Space.l)
    }

    // MARK: Pads (like the panel)

    @FocusState private var entriesFocused: Bool

    /// The category as the panel shows it: its pages of 3×3 pads at the panel's pad size, side by side as far as
    /// this column allows, then the contents of every open folder as its own pads below.
    private func entryGrid(_ category: HMLauncherCore.Category) -> some View {
        GeometryReader { geo in
            let size = model.config.panelSize
            let blockWidth = min(CGFloat(size.columnWidth), geo.size.width)
            let fitting = Int((geo.size.width + PanelView.blockSpacing) / (blockWidth + PanelView.blockSpacing))
            let layout = PadLayout(columns: max(1, fitting),   // each block is one page of the panel
                                   padWidth: PanelView.padWidth(columnWidth: blockWidth),
                                   padHeight: PanelView.padHeight(size))
            let rows = flatRows(category)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    padBlocks(rows.filter { $0.folderID == nil }, layout, in: category)
                    ForEach(category.entries.filter { $0.isFolder && !collapsed.contains($0.id) }) { folder in
                        openFolder(folder, rows: rows.filter { $0.folderID == folder.id }, layout, in: category)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .onDrop(of: [browserDragType, entriesDragType, .fileURL, .text], isTargeted: nil) { providers in
                // Empty area around the pads: entries move to the end, browser plugins are added.
                if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(entriesDragType.identifier) }) {
                    loadEntryIDs(p) { model.config.moveEntries($0, toFolder: nil, before: nil, in: category.id) }
                    return true
                }
                return drop(providers, into: category.id)
            }
        }
        .focusable()
        .focused($entriesFocused)
        .modifier(NoFocusRing())
        .onDeleteCommand { removeSelection() }
        .onMoveCommand { direction in moveSelectionCursor(direction, rows: flatRows(category), columns: PanelGrid.padsPerRow) }
    }

    private struct PadLayout {
        let columns: Int
        let padWidth: CGFloat
        let padHeight: CGFloat
    }

    /// Blocks of 9 side by side (up to `columns`), 3 pads per row inside a block — the panel's order.
    private func padBlocks(_ rows: [FlatRow], _ layout: PadLayout, in category: HMLauncherCore.Category) -> some View {
        // Each block of 9 is one page of the panel; a thin line runs between pages.
        VStack(alignment: .leading, spacing: PanelView.blockSpacing) {
            ForEach(Array(PanelGrid.blocks(0..<rows.count, columns: layout.columns).enumerated()), id: \.offset) { r, blockRow in
                if r > 0 { pageLine.frame(height: 1) }
                HStack(alignment: .top, spacing: PanelView.blockSpacing) {
                    ForEach(Array(blockRow.filter { !$0.isEmpty }.enumerated()), id: \.offset) { c, block in
                        if c > 0 { pageLine.frame(width: 1) }
                        VStack(alignment: .leading, spacing: PanelView.padSpacing) {
                            ForEach(Array(stride(from: 0, to: block.count, by: PanelGrid.padsPerRow)), id: \.self) { start in
                                HStack(spacing: PanelView.padSpacing) {
                                    ForEach(block[start..<min(start + PanelGrid.padsPerRow, block.count)], id: \.self) { i in
                                        padCell(rows[i], layout, in: category)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var pageLine: some View { Rectangle().fill(Palette.current.padStripe) }

    private func padCell(_ row: FlatRow, _ layout: PadLayout, in category: HMLauncherCore.Category) -> some View {
        entryRow(row, in: category, padWidth: layout.padWidth, padHeight: layout.padHeight)
            // Own drag & drop: the payload works for pads and for categories alike.
            .onDrag { dragPayload(for: row.id) } preview: {
                // Just a count next to the cursor instead of a shrunken copy of the pad.
                DragCountBadge(count: selection.contains(row.id) ? selection.count : 1)
            }
            .onDrop(of: [browserDragType, entriesDragType, .fileURL, .text], delegate: RowDropDelegate(
                row: SettingsViewRow(id: row.id, isFolder: row.entry.isFolder), drop: dropState,
                perform: { spot, providers in dropOnRow(row, spot, providers, in: category) },
                padWidth: layout.padWidth))
    }

    /// An open folder below the category's pads: its name, then its contents as pads (keys 1–9 as in the panel).
    private func openFolder(_ folder: Entry, rows: [FlatRow], _ layout: PadLayout, in category: HMLauncherCore.Category) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").foregroundColor(.accent)
                Text(folder.title).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                Text("\(rows.count)").font(DS.Font.caption.monospacedDigit()).foregroundColor(DS.textTertiary)
                Rectangle().fill(DS.hairline).frame(height: 1)
                Button { collapsed.insert(folder.id) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless).foregroundColor(.dimText)
                .help(Loc.t("Inhalt ausblenden", "Hide contents"))
            }
            if rows.isEmpty {
                Text(Loc.t("Leer – Einträge hierher ziehen", "Empty – drag entries here"))
                    .font(DS.Font.caption).foregroundColor(DS.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.m).strokeBorder(DS.hairline, style: StrokeStyle(lineWidth: 1, dash: [4])))
                    .onDrop(of: [browserDragType, entriesDragType, .fileURL, .text], isTargeted: nil) { providers in
                        dropIntoFolder(folder, providers, in: category)
                    }
            } else {
                padBlocks(rows, layout, in: category)
            }
        }
    }

    private func dropIntoFolder(_ folder: Entry, _ providers: [NSItemProvider], in category: HMLauncherCore.Category) -> Bool {
        dropOnRow(FlatRow(entry: folder, index: 0, folderID: nil), .into, providers, in: category)
    }

    /// Arrow keys move the selection: ← → by one pad, ↑ ↓ by a pad row.
    private func moveSelectionCursor(_ direction: MoveCommandDirection, rows: [FlatRow], columns: Int) {
        guard !rows.isEmpty else { return }
        let current = selectionAnchor.flatMap { id in rows.firstIndex { $0.id == id } }
        let step: Int
        switch direction {
        case .left: step = -1
        case .right: step = 1
        case .up: step = -columns
        case .down: step = columns
        @unknown default: step = 0
        }
        let next = current.map { min(max($0 + step, 0), rows.count - 1) } ?? 0
        selection = [rows[next].id]
        selectionAnchor = rows[next].id
    }

    // MARK: Folders

    private struct FlatRow: Identifiable {
        let entry: Entry
        let index: Int          // position inside its container (top level or folder)
        let folderID: UUID?     // set for plugins shown inside an expanded folder
        var id: UUID { entry.id }
    }

    /// Top-level entries first, then the contents of each open folder — the order the pads are drawn in.
    private func flatRows(_ category: HMLauncherCore.Category) -> [FlatRow] {
        let top = category.entries.enumerated().map { FlatRow(entry: $1, index: $0, folderID: nil) }
        let inside = category.entries.filter { $0.isFolder && !collapsed.contains($0.id) }.flatMap { folder in
            (folder.children ?? []).enumerated().map { FlatRow(entry: $1, index: $0, folderID: folder.id) }
        }
        return top + inside
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
                .font(DS.Font.keycap)
                .foregroundColor(DS.textSecondary)
                .fixedSize()
                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 17)
                .background(RoundedRectangle(cornerRadius: 4).fill(DS.raised))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(DS.hairline))
            Text(text).font(DS.Font.caption).foregroundColor(DS.textTertiary).fixedSize()
        }
    }

    private func activeSelectionBar(_ category: HMLauncherCore.Category) -> some View {
        let folders = category.entries.filter { $0.isFolder && !selection.contains($0.id) }
        return HStack(spacing: 10) {
            Text(Loc.t("\(selection.count) ausgewählt", "\(selection.count) selected")).font(DS.Font.secondaryStrong)
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
        .plate(lit: true, radius: DS.Radius.m)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.m).stroke(Color.brandBlue.opacity(0.5)))
    }

    private func newFolder(in categoryID: UUID? = nil) {
        let id = categoryID ?? self.categoryID
        let folder = model.config.addFolder(named: Loc.t("Neuer Ordner", "New Folder"), to: id)
        collapsed.remove(folder)
        renamingEntry = folder
    }

    @State private var renamingEntry: UUID?

    private func entryRow(_ row: FlatRow, in category: HMLauncherCore.Category, padWidth: CGFloat? = nil, padHeight: CGFloat = 66) -> some View {
        let entry = row.entry
        let folders = category.entries.filter(\.isFolder)
        let multi = selection.contains(entry.id) && selection.count > 1
        return EntryRow(
            index: row.index, entry: entry,
            isSelected: selection.contains(entry.id),
            selectionCount: multi ? selection.count : 1,
            onSelect: { select(entry.id, rows: flatRows(category)); entriesFocused = true },
            onGroup: groupSelection,
            available: entry.isFolder || entry.action != nil || catalog.items.isEmpty
                || (entry.chain.map { $0.allSatisfy { catalog.index.resolve(Entry(item: $0)) != nil } } ?? (catalog.index.resolve(entry) != nil)),
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
            onEditChain: entry.chain == nil ? nil : { chainEditor = ChainEditTarget(entryID: entry.id) },
            onUpdateAction: entry.action?.kind.takesValue == true ? { model.config.updateAction(entry.id, in: category.id, to: $0) } : nil,
            streamDeckToken: model.config.streamDeckToken,
            onShortcut: entry.isFolder || entry.chain != nil || entry.action != nil ? nil : { requestShortcut(catalog.index.resolve(entry) ?? PluginItem(uri: entry.uri, name: entry.name, source: entry.source, path: entry.path)) },
            shortcutLabel: entry.isFolder ? nil : model.config.itemShortcut(for: catalog.index.resolve(entry)
                ?? PluginItem(uri: entry.uri, name: entry.name, source: entry.source, path: entry.path)).map { KeyNames.describe($0.combo) },
            padWidth: padWidth, padHeight: padHeight)
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
            try? await catalog.refresh(rescan: true) // the list may just be older than the file
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
            // Live scans the User Library on its own (~6 s). Each check makes Live walk its browser, so check sparingly.
            for _ in 0..<6 where !copies.isEmpty {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                try? await catalog.refresh(rescan: true)
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

struct ChainEditTarget: Identifiable {
    let id = UUID()
    let entryID: UUID?
}

/// Keyboard focus on the pad area (for ⌫ and the arrow keys) without the blue ring around the whole column.
private struct NoFocusRing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) { content.focusEffectDisabled() } else { content }
    }
}
