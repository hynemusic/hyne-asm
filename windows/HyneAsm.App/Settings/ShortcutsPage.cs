using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Shortcut text and recording (Windows keys; stored in the Mac format).</summary>
static class Keys
{
    public static string Describe(KeyCombo? combo)
    {
        if (combo == null) return Loc.T("aus", "off");
        return KeyTranslation.ToWindows(combo) is { } w ? Describe(w.vk, w.mods) : "?";
    }

    public static string Describe(ushort vk, WinModifiers mods)
    {
        var parts = new List<string>();
        if (mods.HasFlag(WinModifiers.Ctrl)) parts.Add(Loc.T("Strg", "Ctrl"));
        if (mods.HasFlag(WinModifiers.Alt)) parts.Add("Alt");
        if (mods.HasFlag(WinModifiers.Shift)) parts.Add("⇧");
        if (mods.HasFlag(WinModifiers.Win)) parts.Add("Win");
        parts.Add(KeyName(vk));
        return string.Join("+", parts);
    }

    public static string KeyName(ushort vk) => vk switch
    {
        0x20 => Loc.T("Leertaste", "Space"), 0x0D => "↵", 0x1B => "Esc", 0x09 => "⇥", 0x08 => "⌫", 0x2E => Loc.T("Entf", "Del"),
        0x25 => "←", 0x26 => "↑", 0x27 => "→", 0x28 => "↓", 0x24 => "Pos1", 0x23 => Loc.T("Ende", "End"), 0x21 => "Bild↑", 0x22 => "Bild↓",
        >= 0x30 and <= 0x39 or >= 0x41 and <= 0x5A => ((char)vk).ToString(),
        >= 0x70 and <= 0x87 => "F" + (vk - 0x6F),
        0xBA => ";", 0xBB => "=", 0xBC => ",", 0xBD => "-", 0xBE => ".", 0xBF => "/", 0xC0 => "`", 0xDB => "[", 0xDC => "\\", 0xDD => "]", 0xDE => "'",
        _ => KeyInterop.KeyFromVirtualKey(vk).ToString(),
    };

    /// <summary>The combo a WPF key event means, or null for lone modifiers.</summary>
    public static KeyCombo? From(KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin) return null;
        var m = WinModifiers.None;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) m |= WinModifiers.Ctrl;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Alt)) m |= WinModifiers.Alt;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) m |= WinModifiers.Shift;
        if (Keyboard.IsKeyDown(Key.LWin) || Keyboard.IsKeyDown(Key.RWin)) m |= WinModifiers.Win;
        return KeyTranslation.FromWindows((ushort)KeyInterop.VirtualKeyFromKey(key), m);
    }

    /// <summary>Live and Windows shortcuts the combo would take away.</summary>
    public static IReadOnlyList<KnownShortcut> Conflicts(KeyCombo combo) => KnownShortcuts.Conflicts(combo);

    public static string? ConflictText(KeyCombo combo)
    {
        var hits = Conflicts(combo);
        return hits.Count == 0 ? null : Loc.T("Auch belegt: ", "Also used: ") + string.Join(", ", hits.Take(3).Select(h => $"{h.Title} ({AppName(h.App)})"));
    }

    public static string AppName(KnownShortcut.AppKind app) => app switch
    {
        KnownShortcut.AppKind.Live => "Live", KnownShortcut.AppKind.Windows => "Windows", _ => "HYNE ASM",
    };

    /// <summary>A key cap; click, then press the new combination (Esc cancels).</summary>
    public static Border Cap(KeyCombo? combo, Action<KeyCombo> recorded, string? emptyText = null)
    {
        string Shown() => combo == null ? emptyText ?? "+" : Describe(combo);
        var label = UI.Text(Shown(), 13, Theme.TextPrimary, FontWeights.Bold);
        label.HorizontalAlignment = HorizontalAlignment.Center;
        var cap = new Border
        {
            Child = label, Padding = new Thickness(combo == null ? 9 : 14, 5, combo == null ? 9 : 14, 5), MinWidth = combo == null ? 32 : 82,
            CornerRadius = new CornerRadius(Theme.Radius(6)), Background = UI.Canvas, Cursor = Cursors.Hand, Focusable = true, FocusVisualStyle = null,
            VerticalAlignment = VerticalAlignment.Center, BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1),
            ToolTip = Loc.T("Klicken, dann die Kombination drücken. Esc bricht ab.", "Click, then press the combination. Esc cancels."),
        };
        var recording = false;
        void Stop() { recording = false; cap.BorderBrush = Theme.Stroke; cap.Effect = null; label.Text = Shown(); }
        cap.MouseLeftButtonUp += (_, e) =>
        {
            e.Handled = true;
            if (recording) { Stop(); return; }
            recording = true;
            UI.Glow(cap);
            label.Text = Loc.T("Tasten drücken …", "Press keys …");
            cap.Focus();
            Keyboard.Focus(cap);
        };
        cap.LostKeyboardFocus += (_, _) => { if (recording) Stop(); };
        cap.PreviewKeyDown += (_, e) =>
        {
            if (!recording) return;
            e.Handled = true;
            var key = e.Key == Key.System ? e.SystemKey : e.Key;
            if (key == Key.Escape && Keyboard.Modifiers == ModifierKeys.None) { Stop(); return; }
            if (From(e) is { } c) { recording = false; recorded(c); }
        };
        return cap;
    }
}

