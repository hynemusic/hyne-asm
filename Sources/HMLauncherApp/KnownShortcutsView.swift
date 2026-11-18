import AppKit
import Carbon.HIToolbox
import SwiftUI
import HMLauncherCore

/// Character → key code for the keyboard layout in use (Live and macOS shortcuts follow the character).
@MainActor
enum KeyboardLayout {
    private static var cache: [Character: UInt16]?

    static func keyCode(for character: Character) -> UInt16? {
        if cache == nil { cache = build() }
        return cache?[Character(character.lowercased())]
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

    private static func build() -> [Character: UInt16] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var map: [Character: UInt16] = [:]
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in UInt16(0)..<128 {
                var dead: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
                guard status == noErr, length > 0, let ch = String(utf16CodeUnits: chars, count: length).lowercased().first,
                      !ch.isWhitespace, map[ch] == nil else { continue }
                map[ch] = code
            }
        }
        return map
    }
}

/// Sheet with Live's and macOS's default shortcuts, searchable, marking the ones HYNE ASM uses too.
struct KnownShortcutsSheet: View {
    let config: LauncherConfig
    let onClose: () -> Void
    @State private var query = ""
    @State private var app: KnownShortcut.App = .live

    private var list: [KnownShortcut] {
        let all = app == .live ? KnownShortcuts.live : KnownShortcuts.macOS
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? all : all.filter { $0.title.lowercased().contains(q) || KeyboardLayout.describe($0).lowercased().contains(q) }
    }

    /// The app's own combos, to mark overlaps.
    private var ownCombos: [KeyCombo] {
        [config.shortcuts.closeFocused].compactMap { $0 } + config.shortcuts.closeAll + config.shortcuts.quickSearch + config.itemShortcuts.map(\.combo)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.t("Bekannte Tastenkürzel", "Known Shortcuts")).font(.system(size: 17, weight: .bold)).foregroundColor(DS.textPrimary)
                    Text(Loc.t("Standardkürzel von Ableton Live 12 und macOS – die gängigen, nicht alle.",
                               "Default shortcuts of Ableton Live 12 and macOS – the common ones, not every one."))
                        .font(DS.Font.caption).foregroundColor(DS.textTertiary)
                }
                Spacer()
                Button(Loc.t("Fertig", "Done"), action: onClose).keyboardShortcut(.defaultAction)
            }
            HStack(spacing: DS.Space.m) {
                Picker("", selection: $app) {
                    Text("Ableton Live").tag(KnownShortcut.App.live)
                    Text("macOS").tag(KnownShortcut.App.macOS)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                SearchField(placeholder: Loc.t("Suchen", "Search"), text: $query)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let sections = list.reduce(into: [String]()) { if !$0.contains($1.section) { $0.append($1.section) } }
                    ForEach(sections, id: \.self) { section in
                        SectionLabel(text: section).padding(.top, DS.Space.m).padding(.bottom, DS.Space.xs)
                        ForEach(list.filter { $0.section == section }) { s in row(s) }
                    }
                }
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 560, height: 560)
        .background(DS.canvas)
        .preferredColorScheme(.dark)
    }

    private func row(_ s: KnownShortcut) -> some View {
        let used = ownCombos.contains { s.matches($0, keyCode: KeyboardLayout.keyCode(for:)) }
        return HStack {
            Text(s.title).font(DS.Font.body).foregroundColor(DS.textPrimary)
            if used {
                Label(Loc.t("auch in HYNE ASM", "also in HYNE ASM"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5)).foregroundColor(DS.warning)
            }
            Spacer()
            Text(KeyboardLayout.describe(s))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal, 7).frame(minWidth: 30, minHeight: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(DS.raised))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(DS.hairline))
        }
        .padding(.horizontal, DS.Space.s)
        .frame(height: 32)
        .modifier(HoverHighlight())
    }
}
