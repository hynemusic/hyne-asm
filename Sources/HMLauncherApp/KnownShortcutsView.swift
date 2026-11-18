import AppKit
import Carbon.HIToolbox
import SwiftUI
import HMLauncherCore

/// Character → key code for the keyboard layout in use (Live and macOS shortcuts follow the character).
@MainActor
enum KeyboardLayout {
    private static var cache: [Character: UInt16]?
    private static var labels: [UInt16: String]?

    static func keyCode(for character: Character) -> UInt16? {
        if cache == nil { cache = build().byChar }
        return cache?[Character(character.lowercased())]
    }

    /// What is printed on a key in the current layout ("Z" at key code 16 on a German keyboard).
    static func label(for keyCode: UInt16) -> String? {
        if labels == nil { labels = build().byCode }
        return labels?[keyCode]
    }

    /// ISO keyboards (German, most of Europe) have the extra key next to the left Shift and a tall Return.
    static var isISO: Bool { KBGetLayoutType(Int16(LMGetKbdType())) == kKeyboardISO }

    /// The main key a shortcut uses, as a key code in the current layout.
    static func keyCode(of s: KnownShortcut) -> UInt16? {
        switch s.key {
        case .code(let c): return c
        case .char(let ch): return keyCode(for: ch)
        }
    }

    static func describe(_ s: KnownShortcut) -> String {
        var text = ""
        if s.modifiers.contains(.ctrl) { text += "⌃" }
        if s.modifiers.contains(.alt) { text += "⌥" }
        if s.modifiers.contains(.shift) { text += "⇧" }
        if s.modifiers.contains(.cmd) { text += "⌘" }
        switch s.key {
        case .char(let c): return text + c.uppercased()
        case .code(let code): return text + KeyNames.describe(KeyCombo(keyCode: code, modifiers: []))
        }
    }

    /// Conflicts with Live, macOS and the app's own shortcuts, as lines for a warning.
    static func conflicts(_ combo: KeyCombo, config: LauncherConfig, ignoring itemID: UUID? = nil) -> [String] {
        var lines = KnownShortcuts.conflicts(with: combo, keyCode: keyCode(for:)).map {
            ($0.app == .live ? "Ableton Live: " : "macOS: ") + $0.title
        }
        if let owner = config.shortcutOwner(of: combo, ignoring: itemID) { lines.append("HYNE ASM: " + owner) }
        return lines
    }

    /// Asks before a combination that is already taken is set. True = set it.
    static func confirm(_ combo: KeyCombo, config: LauncherConfig, ignoring itemID: UUID? = nil) -> Bool {
        let lines = conflicts(combo, config: config, ignoring: itemID)
        guard !lines.isEmpty else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Loc.t("\(KeyNames.describe(combo)) ist schon belegt", "\(KeyNames.describe(combo)) is already in use")
        alert.informativeText = lines.map { "• " + $0 }.joined(separator: "\n") + "\n\n"
            + Loc.t("Während Live vorne ist, gewinnt dein HYNE-ASM-Kürzel – die Funktion oben ist dann nicht mehr per Tastatur erreichbar. Trotzdem setzen?",
                    "While Live is in front your HYNE ASM shortcut wins, so the command above can no longer be reached by keyboard. Set it anyway?")
        alert.addButton(withTitle: Loc.t("Trotzdem setzen", "Set Anyway"))
        alert.addButton(withTitle: Loc.t("Abbrechen", "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func build() -> (byChar: [Character: UInt16], byCode: [UInt16: String]) {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return ([:], [:]) }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var map: [Character: UInt16] = [:]
        var byCode: [UInt16: String] = [:]
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in UInt16(0)..<128 {
                var dead: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            0, &dead, chars.count, &length, &chars)
                if status == noErr, length == 0, dead != 0 {
                    // Dead key ("^", "´"): its character appears with the next key, as macOS does with a space.
                    status = UCKeyTranslate(layout, 49, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            0, &dead, chars.count, &length, &chars)
                }
                guard status == noErr, length > 0, let ch = String(utf16CodeUnits: chars, count: length).lowercased().first,
                      !(ch.asciiValue.map { $0 < 33 || $0 == 127 } ?? false) else { continue }
                if byCode[code] == nil { byCode[code] = ch.uppercased().count == 1 ? ch.uppercased() : String(ch) }
                if map[ch] == nil { map[ch] = code }
            }
        }
        return (map, byCode)
    }
}