/// <summary>Page "Shortcuts" (like the Mac's): plugin shortcuts, plugin windows, quick search, profiles, the keys in the
/// panel; each with key caps (× removes, + adds), a warning when Live or Windows already uses a combination,
/// "Restore Defaults", and the overview of Live's and Windows' shortcuts.</summary>
sealed class ShortcutsPage : Page
{
    public ShortcutsPage(AppModel model, SettingsWindow window) : base(model, window) { }

    public override UIElement Build()
    {
        var c = Model.Config;
        var s = c.Shortcuts;
        var d = WindowsDefaults.Shortcuts;
        var panel = new StackPanel();
        panel.Children.Add(UI.PageHeader(Loc.T("Tastenkürzel", "Shortcuts"),
            Loc.T("Klick auf ein Kürzel und drück die neue Kombination. Alle Kürzel wirken nur, solange Live vorne ist.",
                  "Click a shortcut and press the new combination. All shortcuts only work while Live is in front."),
            UI.Button(Loc.T("Ableton- & Windows-Kürzel", "Ableton & Windows Shortcuts"), () => new ShortcutOverview(Model) { Owner = Window }.ShowDialog(), "")));

        // Plugin shortcuts
        panel.Children.Add(UI.GroupHeader("", Loc.T("Plugin-Kürzel", "Plugin Shortcuts"),
            Loc.T("Fügt ein Plugin, Rack oder Preset direkt in die ausgewählte Spur ein, ganz ohne Panel. Kürzel brauchen Strg, Alt oder Win.",
                  "Inserts a plugin, rack or preset straight into the selected track, no panel needed. Shortcuts need Ctrl, Alt or Win."),
            UI.Link(Loc.T("Kürzel hinzufügen …", "Add Shortcut …"), AddPluginShortcut, accent: false)));
        if (c.ItemShortcuts.Count == 0)
            panel.Children.Add(UI.Card(UI.Row(Loc.T("Noch keine. Klick oben auf „Kürzel hinzufügen …“ oder rechtsklick ein Plugin in der Bibliothek → „Tastenkürzel …“.",
                                                    "None yet. Click “Add Shortcut …” above, or right-click a plugin in the Library and choose “Shortcut …”."), null, null)));
        else
            panel.Children.Add(UI.Card(c.ItemShortcuts.ToList().Select(sc =>
            {
                var item = new PluginItem(sc.Uri, sc.Name, sc.Source, sc.Path);
                return Line(sc.Name, new List<KeyCombo> { sc.Combo }, list => c.SetItemShortcut(list.FirstOrDefault(), item), max: 1, detail: PluginGrouping.FormatLabel(item));
            }).ToArray()));

        // Plugin windows
        panel.Children.Add(UI.GroupHeader("", Loc.T("Plugin-Fenster", "Plugin Windows"), Loc.T("Kürzel brauchen Strg, Alt oder Win.", "Shortcuts need Ctrl, Alt or Win."),
            UI.Link(Loc.T("Standard wiederherstellen", "Restore Defaults"), () => { s.CloseFocused = d.CloseFocused; s.CloseAll = d.CloseAll.ToList(); Changed(); }, accent: false)));
        panel.Children.Add(UI.Card(
            Line(Loc.T("Fokussiertes Plugin-Fenster schließen", "Close focused plugin window"), s.CloseFocused is { } f ? new List<KeyCombo> { f } : new(), l => s.CloseFocused = l.FirstOrDefault(), max: 1),
            Line(Loc.T("Alle Plugin-Fenster schließen", "Close all plugin windows"), s.CloseAll, l => s.CloseAll = l)));

        // Quick search
        panel.Children.Add(UI.GroupHeader("", Loc.T("Schnellsuche", "Quick Search"),
            Loc.T("Öffnet das Suchfenster in der Bildschirmmitte. Windows nutzt Win+Leertaste zum Umschalten der Eingabesprache.",
                  "Opens the search window in the middle of the screen. Windows uses Win+Space for switching input languages."),
            UI.Link(Loc.T("Standard wiederherstellen", "Restore Defaults"), () => { s.QuickSearch = d.QuickSearch.ToList(); Changed(); }, accent: false)));
        panel.Children.Add(UI.Card(Line(Loc.T("Schnellsuche öffnen", "Open quick search"), s.QuickSearch, l => s.QuickSearch = l)));

        // Profiles
        panel.Children.Add(UI.GroupHeader("", Loc.T("Profile", "Profiles"), Loc.T("Wechselt zum nächsten Profil (sein eigenes Menü). Standardmäßig aus.", "Switches to the next profile (its own menu). Off by default."),
            UI.Link(Loc.T("Standard wiederherstellen", "Restore Defaults"), () => { s.NextProfile = new(); Changed(); }, accent: false)));
        panel.Children.Add(UI.Card(Line(Loc.T("Nächstes Profil", "Next profile"), s.NextProfile, l => s.NextProfile = l)));

        // In the panel
        panel.Children.Add(UI.GroupHeader("", Loc.T("Im Panel", "In the Panel"),
            Loc.T("Immer an: 1–9 fügen das Pad ein, Tippen sucht, ⌫ löscht in der Suche, Strg+A markiert alles, ⇧ hält das Panel offen.",
                  "Always on: 1–9 insert that pad, typing searches, ⌫ deletes in the search, Ctrl+A selects all, Shift keeps the panel open."),
            UI.Link(Loc.T("Standard wiederherstellen", "Restore Defaults"), () => { c.PanelKeys = PanelKeyBindings.Default; Changed(); }, accent: false)));
        panel.Children.Add(UI.Card(Enum.GetValues<PanelKeyAction>().Select(a => Line(a.Label(), c.PanelKeys[a], l => c.PanelKeys[a] = l, conflicts: false)).ToArray()));
        return UI.PageColumn(panel);
    }

