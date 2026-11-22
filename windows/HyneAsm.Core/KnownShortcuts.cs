namespace HyneAsm.Core;

/// <summary>A shortcut that Ableton Live or Windows already uses (Live 12 on Windows, default settings).
/// The tables differ from the Mac ones by design: the commands are the same, the keys are Windows keys.</summary>
public sealed record KnownShortcut
{
    public enum AppKind { Live, Windows, Hyne }

    /// <summary>Live/Windows shortcuts follow the character on the key, so Ctrl+Z is a different physical key on a German
    /// keyboard. A key without a character (Space, Tab, Esc, arrows, F-keys) is a Windows virtual key.</summary>
    public readonly record struct Key
    {
        public char? Char { get; }
        public ushort? Code { get; }
        Key(char? c, ushort? code) { Char = c; Code = code; }
        public static Key Of(char c) => new(c, null);
        public static Key VirtualKey(ushort vk) => new(null, vk);
        public override string ToString() => Char is { } c ? $"char({c})" : $"code({Code})";
    }

    /// <summary>Includes the keys: one command can have several combinations.</summary>
    public string Id => $"{App}|{Section}|{Title}|{Pressed}|{(byte)Modifiers}";
    public AppKind App { get; }
    public string Section { get; }
    public string Title { get; }
    public Key Pressed { get; }
    public WinModifiers Modifiers { get; }

    public KnownShortcut(AppKind app, string section, string title, Key key, WinModifiers modifiers)
    {
        App = app; Section = section; Title = title; Pressed = key; Modifiers = modifiers;
    }

    /// <summary>The stored (Mac-format) combo is translated to a Windows key first. <paramref name="vkForChar"/> turns a
    /// character into its virtual key on the current layout (default: US layout).</summary>
    public bool Matches(KeyCombo combo, Func<char, ushort?>? vkForChar = null)
    {
        if (KeyTranslation.ToWindows(combo) is not { } win || win.mods != Modifiers) return false;
        if (Pressed.Code is { } code) return code == win.vk;
        return (vkForChar ?? KnownShortcuts.UsLayoutVk)(Pressed.Char!.Value) == win.vk;
    }
}

/// <summary>The common default shortcuts of Ableton Live 12 (Windows) and of Windows. Not every shortcut either has -
/// the ones people actually press, so a new shortcut doesn't silently take one of them away. The Live commands
/// are the ones the Mac table covers, with their Windows combos from the Live 12 manual's keyboard-shortcut chapter.</summary>
public static class KnownShortcuts
{
    const ushort Tab = 0x09, Esc = 0x1B, Space = 0x20, Print = 0x2C;
    const ushort Left = 0x25, Up = 0x26, Right = 0x27, Down = 0x28, F4 = 0x73, F9 = 0x78, F11 = 0x7A, F12 = 0x7B;
    const WinModifiers C = WinModifiers.Ctrl, A = WinModifiers.Alt, S = WinModifiers.Shift, W = WinModifiers.Win;

    /// <summary>US-layout virtual key of a character: letters and digits are their own code, punctuation the OEM keys.</summary>
    public static ushort? UsLayoutVk(char c)
    {
        c = char.ToUpperInvariant(c);
        if (c is >= 'A' and <= 'Z' or >= '0' and <= '9') return c;
        return c switch
        {
            ',' => 0xBC, '.' => 0xBE, '-' => 0xBD, '=' => 0xBB, ';' => 0xBA, '/' => 0xBF, '`' => 0xC0,
            '[' => 0xDB, ']' => 0xDD, '\\' => 0xDC, '\'' => 0xDE, _ => null,
        };
    }

    static KnownShortcut Ch(KnownShortcut.AppKind app, string section, string title, char c, WinModifiers m) =>
        new(app, section, title, KnownShortcut.Key.Of(c), m);

    static KnownShortcut Vk(KnownShortcut.AppKind app, string section, string title, ushort vk, WinModifiers m) =>
        new(app, section, title, KnownShortcut.Key.VirtualKey(vk), m);