// MARK: - Keyboard overview

/// One key of the drawn keyboard. `width` in key units (a letter key = 1).
private struct KeySpec: Identifiable {
    let id = UUID()
    let code: UInt16?
    var label: String
    var width: CGFloat = 1
    /// Modifier keys toggle a modifier filter instead of being a shortcut key.
    var modifier: ModifierSet = []
}

@MainActor
private enum KeyboardModel {
    static func rows(iso: Bool) -> [[KeySpec]] {
        func k(_ code: UInt16, _ w: CGFloat = 1, _ name: String? = nil) -> KeySpec {
            KeySpec(code: code, label: name ?? KeyboardLayout.label(for: code) ?? "", width: w)
        }
        func m(_ code: UInt16, _ name: String, _ mod: ModifierSet, _ w: CGFloat) -> KeySpec {
            KeySpec(code: code, label: name, width: w, modifier: mod)
        }
        let fRow: [KeySpec] = [k(53, 1.5, "esc"), k(122, 1, "F1"), k(120, 1, "F2"), k(99, 1, "F3"), k(118, 1, "F4"),
                               k(96, 1, "F5"), k(97, 1, "F6"), k(98, 1, "F7"), k(100, 1, "F8"), k(101, 1, "F9"),
                               k(109, 1, "F10"), k(103, 1, "F11"), k(111, 1.5, "F12")]
        // Apple ISO keyboards: the key left of "1" is 10, the extra one next to the left Shift is 50.
        let numbers: [KeySpec] = [k(iso ? 10 : 50), k(18), k(19), k(20), k(21), k(23), k(22), k(26), k(28), k(25), k(29), k(27), k(24), k(51, 1.5, "⌫")]
        var top: [KeySpec] = [k(48, 1.5, "⇥"), k(12), k(13), k(14), k(15), k(17), k(16), k(32), k(34), k(31), k(35), k(33), k(30)]
        top.append(iso ? k(36, 1.5, "↩") : k(42, 1.5))
        var home: [KeySpec] = [k(57, 1.75, "⇪"), k(0), k(1), k(2), k(3), k(5), k(4), k(38), k(40), k(37), k(41), k(39)]
        home += iso ? [k(42), k(36, 1.25, "↩")] : [k(36, 2.25, "↩")]
        var bottom: [KeySpec] = iso ? [m(56, "⇧", .shift, 1.25), k(50)] : [m(56, "⇧", .shift, 2.25)]
        bottom += [k(6), k(7), k(8), k(9), k(11), k(45), k(46), k(43), k(47), k(44), m(60, "⇧", .shift, 2.25)]
        let space: [KeySpec] = [KeySpec(code: nil, label: "fn"), m(59, "⌃", .ctrl, 1), m(58, "⌥", .alt, 1), m(55, "⌘", .cmd, 1.25),
                                k(49, 5, ""), m(54, "⌘", .cmd, 1.25), m(61, "⌥", .alt, 1),
                                k(123, 1, "←"), k(126, 1, "↑"), k(125, 1, "↓"), k(124, 1, "→")]
        return [fRow, numbers, top, home, bottom, space]
    }
}

/// Sheet: a keyboard on the left, the shortcuts on the right. Hovering a shortcut lights up its keys; hovering a key
/// shows the shortcuts that use it. Clicking ⌘ ⌥ ⇧ ⌃ filters by those modifiers.
struct KnownShortcutsSheet: View {
    let config: LauncherConfig
    let onClose: () -> Void
    @State private var query = ""
    @State private var app: KnownShortcut.App? = nil
    @State private var hoveredShortcut: String? = KnownShortcutsSheet.debugHover
    /// Developer aid for screenshots: a shortcut id shown as hovered.
    static var debugHover: String?
    @State private var hoveredKey: UInt16?
    @State private var modFilter: ModifierSet = []

    private static let unit: CGFloat = 40
    private static let gap: CGFloat = 5