    /// <summary>A shortcut row: label (with ⚠ when Live or Windows uses a combo), key caps with ×, then +.</summary>
    UIElement Line(string title, List<KeyCombo> combos, Action<List<KeyCombo>> save, int max = 8, string? detail = null, bool conflicts = true)
    {
        void Save(List<KeyCombo> list) { save(list); Changed(); }
        var caps = new StackPanel { Orientation = Orientation.Horizontal };
        if (combos.Count == 0) { var off = UI.Text(Loc.T("aus", "off"), 13, Theme.TextTertiary); off.Margin = new Thickness(0, 0, 10, 0); caps.Children.Add(off); }
        for (var i = 0; i < combos.Count; i++)
        {
            var index = i;
            caps.Children.Add(Keys.Cap(combos[i], v => { var l = combos.ToList(); l[index] = v; Save(l); }));
            var x = UI.IconButton("", () => { var l = combos.ToList(); l.RemoveAt(index); Save(l); }, Loc.T("Entfernen", "Remove"), Theme.TextTertiary);
            x.Padding = new Thickness(7, 4, 9, 4);
            caps.Children.Add(x);
        }
        if (combos.Count < max) caps.Children.Add(Keys.Cap(null, v => Save(max == 1 ? new List<KeyCombo> { v } : combos.Append(v).ToList())));
        var label = new StackPanel { Orientation = Orientation.Horizontal };
        label.Children.Add(UI.Text(title, 14.5, weight: FontWeights.Medium));
        var warnings = conflicts ? combos.Select(Keys.ConflictText).Where(t => t != null).ToList() : new();
        if (warnings.Count > 0)
        {
            var warn = UI.Icon("", 13, Theme.B(Color.FromRgb(0xF5, 0xC0, 0x4A)));
            warn.Margin = new Thickness(10, 0, 0, 0);
            warn.ToolTip = string.Join("\n", warnings);
            label.Children.Add(warn);
        }
        var grid = new Grid { MinHeight = 60 };
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        left.Children.Add(label);
        if (detail != null) left.Children.Add(UI.Text(detail, 12, Theme.TextTertiary));
        grid.Children.Add(left);
        Grid.SetColumn(caps, 1);
        caps.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(caps);
        return grid;
    }

