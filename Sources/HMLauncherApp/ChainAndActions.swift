import SwiftUI
import HMLauncherCore

/// Sheet to build or edit a chain: a name and an ordered list of plugins, devices, racks or own presets that are
/// inserted one after the other.
struct ChainBuilderSheet: View {
    let items: [PluginItem]
    let initialName: String
    let initialSteps: [PluginItem]
    let onSave: (String, [PluginItem]) -> Void
    let onCancel: () -> Void
    @State private var name: String
    @State private var steps: [PluginItem]
    @State private var picking = false

    init(items: [PluginItem], name: String = "", steps: [PluginItem] = [],
         onSave: @escaping (String, [PluginItem]) -> Void, onCancel: @escaping () -> Void) {
        self.items = items
        initialName = name
        initialSteps = steps
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: name)
        _steps = State(initialValue: steps)
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !steps.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(initialSteps.isEmpty ? Loc.t("Neue Kette", "New Chain") : Loc.t("Kette bearbeiten", "Edit Chain"))
                    .font(DS.Font.title).foregroundColor(DS.textPrimary)
                Text(Loc.t("Diese Einträge werden der Reihe nach eingefügt – mit einer Taste.",
                           "These items are inserted in order – with one key."))
                    .font(DS.Font.secondary).foregroundColor(DS.textTertiary)
            }
            TextField(Loc.t("Name, z. B. „Vocal Basic“", "Name, e.g. “Vocal Basic”"), text: $name)
                .textFieldStyle(.roundedBorder)
            VStack(spacing: 0) {
                if steps.isEmpty {
                    Text(Loc.t("Noch keine Schritte", "No steps yet"))
                        .font(DS.Font.body).foregroundColor(DS.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 90)
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    if i > 0 { Rectangle().fill(DS.hairline).frame(height: 1).padding(.leading, 44) }
                    stepRow(i, step)
                }
            }
            .background(RoundedRectangle(cornerRadius: DS.Radius.l).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).stroke(DS.hairline))
            Button { picking = true } label: { Label(Loc.t("Schritt hinzufügen …", "Add Step …"), systemImage: "plus") }
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    ItemPicker(items: items, title: Loc.t("Schritt hinzufügen", "Add step")) { item in
                        steps.append(item)
                        picking = false
                    }
                }
            HStack {
                Spacer()
                Button(Loc.t("Abbrechen", "Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(Loc.t("Sichern", "Save")) { onSave(name.trimmingCharacters(in: .whitespaces), steps) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).tint(.brandBlue)
                    .disabled(!canSave)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 460)
        .background(DS.canvas)
        .themedColorScheme()
    }

    private func stepRow(_ i: Int, _ step: PluginItem) -> some View {
        HStack(spacing: DS.Space.m) {
            Text("\(i + 1)").font(DS.Font.keycap).foregroundColor(DS.textSecondary)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(DS.raised))
            Image(systemName: IconCatalog.symbolName(for: IconGuesser.guess(step)))
                .font(.system(size: 12)).foregroundColor(DS.textSecondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.name).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary).lineLimit(1)
                Text(PluginGrouping.formatLabel(step)).font(DS.Font.caption).foregroundColor(DS.textTertiary)
            }
            Spacer()
            IconButton(symbol: "chevron.up", help: Loc.t("Nach oben", "Move up")) { move(i, -1) }.disabled(i == 0)
            IconButton(symbol: "chevron.down", help: Loc.t("Nach unten", "Move down")) { move(i, 1) }.disabled(i == steps.count - 1)
            IconButton(symbol: "xmark", help: Loc.t("Entfernen", "Remove")) { steps.remove(at: i) }
        }
        .padding(.horizontal, DS.Space.m)
        .frame(height: 46)
    }

    private func move(_ i: Int, _ by: Int) {
        let j = i + by
        guard steps.indices.contains(j) else { return }
        steps.swapAt(i, j)
    }
}

