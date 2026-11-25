import SwiftUI
import AppKit
import HMLauncherCore

/// The wrench next to the "Plugins & Presets" count: shows the folders Live reads the list from
/// and how to add more in Live (the list comes from Live's browser, so folders are managed there).
struct LibraryLocationsButton: View {
    let liveVersion: String?
    let onReload: () -> Void
    @State private var open = false

    var body: some View {
        IconButton(symbol: "wrench.adjustable", help: Loc.t("Ordner, aus denen Live die Liste liest", "Folders Live reads this list from")) {
            open.toggle()
        }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            LibraryLocationsPopover(liveVersion: liveVersion, onReload: { onReload(); open = false })
        }
    }
}

struct LibraryLocationsPopover: View {
    let liveVersion: String?
    let onReload: () -> Void
    @State private var locations: [LibraryLocation] = []

    private var pluginFolders: [LibraryLocation] {
        locations.filter { $0.kind == .pluginFolder && FileManager.default.fileExists(atPath: $0.path) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Loc.t("Bibliotheks-Ordner", "Library Locations")).font(DS.Font.columnTitle).foregroundColor(DS.textPrimary)
                Text(Loc.t("Die Liste kommt aus Lives Browser. Live liest diese Ordner.",
                           "The list comes from Live's browser. Live reads these folders."))
                    .font(DS.Font.caption).foregroundColor(DS.textTertiary)
            }
            // Short lists show in full; long ones (many Places) scroll at a fixed height.
            ViewThatFits(in: .vertical) {
                folderList.fixedSize(horizontal: false, vertical: true)
                ScrollView { folderList }.frame(height: 340)
            }
            .frame(maxHeight: 340)
            guidance
        }
        .padding(DS.Space.l)
        .frame(width: 420)
        .onAppear { locations = LibraryLocations.all(liveVersion: liveVersion) }
    }

    private var folderList: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            section(Loc.t("Plugins", "Plug-ins"), pluginFolders)
            section(Loc.t("User Library", "User Library"), locations.filter { $0.kind == .userLibrary })
            let places = locations.filter { $0.kind == .place }
            if places.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    SectionLabel(text: Loc.t("Orte", "Places"))
                    Text(Loc.t("Keine eigenen Ordner in Live.", "No folders added in Live."))
                        .font(DS.Font.caption).foregroundColor(DS.textTertiary)
                }
            } else {
                section(Loc.t("Orte", "Places"), places)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func section(_ title: String, _ items: [LibraryLocation]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: title).padding(.bottom, 2)
                ForEach(items, id: \.self) { row($0) }
            }
        }
    }

    private func row(_ location: LibraryLocation) -> some View {
        let exists = FileManager.default.fileExists(atPath: location.path)
        return HStack(spacing: DS.Space.s) {
            Image(systemName: exists ? "folder" : "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundColor(exists ? DS.textSecondary : .orange)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(location.name).font(DS.Font.secondaryStrong).foregroundColor(DS.textPrimary).lineLimit(1)
                Text(exists ? location.path : location.path + Loc.t(" (nicht gefunden)", " (not found)"))
                    .font(DS.Font.caption).foregroundColor(DS.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: DS.Space.s)
            if exists {
                IconButton(symbol: "arrow.up.forward.square", help: Loc.t("Im Finder zeigen", "Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: location.path)])
                }
            }
        }
        .padding(.vertical, 3)
        .tooltip(location.path)
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Divider()
            Text(Loc.t("Ordner hinzufügen oder entfernen", "Add or remove a folder")).font(DS.Font.secondaryStrong).foregroundColor(DS.textPrimary)
            step("1", Loc.t("Presets: In Lives Browser unter „Orte“ auf „Ordner hinzufügen …“ klicken. Entfernen per Rechtsklick → „Aus Seitenleiste entfernen“.",
                            "Presets: in Live's browser, click \"Add Folder…\" under Places. To remove one, right-click it and choose \"Remove from Sidebar\"."))
            step("2", Loc.t("Plugins: Live → Einstellungen → Plug-Ins → „Eigenen VST3-/VST2-Ordner verwenden“ einschalten und Ordner wählen.",
                            "Plug-ins: Live → Settings → Plug-Ins → turn on \"Use VST3/VST2 Custom Folder\" and pick the folder."))
            step("3", Loc.t("Danach hier die Liste neu laden.", "Then reload the list here."))
            HStack {
                Spacer()
                Button(Loc.t("Liste neu laden", "Reload List"), action: onReload)
            }
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(number).font(DS.Font.caption.monospacedDigit().weight(.semibold)).foregroundColor(DS.textTertiary)
            Text(text).font(DS.Font.caption).foregroundColor(DS.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