    /// <summary>Pick a plugin by name, then record its shortcut.</summary>
    void AddPluginShortcut()
    {
        if (Model.Catalog.Items.Count == 0) { UI.Tell(Window, "HYNE ASM", Loc.T("Erst mit Live verbinden: die Plugin-Liste kommt aus Live.", "Connect to Live first: the plugin list comes from Live.")); return; }
        var search = UI.TextBox("", Loc.T("Plugin, Gerät oder Preset suchen", "Search a plugin, device or preset"));
        search.Width = 420;
        var results = new StackPanel { Margin = new Thickness(0, 10, 0, 0), MinHeight = 300 };
        var dialog = new Window
        {
            Owner = Window, Title = Loc.T("Kürzel hinzufügen", "Add Shortcut"), SizeToContent = SizeToContent.WidthAndHeight, ResizeMode = ResizeMode.NoResize,
            WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = UI.Surface, ShowInTaskbar = false, FontFamily = Theme.Font,
        };
        void Fill()
        {
            results.Children.Clear();
            var q = search.Text.Trim();
            if (q.Length == 0) return;
            foreach (var r in new QuickSearch(Model.Config, Model.SearchIndex, Model.Usage.Counts).Results(q).Where(r => r.Row.Action == null && r.Row.Chain == null && r.Row.FolderID == null && r.Row.Uri.Length > 0).Take(10))
            {
                var row = r.Row;
                var line = UI.Row(row.Title, r.Place ?? PluginGrouping.FormatLabel(new PluginItem(row.Uri, row.Name, row.Source, row.Path)), null, Theme.Icon(row.IconID, 15, Theme.TextSecondary), 44);
                var b = new Border { Child = line, Padding = new Thickness(10, 0, 10, 0), CornerRadius = new CornerRadius(Theme.Radius(7)), Cursor = Cursors.Hand, Background = Brushes.Transparent };
                b.MouseEnter += (_, _) => b.Background = UI.Hover;
                b.MouseLeave += (_, _) => b.Background = Brushes.Transparent;
                b.MouseLeftButtonUp += (_, _) => { dialog.Close(); ShortcutDialog.Show(Window, Model, new PluginItem(row.Uri, row.Name, row.Source, row.Path), row.Title); };
                results.Children.Add(b);
            }
        }
        search.TextChanged += (_, _) => Fill();
        var panel = new StackPanel { Margin = new Thickness(22) };
        panel.Children.Add(UI.Text(Loc.T("Für welches Plugin?", "For which plugin?"), 16, weight: FontWeights.Bold));
        search.Margin = new Thickness(0, 12, 0, 0);
        panel.Children.Add(search);
        panel.Children.Add(results);
        dialog.Content = panel;
        dialog.Loaded += (_, _) => search.Focus();
        dialog.ShowDialog();
    }
}

/// <summary>Sets the shortcut that inserts one plugin straight away.</summary>
static class ShortcutDialog
{
    public static void Show(Window owner, AppModel model, PluginItem item, string title)
    {
        var dialog = new Window
        {
            Owner = owner, Title = "HYNE ASM", SizeToContent = SizeToContent.WidthAndHeight, ResizeMode = ResizeMode.NoResize,
            WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = UI.Surface, ShowInTaskbar = false, FontFamily = Theme.Font,
        };
        var panel = new StackPanel { Margin = new Thickness(24), Width = 420 };
        void Fill()
        {
            panel.Children.Clear();
            panel.Children.Add(UI.Text(Loc.T("Tastenkürzel für ", "Shortcut for ") + title, 16, weight: FontWeights.Bold));
            var cap = UI.Caption(Loc.T("Fügt es sofort in die ausgewählte Spur ein, solange Live vorne ist.", "Inserts it into the selected track right away while Live is in front."));
            cap.Margin = new Thickness(0, 6, 0, 14);
            panel.Children.Add(cap);
            var current = model.Config.ItemShortcutFor(item)?.Combo;
            var line = new StackPanel { Orientation = Orientation.Horizontal };
            line.Children.Add(Keys.Cap(current, v =>
            {
                if (model.Config.ShortcutOwner(v, model.Config.ItemShortcutFor(item)?.Id) is { } other)
                {
                    UI.Tell(dialog, Loc.T("Schon belegt", "Already in use"), Loc.T($"{Keys.Describe(v)} gehört schon zu „{other}“.", $"{Keys.Describe(v)} already belongs to “{other}”."));
                    return;
                }
                model.Config.SetItemShortcut(v, item);
                model.ConfigChanged();
                Fill();
            }, Loc.T("Kürzel aufnehmen", "Record shortcut")));
            if (current != null)
                line.Children.Add(UI.IconButton("", () => { model.Config.SetItemShortcut(null, item); model.ConfigChanged(); Fill(); }, Loc.T("Entfernen", "Remove")));
            panel.Children.Add(line);
            if (current != null && Keys.ConflictText(current) is { } warn) { var w = UI.Caption("⚠ " + warn); w.Margin = new Thickness(0, 10, 0, 0); panel.Children.Add(w); }
            var close = UI.Primary(Loc.T("Fertig", "Done"), () => dialog.Close());
            close.HorizontalAlignment = HorizontalAlignment.Right;
            close.Margin = new Thickness(0, 18, 0, 0);
            panel.Children.Add(close);
        }
        Fill();
        dialog.Content = panel;
        dialog.ShowDialog();
    }
}