/// Value editor for actions that need one (tempo, time signature) before they become an entry.
struct LiveActionValueEditor: View {
    let kind: LiveActionKind
    let onAdd: (LiveAction) -> Void
    @State private var bpm: Double = 120
    @State private var numerator = 4
    @State private var denominator = 4

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text(kind.title).font(DS.Font.columnTitle).foregroundColor(DS.textPrimary)
            if kind == .setTempo {
                HStack {
                    TextField("BPM", value: $bpm, format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder).frame(width: 80)
                    Stepper("", value: $bpm, in: 20...999, step: 1).labelsHidden()
                    Text("BPM").font(DS.Font.secondary).foregroundColor(DS.textTertiary)
                }
            } else {
                HStack {
                    Picker("", selection: $numerator) { ForEach(1...16, id: \.self) { Text("\($0)").tag($0) } }
                        .labelsHidden().frame(width: 64)
                    Text("/").foregroundColor(DS.textTertiary)
                    Picker("", selection: $denominator) { ForEach([1, 2, 4, 8, 16], id: \.self) { Text("\($0)").tag($0) } }
                        .labelsHidden().frame(width: 64)
                }
            }
            Button(Loc.t("Hinzufügen", "Add")) {
                onAdd(kind == .setTempo ? LiveAction(kind: kind, value: min(max(bpm, 20), 999))
                                        : LiveAction(kind: kind, value: Double(numerator), value2: denominator))
            }
            .buttonStyle(.borderedProminent).tint(.brandBlue).keyboardShortcut(.defaultAction)
        }
        .padding(DS.Space.l)
        .frame(width: 240)
    }
}

/// "Live Actions" folder in the settings browser: Live commands that can go into the panel like plugins.
struct LiveActionsGroup: View {
    let search: String
    let categoryName: String
    let onAdd: (LiveAction) -> Void
    @State private var open = false
    @State private var editing: LiveActionKind?

    private var kinds: [LiveActionKind] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? LiveActionKind.allCases : LiveActionKind.allCases.filter { SearchMatcher.score($0.title, q) != nil }
    }

    var body: some View {
        if !kinds.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Button { open.toggle() } label: {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .bold))
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .foregroundColor(DS.textTertiary).frame(width: 10)
                        Image(systemName: "bolt.horizontal").font(.system(size: 12))
                            .foregroundColor(isOpen ? .accent : DS.textSecondary).frame(width: 16)
                        Text(Loc.t("Live-Aktionen", "Live Actions")).font(DS.Font.body).foregroundColor(DS.textPrimary)
                        Spacer(minLength: DS.Space.s)
                        Text("\(kinds.count)").font(DS.Font.caption.monospacedDigit()).foregroundColor(DS.textTertiary)
                    }
                    .padding(.horizontal, DS.Space.s)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .modifier(HoverHighlight())
                }
                .buttonStyle(.plain)
                if isOpen {
                    ForEach(kinds, id: \.self) { kind in row(kind) }
                }
            }
        }
    }

    private var isOpen: Bool { open || !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private func row(_ kind: LiveActionKind) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: IconCatalog.symbolName(for: kind.iconID)).font(.system(size: 11)).foregroundColor(DS.textTertiary).frame(width: 14)
            Text(kind.title).font(DS.Font.body).foregroundColor(DS.textSecondary).lineLimit(1)
            if kind.takesValue {
                Text(kind == .setTempo ? "BPM" : "4/4").font(DS.Font.badge).foregroundColor(DS.textTertiary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(DS.hairline))
            }
            Spacer()
        }
        .padding(.leading, 26).padding(.trailing, DS.Space.s)
        .frame(height: 26)
        .contentShape(Rectangle())
        .modifier(HoverHighlight())
        .onTapGesture(count: 2) { add(kind) }
        .contextMenu {
            Button(Loc.t("Zu „\(categoryName)“ hinzufügen …", "Add to “\(categoryName)” …")) { add(kind) }
        }
        .popover(isPresented: Binding(get: { editing == kind }, set: { if !$0 { editing = nil } }), arrowEdge: .trailing) {
            LiveActionValueEditor(kind: kind) { action in
                onAdd(action)
                editing = nil
            }
        }
        .help(kind.takesValue ? Loc.t("Doppelklick: Wert wählen und hinzufügen", "Double-click: choose a value and add")
                              : Loc.t("Doppelklick fügt hinzu", "Double-click to add"))
    }

    private func add(_ kind: LiveActionKind) {
        if kind.takesValue { editing = kind } else { onAdd(LiveAction(kind: kind)) }
    }
}
