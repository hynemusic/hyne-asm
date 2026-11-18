import AppKit
import SwiftUI
import UniformTypeIdentifiers
import HMLauncherCore

// MARK: - LES import

@MainActor
final class LESImportModel: ObservableObject {
    @Published var text = ""
    @Published var draft = ImportDraft()
    @Published var selected: UUID?
    @Published var message: String?

    func build(items: [PluginItem]) {
        draft = ImportDraft.make(text: text, items: items)
        selected = draft.categories.first?.id
        message = nil
    }
}

struct LESImportPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var catalog: PluginCatalog
    @ObservedObject var importer: LESImportModel
    let onDone: () -> Void
    @State private var renaming: UUID?
    @State private var confirmReplace = false

    private var category: ImportCategory? {
        importer.draft.categories.first { $0.id == importer.selected } ?? importer.draft.categories.first
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: Loc.t("LES-Import", "LES Import"),
                       subtitle: Loc.t("Übernimm dein Menü aus Live Enhancement Suite. Du siehst vorher genau, was zugeordnet wird.",
                                       "Bring over your menu from Live Enhancement Suite. You see exactly what gets matched before anything changes."))
                .padding(.horizontal, DS.Space.xxl)
                .padding(.top, 40)
                .padding(.bottom, DS.Space.l)
                .hairline(.bottom)
            HStack(spacing: 0) {
                source.frame(width: 340).background(DS.surface).hairline(.trailing)
                if importer.draft.categories.isEmpty { emptyPreview } else { preview }
            }
        }
        .background(DS.canvas)
    }

    // MARK: Source text

    private var source: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            ColumnHeader(title: "menuconfig.ini") { EmptyView() }
            Text(Loc.t("Füge deine LES-Menükonfiguration ein oder lade sie direkt aus LES.",
                       "Paste your LES menu configuration or load it straight from LES."))
                .font(DS.Font.caption).foregroundColor(DS.textTertiary)
            HStack {
                if FileManager.default.fileExists(atPath: LESMenuParser.defaultURL.path) {
                    Button(Loc.t("Von LES laden", "Load from LES")) { load(LESMenuParser.defaultURL) }
                }
                Button(Loc.t("Datei öffnen …", "Open File …")) { openFile() }
            }
            TextEditor(text: $importer.text)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(DS.Space.xs)
                .background(RoundedRectangle(cornerRadius: DS.Radius.m).fill(DS.raised))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.m).stroke(DS.hairline))
            Button {
                importer.build(items: catalog.items)
            } label: {
                Label(Loc.t("Vorschau erstellen", "Build Preview"), systemImage: "wand.and.stars").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandBlue)
            .disabled(importer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || catalog.items.isEmpty)
            if catalog.items.isEmpty {
                Text(Loc.t("Erst mit Live verbinden – die Plugin-Liste wird zum Zuordnen gebraucht.",
                           "Connect to Live first – the plugin list is needed for matching."))
                    .font(DS.Font.caption).foregroundColor(DS.warning)
            }
        }
        .padding(DS.Space.l)
    }

    private func load(_ url: URL) {
        // LES may have written the file in Latin-1; UTF-8 first, then that.
        if let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) {
            importer.text = text
            importer.build(items: catalog.items)
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ini") ?? .plainText, .plainText]
        panel.directoryURL = LESMenuParser.defaultURL.deletingLastPathComponent()
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    // MARK: Preview

    private var emptyPreview: some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 30)).foregroundColor(DS.textTertiary)
            Text(Loc.t("Noch keine Vorschau", "No preview yet")).font(DS.Font.bodyStrong).foregroundColor(DS.textSecondary)
            Text(Loc.t("Hier erscheint dein LES-Menü so, wie es im Panel aussehen wird.",
                       "Your LES menu will appear here the way it will look in the panel."))
                .font(DS.Font.caption).foregroundColor(DS.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.canvas)
    }

    private var preview: some View {
        VStack(spacing: 0) {
            summary.padding(12)
            Divider()
            HStack(spacing: 0) {
                categoryColumn.frame(width: 220).background(DS.surface).hairline(.trailing)
                rowColumn.background(DS.canvas)
            }
            Divider()
            pushBar.padding(12)
        }
    }

    private var summary: some View {
        let c = importer.draft.counts
        return HStack(spacing: 16) {
            Text(Loc.t("Vorschau", "Preview")).font(DS.Font.sectionTitle)
            Label("\(c.found) " + Loc.t("gefunden", "found"), systemImage: "checkmark.circle.fill").foregroundColor(.green)
            Label("\(c.uncertain) " + Loc.t("unsicher", "uncertain"), systemImage: "exclamationmark.triangle.fill").foregroundColor(.yellow)
            Label("\(c.notFound) " + Loc.t("nicht gefunden", "not found"), systemImage: "xmark.circle.fill").foregroundColor(.red)
            Spacer()
        }
        .font(.system(size: 12))
    }

    /// Top-level categories, each followed by the folders that will be created inside it.
    private var orderedCategories: [ImportCategory] {
        let all = importer.draft.categories
        let ids = Set(all.map(\.id))
        let tops = all.filter { $0.parentID.map { !ids.contains($0) } ?? true }
        return tops.flatMap { top in [top] + all.filter { $0.parentID == top.id } }
    }

    private var categoryColumn: some View {
        List {
            ForEach(orderedCategories) { c in
                categoryRow(c)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 2, leading: c.parentID == nil ? 6 : 26, bottom: 2, trailing: 6))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func categoryRow(_ c: ImportCategory) -> some View {
        let selected = c.id == category?.id
        let missing = c.rows.filter { $0.match.status == .notFound }.count
        let isFolder = c.parentID != nil
        return HStack(spacing: 8) {
            Image(systemName: isFolder ? "folder.fill" : "square.stack").foregroundColor(isFolder ? .accent : .dimText)
            if renaming == c.id {
                InlineNameField(initial: c.name,
                                onCommit: { importer.draft.renameCategory(c.id, to: $0); renaming = nil },
                                onCancel: { renaming = nil })
            } else {
                Text(c.name).font(selected ? DS.Font.columnTitle : DS.Font.body).lineLimit(1)
            }
            Spacer()
            if missing > 0 { Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.red) }
            Text("\(c.rows.count)").font(DS.Font.caption).foregroundColor(.dimText)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(selected ? Color.rowHighlight : Color.clear)
        .overlay(alignment: .leading) { if selected { Rectangle().fill(Color.accent).frame(width: 3) } }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { renaming = c.id }
        .simultaneousGesture(TapGesture().onEnded { importer.selected = c.id })
        .contextMenu {
            Button(Loc.t("Umbenennen", "Rename")) { renaming = c.id }
            if isFolder {
                Button(Loc.t("Als eigene Kategorie", "Make Own Category")) { importer.draft.setParent(c.id, to: nil) }
            } else if !importer.draft.categories.contains(where: { $0.parentID == c.id }) {
                Menu(Loc.t("Als Ordner in", "Make Folder In")) {
                    ForEach(importer.draft.categories.filter { $0.parentID == nil && $0.id != c.id }) { target in
                        Button(target.name) { importer.draft.setParent(c.id, to: target.id) }
                    }
                }
            }
            Menu(Loc.t("Zusammenführen mit", "Merge into")) {
                ForEach(importer.draft.categories.filter { $0.id != c.id }) { target in
                    Button(target.name) {
                        importer.draft.mergeCategory(c.id, into: target.id)
                        importer.selected = target.id
                    }
                }
            }
            Divider()
            Button(Loc.t("Kategorie entfernen", "Remove Category"), role: .destructive) {
                importer.draft.removeCategory(c.id)
                if importer.selected == c.id { importer.selected = importer.draft.categories.first?.id }
            }
        }
    }

    private var rowColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let category {
                HStack {
                    if let parent = importer.draft.categories.first(where: { $0.id == category.parentID }) {
                        Text(parent.name + " /").font(DS.Font.sectionTitle).fontWeight(.regular).foregroundColor(.dimText)
                        Image(systemName: "folder.fill").foregroundColor(.accent)
                    }
                    Text(category.name).font(DS.Font.sectionTitle)
                    Spacer()
                    Text(Loc.t("So erscheint es im Panel", "This is how it looks in the panel")).font(DS.Font.caption).foregroundColor(.dimText)
                }
                List {
                    ForEach(Array(category.rows.enumerated()), id: \.element.id) { index, row in
                        ImportRowView(index: index, row: row, catalog: catalog,
                                      onPick: { importer.draft.setMatch($0, for: row.id, in: category.id) },
                                      onRemove: { importer.draft.removeRow(row.id, from: category.id) })
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    }
                    .onMove { from, to in
                        guard let f = from.first else { return }
                        importer.draft.moveRow(in: category.id, from: f, to: to > f ? to - 1 : to)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                Text(Loc.t("Ziehen sortiert · Klick auf ⚠️/❌ wählt das richtige Plugin · Rechtsklick links: umbenennen, Ordner ↔ Kategorie, zusammenführen",
                           "Drag to reorder · click ⚠️/❌ to pick the right plugin · right-click on the left: rename, folder ↔ category, merge"))
                    .font(DS.Font.caption).foregroundColor(DS.textTertiary)
            }
        }
        .padding(12)
    }

    private var pushBar: some View {
        let skipped = importer.draft.counts.notFound
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let message = importer.message {
                    Label(message, systemImage: "checkmark.circle.fill").foregroundColor(DS.success).font(DS.Font.secondary)
                }
                Text((skipped > 0 ? Loc.t("\(skipped) nicht gefundene werden übersprungen. ", "\(skipped) not found will be skipped. ") : "")
                     + Loc.t("Vorher wird automatisch eine Version gesichert.", "The current menu is saved as a version first."))
                    .font(DS.Font.caption).foregroundColor(DS.textTertiary)
            }
            Spacer()
            Button(Loc.t("Hinzufügen", "Add")) { push(.add) }
                .help(Loc.t("Zu deinen bestehenden Kategorien hinzufügen (gleichnamige werden zusammengeführt)",
                            "Add to your existing categories (same names are merged)"))
            Button(Loc.t("Ersetzen …", "Replace …")) { confirmReplace = true }
                .buttonStyle(.borderedProminent).tint(.brandBlue)
                .help(Loc.t("Alle Kategorien außer Favorites durch die Vorschau ersetzen",
                            "Replace all categories except Favorites with the preview"))
        }
        .confirmationDialog(Loc.t("Menü ersetzen?", "Replace menu?"), isPresented: $confirmReplace) {
            Button(Loc.t("Ersetzen", "Replace"), role: .destructive) { push(.replace) }
        } message: {
            Text(Loc.t("Alle Kategorien außer Favorites werden durch die Vorschau ersetzt. Der jetzige Stand wird vorher als Version gesichert.",
                       "All categories except Favorites are replaced by the preview. The current state is saved as a version first."))
        }
    }

    private func push(_ mode: ImportMode) {
        do {
            try model.push(importer.draft, mode: mode)
            importer.message = Loc.t("Ins Menü übernommen.", "Pushed to the menu.")
        } catch {
            importer.message = nil
            showError(error)
        }
    }
}

