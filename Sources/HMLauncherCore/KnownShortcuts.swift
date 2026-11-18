import Foundation

/// A shortcut that Ableton Live or macOS already uses (Live 12 on the Mac, default settings).
public struct KnownShortcut: Identifiable, Equatable, Sendable {
    public enum App: String, Sendable { case live, macOS, hyne }
    /// Live/macOS shortcuts follow the character on the key, so ⌘Z is a different physical key on a German keyboard.
    public enum Key: Hashable, Sendable {
        case char(Character)
        case code(UInt16)   // keys without a character: Space, Tab, Esc, arrows, F-keys
    }

    /// Includes the keys: one command can have several combinations ("Close all plugin windows": ⌥⌘W and ⌘Esc).
    public var id: String { "\(app.rawValue)|\(section)|\(title)|\(key)|\(modifiers.rawValue)" }
    public let app: App
    public let section: String
    public let title: String
    public let key: Key
    public let modifiers: ModifierSet

    public init(_ app: App, _ section: String, _ title: String, _ key: Key, _ modifiers: ModifierSet) {
        self.app = app; self.section = section; self.title = title; self.key = key; self.modifiers = modifiers
    }

    /// Matching uses the current keyboard layout: `keyCode(for:)` turns a character into its key code.
    public func matches(_ combo: KeyCombo, keyCode: (Character) -> UInt16?) -> Bool {
        guard combo.modifiers == modifiers else { return false }
        switch key {
        case .code(let c): return c == combo.keyCode
        case .char(let ch): return keyCode(ch) == combo.keyCode
        }
    }
}

/// The common default shortcuts of Ableton Live 12 (Mac) and of macOS. Not every shortcut Live has —
/// the ones people actually press, so a new shortcut doesn't silently take one of them away.
public enum KnownShortcuts {
    private static let space: UInt16 = 49, tab: UInt16 = 48, esc: UInt16 = 53, f9: UInt16 = 101
    private static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126

    public static var live: [KnownShortcut] {
        let file = Loc.t("Datei", "File"), edit = Loc.t("Bearbeiten", "Edit"), create = Loc.t("Erstellen", "Create")
        let view = Loc.t("Ansicht", "View"), grid = Loc.t("Raster", "Grid"), transport = Loc.t("Transport", "Transport")
        func s(_ section: String, _ de: String, _ en: String, _ key: KnownShortcut.Key, _ mods: ModifierSet) -> KnownShortcut {
            KnownShortcut(.live, section, Loc.t(de, en), key, mods)
        }
        return [
            s(file, "Neues Live-Set", "New Live Set", .char("n"), [.cmd]),
            s(file, "Live-Set öffnen", "Open Live Set", .char("o"), [.cmd]),
            s(file, "Live-Set sichern", "Save Live Set", .char("s"), [.cmd]),
            s(file, "Live-Set sichern unter", "Save Live Set As", .char("s"), [.cmd, .shift]),
            s(file, "Audio/Video exportieren", "Export Audio/Video", .char("r"), [.cmd, .shift]),
            s(file, "Fenster schließen", "Close Window", .char("w"), [.cmd]),
            s(file, "Einstellungen", "Settings", .char(","), [.cmd]),
            s(file, "Live beenden", "Quit Live", .char("q"), [.cmd]),
            s(edit, "Widerrufen", "Undo", .char("z"), [.cmd]),
            s(edit, "Wiederholen", "Redo", .char("z"), [.cmd, .shift]),
            s(edit, "Ausschneiden", "Cut", .char("x"), [.cmd]),
            s(edit, "Kopieren", "Copy", .char("c"), [.cmd]),
            s(edit, "Einsetzen", "Paste", .char("v"), [.cmd]),
            s(edit, "Duplizieren", "Duplicate", .char("d"), [.cmd]),
            s(edit, "Alles auswählen", "Select All", .char("a"), [.cmd]),
            s(edit, "Clip teilen", "Split Clip", .char("e"), [.cmd]),
            s(edit, "Konsolidieren", "Consolidate", .char("j"), [.cmd]),
            s(edit, "Umbenennen", "Rename", .char("r"), [.cmd]),
            s(edit, "Auswahl loopen", "Loop Selection", .char("l"), [.cmd]),
            s(edit, "Quantisieren", "Quantize", .char("u"), [.cmd]),
            s(edit, "Quantisierungseinstellungen", "Quantize Settings", .char("u"), [.cmd, .shift]),
            s(edit, "Im Browser suchen", "Search in Browser", .char("f"), [.cmd]),
            s(create, "Audiospur einfügen", "Insert Audio Track", .char("t"), [.cmd]),
            s(create, "MIDI-Spur einfügen", "Insert MIDI Track", .char("t"), [.cmd, .shift]),
            s(create, "Return-Spur einfügen", "Insert Return Track", .char("t"), [.cmd, .alt]),
            s(create, "Szene einfügen", "Insert Scene", .char("i"), [.cmd]),
            s(create, "Szene aufnehmen und einfügen", "Capture and Insert Scene", .char("i"), [.cmd, .shift]),
            s(create, "Spuren gruppieren", "Group Tracks", .char("g"), [.cmd]),
            s(create, "Gruppierung aufheben", "Ungroup Tracks", .char("g"), [.cmd, .shift]),
            s(view, "Browser ein/aus", "Show/Hide Browser", .char("b"), [.cmd, .alt]),
            s(view, "Detailansicht ein/aus", "Show/Hide Detail View", .char("l"), [.cmd, .alt]),
            s(view, "In/Out ein/aus", "Show/Hide In/Out", .char("i"), [.cmd, .alt]),
            s(view, "Sends ein/aus", "Show/Hide Sends", .char("s"), [.cmd, .alt]),
            s(view, "Mixer ein/aus", "Show/Hide Mixer", .char("m"), [.cmd, .alt]),
            s(view, "Übersicht ein/aus", "Show/Hide Overview", .char("o"), [.cmd, .alt]),
            s(view, "Vollbild", "Full Screen", .char("f"), [.cmd, .ctrl]),
            s(view, "MIDI-Zuweisungsmodus", "MIDI Map Mode", .char("m"), [.cmd]),
            s(view, "Tasten-Zuweisungsmodus", "Key Map Mode", .char("k"), [.cmd]),
            s(view, "Session/Arrangement wechseln", "Toggle Session/Arrangement", .code(tab), []),
            s(view, "Clip/Device-Ansicht wechseln", "Toggle Clip/Device View", .code(tab), [.shift]),
            s(grid, "Raster enger", "Narrow Grid", .char("1"), [.cmd]),
            s(grid, "Raster weiter", "Widen Grid", .char("2"), [.cmd]),
            s(grid, "Triolenraster", "Triplet Grid", .char("3"), [.cmd]),
            s(grid, "Am Raster ausrichten", "Snap to Grid", .char("4"), [.cmd]),
            s(grid, "Festes Raster", "Fixed Grid", .char("5"), [.cmd]),
            s(transport, "Wiedergabe/Stopp", "Play/Stop", .code(space), []),
            s(transport, "Aufnahme", "Record", .code(f9), []),
        ]
    }