    public static IReadOnlyList<KnownShortcut> Live
    {
        get
        {
            string file = Loc.T("Datei", "File"), edit = Loc.T("Bearbeiten", "Edit"), create = Loc.T("Erstellen", "Create");
            string view = Loc.T("Ansicht", "View"), grid = Loc.T("Raster", "Grid"), transport = Loc.T("Transport", "Transport");
            KnownShortcut s(string section, string de, string en, char c, WinModifiers m) => Ch(KnownShortcut.AppKind.Live, section, Loc.T(de, en), c, m);
            KnownShortcut k(string section, string de, string en, ushort vk, WinModifiers m) => Vk(KnownShortcut.AppKind.Live, section, Loc.T(de, en), vk, m);
            return new[]
            {
                s(file, "Neues Live-Set", "New Live Set", 'n', C),
                s(file, "Live-Set öffnen", "Open Live Set", 'o', C),
                s(file, "Live-Set sichern", "Save Live Set", 's', C),
                s(file, "Live-Set sichern unter", "Save Live Set As", 's', C | S),
                s(file, "Audio/Video exportieren", "Export Audio/Video", 'r', C | S),
                s(file, "Einstellungen", "Settings", ',', C),
                s(file, "Live beenden", "Quit Live", 'q', C),
                s(edit, "Widerrufen", "Undo", 'z', C),
                s(edit, "Wiederholen", "Redo", 'y', C),
                s(edit, "Ausschneiden", "Cut", 'x', C),
                s(edit, "Kopieren", "Copy", 'c', C),
                s(edit, "Einsetzen", "Paste", 'v', C),
                s(edit, "Duplizieren", "Duplicate", 'd', C),
                s(edit, "Alles auswählen", "Select All", 'a', C),
                s(edit, "Clip teilen", "Split Clip", 'e', C),
                s(edit, "Konsolidieren", "Consolidate", 'j', C),
                s(edit, "Umbenennen", "Rename", 'r', C),
                s(edit, "Auswahl loopen", "Loop Selection", 'l', C),
                s(edit, "Quantisieren", "Quantize", 'u', C),
                s(edit, "Quantisierungseinstellungen", "Quantize Settings", 'u', C | S),
                s(edit, "Im Browser suchen", "Search in Browser", 'f', C),
                s(create, "Audiospur einfügen", "Insert Audio Track", 't', C),
                s(create, "MIDI-Spur einfügen", "Insert MIDI Track", 't', C | S),
                s(create, "Return-Spur einfügen", "Insert Return Track", 't', C | A),
                s(create, "Szene einfügen", "Insert Scene", 'i', C),
                s(create, "Szene aufnehmen und einfügen", "Capture and Insert Scene", 'i', C | S),
                s(create, "Spuren gruppieren", "Group Tracks", 'g', C),
                s(create, "Gruppierung aufheben", "Ungroup Tracks", 'g', C | S),
                s(view, "Browser ein/aus", "Show/Hide Browser", 'b', C | A),
                s(view, "Clip-Ansicht ein/aus", "Show/Hide Clip View", '3', C | A),
                s(view, "Geräteansicht ein/aus", "Show/Hide Device View", '4', C | A),
                s(view, "In/Out ein/aus", "Show/Hide In/Out", 'i', C | A),
                s(view, "Sends ein/aus", "Show/Hide Sends", 's', C | A),
                s(view, "Mixer ein/aus", "Show/Hide Mixer", 'm', C | A),
                s(view, "Übersicht ein/aus", "Show/Hide Overview", 'o', C | A),
                k(view, "Vollbild", "Full Screen", F11, WinModifiers.None),
                s(view, "MIDI-Zuweisungsmodus", "MIDI Map Mode", 'm', C),
                s(view, "Tasten-Zuweisungsmodus", "Key Map Mode", 'k', C),
                k(view, "Session/Arrangement wechseln", "Toggle Session/Arrangement", Tab, WinModifiers.None),
                k(view, "Clip/Device-Ansicht wechseln", "Toggle Clip/Device View", Tab, S),
                k(view, "Clip/Device-Ansicht wechseln", "Toggle Clip/Device View", F12, WinModifiers.None),
                s(grid, "Raster enger", "Narrow Grid", '1', C),
                s(grid, "Raster weiter", "Widen Grid", '2', C),
                s(grid, "Triolenraster", "Triplet Grid", '3', C),
                s(grid, "Am Raster ausrichten", "Snap to Grid", '4', C),
                s(grid, "Festes Raster", "Fixed Grid", '5', C),
                k(transport, "Wiedergabe/Stopp", "Play/Stop", Space, WinModifiers.None),
                k(transport, "Aufnahme", "Record", F9, WinModifiers.None),
            };
        }
    }