private struct ImportRowView: View {
    let index: Int
    let row: ImportRow
    @ObservedObject var catalog: PluginCatalog
    let onPick: (PluginItem) -> Void
    let onRemove: () -> Void
    @State private var picking = false
    @State private var hovered = false

    var body: some View {
        let item = row.match.item
        LauncherRow(number: index,
                    symbol: IconCatalog.symbolName(for: item.map(IconGuesser.guess) ?? IconCatalog.defaultID),
                    title: row.display,
                    subtitle: subtitle,
                    active: hovered,
                    available: row.match.status != .notFound) {
            if hovered {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundColor(.dimText)
            }
            Button { picking = true } label: { statusIcon }
                .buttonStyle(.borderless)
                .help(Loc.t("Plugin wählen", "Choose plugin"))
                .popover(isPresented: $picking, arrowEdge: .trailing) {
                    PluginPicker(items: catalog.items, initialSearch: row.match.item?.name ?? row.display,
                                 suggestions: row.match.alternatives) { onPick($0); picking = false }
                }
        }
        .onHover { hovered = $0 }
        .contextMenu {
            Button(Loc.t("Plugin wählen …", "Choose Plugin …")) { picking = true }
            Button(Loc.t("Entfernen", "Remove"), role: .destructive, action: onRemove)
        }
    }