    public static var macOS: [KnownShortcut] {
        let system = "macOS", windows = Loc.t("Fenster & Apps", "Windows & Apps"), shots = Loc.t("Bildschirmfotos", "Screenshots")
        func s(_ section: String, _ de: String, _ en: String, _ key: KnownShortcut.Key, _ mods: ModifierSet) -> KnownShortcut {
            KnownShortcut(.macOS, section, Loc.t(de, en), key, mods)
        }
        return [
            s(system, "Spotlight", "Spotlight", .code(space), [.cmd]),
            s(system, "Vorherige Eingabequelle", "Previous Input Source", .code(space), [.ctrl]),
            s(system, "Nächste Eingabequelle", "Next Input Source", .code(space), [.ctrl, .alt]),
            s(system, "Emoji & Symbole", "Emoji & Symbols", .code(space), [.ctrl, .cmd]),
            s(system, "Bildschirm sperren", "Lock Screen", .char("q"), [.ctrl, .cmd]),
            s(system, "Sofort beenden", "Force Quit", .code(esc), [.cmd, .alt]),
            s(system, "Dock ein/aus", "Show/Hide Dock", .char("d"), [.cmd, .alt]),
            s(windows, "App wechseln", "Switch Apps", .code(tab), [.cmd]),
            s(windows, "Nächstes Fenster der App", "Next Window of App", .code(50), [.cmd]),
            s(windows, "App ausblenden", "Hide App", .char("h"), [.cmd]),
            s(windows, "Andere ausblenden", "Hide Others", .char("h"), [.cmd, .alt]),
            s(windows, "Fenster minimieren", "Minimize Window", .char("m"), [.cmd]),
            s(windows, "App beenden", "Quit App", .char("q"), [.cmd]),
            s(windows, "Mission Control", "Mission Control", .code(up), [.ctrl]),
            s(windows, "App-Fenster", "App Windows", .code(down), [.ctrl]),
            s(windows, "Space nach links", "Move Left a Space", .code(left), [.ctrl]),
            s(windows, "Space nach rechts", "Move Right a Space", .code(right), [.ctrl]),
            s(shots, "Ganzer Bildschirm", "Whole Screen", .char("3"), [.cmd, .shift]),
            s(shots, "Auswahl", "Selection", .char("4"), [.cmd, .shift]),
            s(shots, "Bildschirmfoto-Werkzeuge", "Screenshot Tools", .char("5"), [.cmd, .shift]),
        ]
    }

    public static var all: [KnownShortcut] { live + macOS }

    /// The app's own shortcuts in the same form, for the keyboard overview (panel keys left out: they only
    /// work while the panel is open).
    public static func hyne(_ config: LauncherConfig) -> [KnownShortcut] {
        let section = "HYNE ASM"
        func s(_ title: String, _ c: KeyCombo) -> KnownShortcut { KnownShortcut(.hyne, section, title, .code(c.keyCode), c.modifiers) }
        var list: [KnownShortcut] = []
        if let c = config.shortcuts.closeFocused { list.append(s(Loc.t("Fokussiertes Plugin-Fenster schließen", "Close focused plugin window"), c)) }
        list += config.shortcuts.closeAll.map { s(Loc.t("Alle Plugin-Fenster schließen", "Close all plugin windows"), $0) }
        list += config.shortcuts.quickSearch.map { s(Loc.t("Schnellsuche öffnen", "Open quick search"), $0) }
        list += config.itemShortcuts.map { s(Loc.t("„\($0.name)“ einfügen", "Insert “\($0.name)”"), $0.combo) }
        return list
    }

    public static func conflicts(with combo: KeyCombo, keyCode: (Character) -> UInt16?) -> [KnownShortcut] {
        all.filter { $0.matches(combo, keyCode: keyCode) }
    }
}