    public static IReadOnlyList<KnownShortcut> Windows
    {
        get
        {
            string system = "Windows", windows = Loc.T("Fenster & Apps", "Windows & Apps"), shots = Loc.T("Bildschirmfotos", "Screenshots");
            KnownShortcut s(string section, string de, string en, char c, WinModifiers m) => Ch(KnownShortcut.AppKind.Windows, section, Loc.T(de, en), c, m);
            KnownShortcut k(string section, string de, string en, ushort vk, WinModifiers m) => Vk(KnownShortcut.AppKind.Windows, section, Loc.T(de, en), vk, m);
            return new[]
            {
                k(system, "Startmenü", "Start Menu", Esc, C),
                k(system, "Task-Manager", "Task Manager", Esc, C | S),
                k(system, "Eingabesprache wechseln", "Switch Input Language", Space, C),
                k(system, "Eingabesprache wechseln", "Switch Input Language", Space, W),
                k(system, "Eingabesprache wechseln", "Switch Input Language", Space, W | S),
                s(system, "Bildschirm sperren", "Lock Screen", 'l', W),
                s(system, "Ausführen", "Run", 'r', W),
                s(system, "Einstellungen", "Settings", 'i', W),
                s(system, "Emoji & Symbole", "Emoji & Symbols", '.', W),
                s(system, "Zwischenablageverlauf", "Clipboard History", 'v', W),
                s(system, "Suche", "Search", 's', W),
                s(system, "Schnelleinstellungen", "Quick Settings", 'a', W),
                k(windows, "App wechseln", "Switch Apps", Tab, A),
                k(windows, "App wechseln (rückwärts)", "Switch Apps (Backwards)", Tab, A | S),
                k(windows, "Fenster schließen", "Close Window", F4, A),
                k(windows, "Aufgabenansicht", "Task View", Tab, W),
                s(windows, "Desktop anzeigen", "Show Desktop", 'd', W),
                s(windows, "Alle Fenster minimieren", "Minimize All Windows", 'm', W),
                s(windows, "Explorer", "File Explorer", 'e', W),
                k(windows, "Fenster maximieren", "Maximize Window", Up, W),
                k(windows, "Fenster minimieren", "Minimize Window", Down, W),
                k(windows, "Fenster links andocken", "Snap Window Left", Left, W),
                k(windows, "Fenster rechts andocken", "Snap Window Right", Right, W),
                k(shots, "Ganzer Bildschirm", "Whole Screen", Print, WinModifiers.None),
                k(shots, "Ganzer Bildschirm speichern", "Save Whole Screen", Print, W),
                s(shots, "Ausschnitt", "Snipping Tool", 's', W | S),
            };
        }
    }

    public static IReadOnlyList<KnownShortcut> All => Live.Concat(Windows).ToList();

    /// <summary>The app's own shortcuts in the same form, for the keyboard overview (panel keys left out: they only
    /// work while the panel is open). Combos with no Windows counterpart are left out.</summary>
    public static IReadOnlyList<KnownShortcut> Hyne(LauncherConfig config)
    {
        const string section = "HYNE ASM";
        var list = new List<KnownShortcut>();
        void Add(string title, KeyCombo combo)
        {
            if (KeyTranslation.ToWindows(combo) is { } w)
                list.Add(Vk(KnownShortcut.AppKind.Hyne, section, title, w.vk, w.mods));
        }
        if (config.Shortcuts.CloseFocused is { } focused) Add(Loc.T("Fokussiertes Plugin-Fenster schließen", "Close focused plugin window"), focused);
        foreach (var c in config.Shortcuts.CloseAll) Add(Loc.T("Alle Plugin-Fenster schließen", "Close all plugin windows"), c);
        foreach (var c in config.Shortcuts.QuickSearch) Add(Loc.T("Schnellsuche öffnen", "Open quick search"), c);
        foreach (var i in config.ItemShortcuts) Add(Loc.T($"„{i.Name}“ einfügen", $"Insert “{i.Name}”"), i.Combo);
        return list;
    }

    public static IReadOnlyList<KnownShortcut> Conflicts(KeyCombo combo, Func<char, ushort?>? vkForChar = null) =>
        All.Where(k => k.Matches(combo, vkForChar)).ToList();
}
