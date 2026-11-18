import AppKit
import SwiftUI
import UniformTypeIdentifiers
import HMLauncherCore

// Rows of the entry list on the Library page ("looks like the panel") and the icon picker.

struct EntryRow: View {
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
    var onEditChain: (() -> Void)? = nil
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
                Text("\(entry.children?.count ?? 0)").font(DS.Font.caption).foregroundColor(.dimText)
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
            if let onEditChain { Button(Loc.t("Kette bearbeiten …", "Edit Chain …"), action: onEditChain) }
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
        if entry.action != nil { return Loc.t("Live-Aktion", "Live action") }
        if let steps = entry.chain {
            guard available else { return Loc.t("Ein Schritt fehlt in Live", "A step is missing in Live") }
            return Loc.t("Kette", "Chain") + " · " + steps.map(\.name).joined(separator: " → ")
        }
        guard available else { return Loc.t("Nicht mehr in Live gefunden", "No longer found in Live") }
        let path = entry.path.joined(separator: " / ")
        return entry.displayName == nil ? path : "\(entry.name) · \(path)"
    }

}

struct IconPicker: View {
    let selected: String
    let onPick: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 6), count: 6), spacing: 6) {
                ForEach(IconCatalog.all, id: \.id) { icon in
                    Button { onPick(icon.id) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: icon.symbolName).font(.system(size: 18))
                            Text(icon.label).font(DS.Font.caption).lineLimit(1)
                        }
                        .frame(width: 70, height: 54)
                        .background(icon.id == selected ? Color.rowHighlight : Color.rowBackground)
                        .overlay(alignment: .bottom) {
                            if icon.id == selected { Rectangle().fill(Color.accent).frame(height: 2) }
                        }
                        .cornerRadius(5)
                        .foregroundColor(DS.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .frame(width: 470, height: 380)
        .background(Color.panelBackground)
        .themedColorScheme()
    }
}