    private var subtitle: String {
        let target = row.match.item.map { "→ \($0.name) · \(PluginGrouping.formatLabel($0))" } ?? Loc.t("→ nicht gefunden", "→ not found")
        let preset = row.match.isPreset ? Loc.t(" · LES-Preset, nur Plugin übernehmbar", " · LES preset, only the plugin can be imported") : ""
        return "LES: \(row.query)  \(target)\(preset)"
    }

    @ViewBuilder private var statusIcon: some View {
        switch row.match.status {
        case .found: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .uncertain: Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
        case .notFound: Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        }
    }
}

/// Search the installed plugins and pick one.
private struct PluginPicker: View {
    let items: [PluginItem]
    let suggestions: [PluginItem]
    let onPick: (PluginItem) -> Void
    @State private var search: String

    init(items: [PluginItem], initialSearch: String, suggestions: [PluginItem], onPick: @escaping (PluginItem) -> Void) {
        self.items = items
        self.suggestions = suggestions
        self.onPick = onPick
        _search = State(initialValue: initialSearch)
    }

    private var results: [PluginItem] {
        let words = search.lowercased().split(separator: " ")
        let hits = words.isEmpty ? items : items.filter { item in
            let name = item.name.lowercased()
            return words.allSatisfy { name.contains($0) }
        }
        return Array(hits.sorted { $0.name.count < $1.name.count }.prefix(60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(Loc.t("Plugin suchen", "Search plugin"), text: $search).textFieldStyle(.roundedBorder)
            List {
                if !suggestions.isEmpty {
                    Section(Loc.t("Vorschläge", "Suggestions")) { ForEach(suggestions, id: \.uri, content: row) }
                }
                Section(Loc.t("Suche", "Search")) { ForEach(results, id: \.uri, content: row) }
            }
            .listStyle(.plain)
        }
        .padding(10)
        .frame(width: 380, height: 420)
        .themedColorScheme()
    }

    private func row(_ item: PluginItem) -> some View {
        Button { onPick(item) } label: {
            HStack {
                Text(item.name)
                Spacer()
                Text(PluginGrouping.formatLabel(item)).font(DS.Font.caption).foregroundColor(.dimText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Versions

struct VersionsPage: View {
    @ObservedObject var model: AppModel
    @State private var name = ""
    @State private var restoring: MenuVersion?
    @State private var info: String?

    var body: some View {
        PageContainer(title: Loc.t("Profile", "Profiles"),
                      subtitle: Loc.t("Verschiedene Menüs für verschiedene Arbeit (z. B. Produktion und Mixing). Darunter: frühere Stände, Export und Import.",
                                      "Different menus for different work (e.g. production and mixing). Below: earlier states, export and import.")) {
            HStack(spacing: DS.Space.s) {
                Button { importFile() } label: { Label(Loc.t("Importieren …", "Import …"), systemImage: "square.and.arrow.down") }
                Button { exportCurrent() } label: { Label(Loc.t("Exportieren …", "Export …"), systemImage: "square.and.arrow.up") }
            }
        } content: {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                ProfilesCard(model: model)
                SectionLabel(text: Loc.t("Verlauf (alle Profile) – Wiederherstellen ersetzt das aktive Profil", "History (all profiles) – restoring replaces the active profile")).padding(.top, DS.Space.s)
                saveCard
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    HStack {
                        SectionLabel(text: Loc.t("Gesicherte Versionen", "Saved versions"))
                        Spacer()
                        Text(Loc.t("Automatische Sicherungen: die letzten 30", "Automatic backups: last 30 kept"))
                            .font(DS.Font.caption).foregroundColor(DS.textTertiary)
                    }
                    if model.versionList.isEmpty {
                        Text(Loc.t("Noch keine Versionen gesichert.", "No versions saved yet."))
                            .font(DS.Font.body).foregroundColor(DS.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .dsCard()
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.versionList.enumerated()), id: \.element.id) { i, version in
                                if i > 0 { Rectangle().fill(DS.hairline).frame(height: 1).padding(.leading, 52) }
                                versionRow(version)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: DS.Radius.l).fill(DS.surface))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).stroke(DS.hairline))
                    }
                }
            }
            .padding(.bottom, DS.Space.l)
        }
        .onAppear { model.reloadVersions() }
        .confirmationDialog(Loc.t("Version wiederherstellen?", "Restore version?"), isPresented: Binding(
            get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button(Loc.t("Wiederherstellen", "Restore"), role: .destructive) {
                if let v = restoring { run { try model.restoreVersion(v) }; info = Loc.t("„\(v.name)“ wiederhergestellt.", "Restored “\(v.name)”.") }
            }
        } message: {
            Text(Loc.t("Dein jetziges Menü wird vorher automatisch gesichert.", "Your current menu is saved automatically first."))
        }
    }

    private var saveCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.s) {
                TextField(Loc.t("Name der Version, z. B. „Live-Set Sommer“", "Version name, e.g. “Summer live set”"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveCurrent)
                Button(Loc.t("Aktuelles Menü sichern", "Save Current Menu")) { saveCurrent() }
                    .buttonStyle(.borderedProminent).tint(.brandBlue)
            }
            if let info {
                Label(info, systemImage: "checkmark.circle.fill").font(DS.Font.caption).foregroundColor(DS.success)
            } else {
                Text(Loc.t("Vor jedem Import, jeder LES-Übernahme und jedem Wiederherstellen wird automatisch gesichert.",
                           "A backup is saved automatically before every import, LES push and restore."))
                    .font(DS.Font.caption).foregroundColor(DS.textTertiary)
            }
        }
        .dsCard()
    }

    private func versionRow(_ v: MenuVersion) -> some View {
        HStack(spacing: DS.Space.m) {
            Image(systemName: v.isAutomatic ? "clock.arrow.circlepath" : "bookmark.fill")
                .font(.system(size: 13))
                .foregroundColor(v.isAutomatic ? DS.textTertiary : .accent)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(DS.raised))
            VStack(alignment: .leading, spacing: 2) {
                Text(v.name).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                Text("\(v.date.formatted(date: .abbreviated, time: .shortened)) · \(v.categoryCount) " + Loc.t("Kategorien", "categories")
                     + " · \(v.entryCount) Plugins" + (v.isAutomatic ? " · " + Loc.t("automatisch", "automatic") : ""))
                    .font(DS.Font.caption).foregroundColor(DS.textTertiary)
            }
            Spacer()
            Button(Loc.t("Wiederherstellen …", "Restore …")) { restoring = v }
                .controlSize(.small)
            IconButton(symbol: "square.and.arrow.up", help: Loc.t("Exportieren", "Export")) { exportVersion(v) }
            IconButton(symbol: "trash", help: Loc.t("Löschen", "Delete")) { model.deleteVersion(v) }
        }
        .padding(.horizontal, DS.Space.m)
        .frame(height: 56)
    }

    private func saveCurrent() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let finalName = n.isEmpty ? Loc.t("Menü vom ", "Menu from ") + Date().formatted(date: .abbreviated, time: .shortened) : n
        run { try model.saveVersion(name: finalName, automatic: false) }
        name = ""
        info = Loc.t("„\(finalName)“ gesichert.", "Saved “\(finalName)”.")
    }

    private func exportCurrent() {
        guard let url = savePanel(Loc.t("HYNE ASM Menü", "HYNE ASM Menu")) else { return }
        run { try model.exportMenu(to: url) }
        info = Loc.t("Exportiert: \(url.lastPathComponent)", "Exported: \(url.lastPathComponent)")
    }

    private func exportVersion(_ v: MenuVersion) {
        guard let url = savePanel(v.name) else { return }
        run {
            var doc = try model.versions.load(v.id)
            doc.name = url.deletingPathExtension().lastPathComponent
            try doc.write(to: url)
        }
        info = Loc.t("Exportiert: \(url.lastPathComponent)", "Exported: \(url.lastPathComponent)")
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [menuType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run { try model.importMenuFile(url) }
        info = Loc.t("Importiert: \(url.lastPathComponent) – vorheriges Menü gesichert.", "Imported: \(url.lastPathComponent) – previous menu saved.")
    }

    private var menuType: UTType { UTType(filenameExtension: MenuDocument.fileExtension) ?? .json }

    private func savePanel(_ name: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [menuType]
        panel.nameFieldStringValue = name + "." + MenuDocument.fileExtension
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { info = nil; showError(error) }
    }
}

@MainActor
func showError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = Loc.t("Das hat nicht geklappt", "That didn't work")
    alert.informativeText = error is MenuDocument.NotAMenuFile
        ? Loc.t("Das ist keine HYNE-ASM-Menüdatei.", "This is not a HYNE ASM menu file.")
        : error.localizedDescription
    alert.runModal()
}
