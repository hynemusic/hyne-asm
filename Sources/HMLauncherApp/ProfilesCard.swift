import SwiftUI
import HMLauncherCore

/// Profiles on the Profiles page: switch, add (empty or copy), rename, delete.
struct ProfilesCard: View {
    @ObservedObject var model: AppModel
    @State private var renaming: UUID?
    @State private var deleting: Profile?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                SectionLabel(text: Loc.t("Profile", "Profiles"))
                Spacer()
                Menu {
                    Button(Loc.t("Leeres Profil", "Empty Profile")) { add(copy: false) }
                    Button(Loc.t("Kopie des aktiven Profils", "Copy of the Active Profile")) { add(copy: true) }
                } label: { Label(Loc.t("Neues Profil", "New Profile"), systemImage: "plus") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            VStack(spacing: 0) {
                ForEach(Array(model.config.profiles.enumerated()), id: \.element.id) { i, profile in
                    if i > 0 { Rectangle().fill(DS.hairline).frame(height: 1).padding(.leading, 52) }
                    row(profile)
                }
            }
            .background(RoundedRectangle(cornerRadius: DS.Radius.l).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).stroke(DS.hairline))
            HintText(text: Loc.t("Tipp: Unter Tastenkürzel lässt sich „Nächstes Profil“ auf eine Taste legen; im Menüleisten-Menü wechselst du auch.",
                                 "Tip: “Next profile” can get a key under Shortcuts; the menu bar menu switches too."))
        }
        .confirmationDialog(Loc.t("Profil „\(deleting?.name ?? "")“ löschen?", "Delete profile “\(deleting?.name ?? "")”?"),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(Loc.t("Löschen", "Delete"), role: .destructive) {
                if let p = deleting { model.config.deleteProfile(p.id) }
                deleting = nil
            }
        } message: {
            Text(Loc.t("Seine Kategorien und Einträge sind dann weg. Exportier es vorher, wenn du es behalten willst.",
                       "Its categories and entries are gone then. Export it first if you want to keep it."))
        }
    }

    private func add(copy: Bool) {
        let n = model.config.profiles.count + 1
        let id = model.config.addProfile(named: Loc.t("Profil \(n)", "Profile \(n)"), copyingCurrent: copy)
        renaming = id
    }

    private func row(_ profile: Profile) -> some View {
        let active = profile.id == model.config.activeProfileID
        let entries = (active ? model.config.categories : profile.categories).reduce(0) { $0 + $1.entries.count }
        return HStack(spacing: DS.Space.m) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15)).foregroundColor(active ? .accent : DS.textTertiary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                if renaming == profile.id {
                    InlineNameField(initial: profile.name,
                                    onCommit: { model.config.renameProfile(profile.id, to: $0); renaming = nil },
                                    onCancel: { renaming = nil })
                        .frame(maxWidth: 260)
                } else {
                    Text(profile.name).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary)
                }
                Text((active ? Loc.t("Aktiv · ", "Active · ") : "") + Loc.t("\(entries) Einträge", "\(entries) entries"))
                    .font(DS.Font.caption).foregroundColor(DS.textTertiary)
            }
            Spacer()
            if !active {
                Button(Loc.t("Wechseln", "Switch")) { model.config.switchProfile(to: profile.id) }
                    .buttonStyle(.borderedProminent).tint(.brandBlue).controlSize(.small)
            }
            IconButton(symbol: "pencil", help: Loc.t("Umbenennen", "Rename")) { renaming = profile.id }
            IconButton(symbol: "trash", help: Loc.t("Löschen", "Delete")) { deleting = profile }
                .disabled(active || model.config.profiles.count < 2)
                .opacity(active || model.config.profiles.count < 2 ? 0.35 : 1)
        }
        .padding(.horizontal, DS.Space.m)
        .frame(height: 54)
        .background(active ? DS.selection.opacity(0.5) : .clear)
        .onTapGesture(count: 2) { renaming = profile.id }
    }
}