    private var all: [KnownShortcut] { KnownShortcuts.live + KnownShortcuts.macOS + KnownShortcuts.hyne(config) }

    private var list: [KnownShortcut] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { s in
            (app == nil || s.app == app)
                && (modFilter.isEmpty || s.modifiers == modFilter)
                && (q.isEmpty || s.title.lowercased().contains(q) || KeyboardLayout.describe(s).lowercased().contains(q))
        }
    }

    private var hovered: KnownShortcut? { all.first { $0.id == hoveredShortcut } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            header
            HStack(alignment: .top, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    keyboard
                    legend
                }
                listColumn.frame(width: 360)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 1180, height: 580)
        .background(DS.canvas)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Loc.t("Tastenkürzel-Übersicht", "Shortcut Overview")).font(.system(size: 17, weight: .bold)).foregroundColor(DS.textPrimary)
                Text(Loc.t("Fahr über eine Taste oder ein Kürzel. Klick auf ⌘ ⌥ ⇧ ⌃, um nach Modifiern zu filtern. Live 12 und macOS: die gängigen Standardkürzel.",
                           "Hover a key or a shortcut. Click ⌘ ⌥ ⇧ ⌃ to filter by modifiers. Live 12 and macOS: the common default shortcuts."))
                    .font(DS.Font.caption).foregroundColor(DS.textTertiary)
            }
            Spacer()
            Button(Loc.t("Fertig", "Done"), action: onClose).keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Keyboard

    private var keyboard: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            ForEach(Array(KeyboardModel.rows(iso: KeyboardLayout.isISO).enumerated()), id: \.offset) { r, row in
                HStack(spacing: Self.gap) {
                    ForEach(row) { key in keyView(key, short: r == 0) }
                }
            }
        }
        .padding(DS.Space.m)
        .background(RoundedRectangle(cornerRadius: DS.Radius.l).fill(Color(white: 0.075)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).stroke(DS.hairline))
    }

    /// Shortcuts on this key under the current modifier filter.
    private func uses(_ code: UInt16) -> [KnownShortcut] {
        all.filter { KeyboardLayout.keyCode(of: $0) == code && (modFilter.isEmpty || $0.modifiers == modFilter) && (app == nil || $0.app == app) }
    }

    private func keyView(_ key: KeySpec, short: Bool) -> some View {
        let width = key.width * Self.unit + (key.width - 1) * Self.gap
        let height = short ? Self.unit * 0.62 : Self.unit
        let isModifier = !key.modifier.isEmpty
        let lit: Bool = {
            if let h = hovered {
                if isModifier { return h.modifiers.contains(key.modifier) }
                return key.code != nil && KeyboardLayout.keyCode(of: h) == key.code
            }
            if isModifier { return modFilter.contains(key.modifier) }
            return key.code != nil && key.code == hoveredKey
        }()
        let usedBy = key.code.map(uses) ?? []
        let apps = Set(usedBy.map(\.app))
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(lit ? Color.brandBlue : (isModifier && modFilter.contains(key.modifier) ? Color.brandBlue.opacity(0.4) : Color(white: 0.2)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(lit ? Color.white.opacity(0.35) : Color.white.opacity(0.06)))
                .shadow(color: .black.opacity(0.5), radius: 0, y: 1.5)
            Text(key.label)
                .font(.system(size: key.label.count > 2 ? 10 : 13, weight: .medium, design: .rounded))
                .foregroundColor(lit ? .white : (usedBy.isEmpty && !isModifier ? DS.textTertiary : DS.textPrimary))
                .frame(width: width, height: height)
            if !isModifier && !apps.isEmpty && !lit {
                HStack(spacing: 2) {
                    ForEach([KnownShortcut.App.live, .macOS, .hyne].filter(apps.contains), id: \.self) { a in
                        Circle().fill(color(a)).frame(width: 5, height: 5)
                    }
                }
                .padding(5)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onHover { inside in
            guard !isModifier, let code = key.code else { return }
            if inside { hoveredKey = code; hoveredShortcut = nil } else if hoveredKey == code { hoveredKey = nil }
        }
        .onTapGesture {
            guard isModifier else { return }
            if modFilter.contains(key.modifier) { modFilter.remove(key.modifier) } else { modFilter.insert(key.modifier) }
        }
        .help(usedBy.isEmpty ? "" : usedBy.map { "\(KeyboardLayout.describe($0))  \($0.title)" }.joined(separator: "\n"))
    }

    private var legend: some View {
        HStack(spacing: DS.Space.l) {
            ForEach([KnownShortcut.App.live, .macOS, .hyne], id: \.self) { a in
                HStack(spacing: 5) {
                    Circle().fill(color(a)).frame(width: 7, height: 7)
                    Text(appName(a)).font(DS.Font.caption).foregroundColor(DS.textSecondary)
                }
            }
            Spacer()
            if !modFilter.isEmpty {
                Button(Loc.t("Modifier-Filter löschen", "Clear modifier filter")) { modFilter = [] }
                    .buttonStyle(.borderless).font(DS.Font.caption)
            }
        }
    }

    // MARK: List

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Picker("", selection: $app) {
                Text(Loc.t("Alle", "All")).tag(KnownShortcut.App?.none)
                Text("Live").tag(KnownShortcut.App?.some(.live))
                Text("macOS").tag(KnownShortcut.App?.some(.macOS))
                Text("HYNE ASM").tag(KnownShortcut.App?.some(.hyne))
            }
            .pickerStyle(.segmented).labelsHidden()
            SearchField(placeholder: Loc.t("Suchen", "Search"), text: $query)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if list.isEmpty {
                            Text(Loc.t("Keine Kürzel", "No shortcuts")).font(DS.Font.caption).foregroundColor(DS.textTertiary).padding(DS.Space.m)
                        }
                        ForEach(list) { s in row(s).id(s.id) }
                    }
                }
                .onChange(of: hoveredKey) { code in
                    if let code, let first = list.first(where: { KeyboardLayout.keyCode(of: $0) == code }) {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(first.id, anchor: .center) }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: DS.Radius.l).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).stroke(DS.hairline))
        }
    }

    /// Where HYNE ASM uses the same combination (for Live/macOS rows), for the warning tooltip.
    private func ownUses(_ s: KnownShortcut) -> [String] {
        guard s.app != .hyne, let code = KeyboardLayout.keyCode(of: s) else { return [] }
        return KnownShortcuts.hyne(config).filter { KeyboardLayout.keyCode(of: $0) == code && $0.modifiers == s.modifiers }.map(\.title)
    }

    private func row(_ s: KnownShortcut) -> some View {
        let onKey = hoveredKey != nil && KeyboardLayout.keyCode(of: s) == hoveredKey
        let dimmed = hoveredKey != nil && !onKey
        let own = ownUses(s)
        return HStack(spacing: DS.Space.s) {
            Circle().fill(color(s.app)).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(DS.Font.body).foregroundColor(DS.textPrimary).lineLimit(1)
                Text(s.app == .hyne ? "HYNE ASM" : "\(appName(s.app)) · \(s.section)").font(.system(size: 10)).foregroundColor(DS.textTertiary)
            }
            if !own.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundColor(DS.warning)
                    .help(Loc.t("Auch in HYNE ASM belegt:\n", "Also used in HYNE ASM:\n") + own.map { "• " + $0 }.joined(separator: "\n"))
            }
            Spacer(minLength: DS.Space.s)
            Text(KeyboardLayout.describe(s))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal, 7).frame(minWidth: 30, minHeight: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(DS.raised))
        }
        .padding(.horizontal, DS.Space.m)
        .frame(height: 40)
        .background(hoveredShortcut == s.id || onKey ? DS.selection : .clear)
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hoveredShortcut = s.id; hoveredKey = nil } else if hoveredShortcut == s.id { hoveredShortcut = nil }
        }
    }

    private func color(_ app: KnownShortcut.App) -> Color {
        switch app {
        case .live: return .brandCoral
        case .macOS: return Color(white: 0.75)
        case .hyne: return .brandBlue
        }
    }

    private func appName(_ app: KnownShortcut.App) -> String {
        switch app {
        case .live: return "Ableton Live"
        case .macOS: return "macOS"
        case .hyne: return "HYNE ASM"
        }
    }
}
