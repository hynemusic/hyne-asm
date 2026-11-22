using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Page "Shortcuts": plugin windows, quick search, profiles, the keys inside the panel, and plugin shortcuts.</summary>
sealed class ShortcutsPage : Page
{
    public ShortcutsPage(AppModel model, SettingsWindow window) : base(model, window) { }

    public override UIElement Build()
    {
        var c = Model.Config;
        var s = c.Shortcuts;
        var panel = new StackPanel { Margin = new Thickness(28, 22, 28, 22), MaxWidth = 820, HorizontalAlignment = HorizontalAlignment.Left };
        panel.Children.Add(UI.Title(Loc.T("Tastenkürzel", "Shortcuts")));
        panel.Children.Add(UI.Caption(Loc.T("Gelten nur, solange Live vorne ist. Klick auf ein Kürzel und drück die neue Kombination; Rücktaste schaltet es aus.",
                                            "Only active while Live is in front. Click a shortcut and press the new combination; Backspace turns it off.")));

        panel.Children.Add(UI.Section(Loc.T("Plugin-Fenster", "Plugin windows")));
        panel.Children.Add(UI.Card(Stack(
            Single(Loc.T("Fokussiertes Plugin-Fenster schließen", "Close the focused plugin window"),
                   Loc.T("Lives Hauptfenster wird nie geschlossen; dort geht die Taste an Live.", "Live's main window is never closed; there the key goes to Live."),
                   s.CloseFocused, v => s.CloseFocused = v),
            List(Loc.T("Alle Plugin-Fenster schließen", "Close all plugin windows"), null, s.CloseAll))));

        panel.Children.Add(UI.Section(Loc.T("Suche & Profile", "Search & profiles")));
        panel.Children.Add(UI.Card(Stack(
            List(Loc.T("Schnellsuche öffnen", "Open the quick search"), null, s.QuickSearch),
            List(Loc.T("Nächstes Profil", "Next profile"), null, s.NextProfile))));

        panel.Children.Add(UI.Section(Loc.T("Im offenen Panel", "Inside the open panel")));
        var keys = new List<UIElement>();
        foreach (var action in Enum.GetValues<PanelKeyAction>())
        {
            var a = action;
            keys.Add(List(a.Label(), null, c.PanelKeys[a], replace: l => c.PanelKeys[a] = l));
        }
        keys.Add(UI.Caption(Loc.T("Fest: 1–9 wählen, Tippen sucht, Rücktaste löscht, Strg+A markiert alles, Umschalt hält das Panel offen.",
                                  "Fixed: 1–9 pick, typing searches, Backspace deletes, Ctrl+A selects all, Shift keeps the panel open.")));
        panel.Children.Add(UI.Card(Stack(keys.ToArray())));

        panel.Children.Add(UI.Section(Loc.T("Plugin-Kürzel", "Plugin shortcuts")));
        var items = new List<UIElement>();
        foreach (var sc in c.ItemShortcuts.ToList())
        {
            var item = new PluginItem(sc.Uri, sc.Name, sc.Source, sc.Path);
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(Keys.Recorder(sc.Combo, v => { c.SetItemShortcut(v, item); Changed(); }));
            row.Children.Add(UI.IconButton("", () => { c.SetItemShortcut(null, item); Changed(); }, Loc.T("Entfernen", "Remove")));
            items.Add(UI.Row(sc.Name, PluginGrouping.FormatLabel(item), row));
        }
        if (items.Count == 0)
            items.Add(UI.Caption(Loc.T("Noch keine. In der Bibliothek: Rechtsklick auf einen Eintrag → Tastenkürzel.", "None yet. In the Library: right-click an entry → Shortcut.")));
        panel.Children.Add(UI.Card(Stack(items.ToArray())));
        return UI.Scroll(panel);
    }

    static StackPanel Stack(params UIElement[] children)
    {
        var s = new StackPanel();
        foreach (var c in children) s.Children.Add(c);
        return s;
    }

    UIElement Single(string title, string? detail, KeyCombo? combo, Action<KeyCombo?> set)
    {
        var box = new StackPanel { HorizontalAlignment = HorizontalAlignment.Right };
        box.Children.Add(Keys.Recorder(combo, v => { set(v); Changed(); }));
        if (combo != null && Keys.ConflictText(combo) is { } warn) box.Children.Add(Warning(warn));
        return UI.Row(title, detail, box);
    }

    /// <summary>A shortcut that can have several combos: one recorder each, plus "+".</summary>
    UIElement List(string title, string? detail, List<KeyCombo> combos, Action<List<KeyCombo>>? replace = null)
    {
        var box = new StackPanel { HorizontalAlignment = HorizontalAlignment.Right };
        var line = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Right };
        void Save(List<KeyCombo> list) { if (replace != null) replace(list); else { combos.Clear(); combos.AddRange(list); } Changed(); }
        for (var i = 0; i < combos.Count; i++)
        {
            var index = i;
            var r = (FrameworkElement)Keys.Recorder(combos[i], v =>
            {
                var list = combos.ToList();
                if (v == null) list.RemoveAt(index); else list[index] = v;
                Save(list);
            });
            r.Margin = new Thickness(0, 0, 6, 0);
            line.Children.Add(r);
        }
        var add = (FrameworkElement)Keys.Recorder(null, v => { if (v != null) Save(combos.Append(v).ToList()); }, allowClear: false, emptyText: "+");
        add.MinWidth = 40;
        line.Children.Add(add);
        box.Children.Add(line);
        foreach (var combo in combos)
            if (Keys.ConflictText(combo) is { } warn) box.Children.Add(Warning(warn));
        return UI.Row(title, detail, box);
    }

    static UIElement Warning(string text)
    {
        var t = UI.Text(text, 11, Theme.B(System.Windows.Media.Color.FromRgb(0xFF, 0xBF, 0x4D)), wrap: true);
        t.MaxWidth = 360;
        t.TextAlignment = TextAlignment.Right;
        t.Margin = new Thickness(0, 4, 0, 0);
        return t;
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
        var panel = new StackPanel { Margin = new Thickness(22), Width = 380 };
        void Fill()
        {
            panel.Children.Clear();
            panel.Children.Add(UI.Text(Loc.T("Tastenkürzel für ", "Shortcut for ") + title, 14, weight: FontWeights.SemiBold));
            panel.Children.Add(UI.Caption(Loc.T("Fügt es sofort in die ausgewählte Spur ein, solange Live vorne ist.", "Inserts it into the selected track right away while Live is in front.")));
            var current = model.Config.ItemShortcutFor(item)?.Combo;
            var rec = (FrameworkElement)Keys.Recorder(current, v =>
            {
                if (v != null && model.Config.ShortcutOwner(v, model.Config.ItemShortcutFor(item)?.Id) is { } owner2)
                {
                    MessageBox.Show(dialog, Loc.T($"Schon belegt von „{owner2}“.", $"Already used by “{owner2}”."), "HYNE ASM");
                    return;
                }
                model.Config.SetItemShortcut(v, item);
                model.ConfigChanged();
                Fill();
            });
            rec.Margin = new Thickness(0, 12, 0, 6);
            rec.HorizontalAlignment = HorizontalAlignment.Left;
            panel.Children.Add(rec);
            if (current != null && Keys.ConflictText(current) is { } warn) panel.Children.Add(UI.Caption(warn));
            var close = UI.Button(Loc.T("Fertig", "Done"), () => dialog.Close(), primary: true);
            close.HorizontalAlignment = HorizontalAlignment.Right;
            close.Margin = new Thickness(0, 12, 0, 0);
            panel.Children.Add(close);
        }
        Fill();
        dialog.Content = panel;
        dialog.ShowDialog();
    }
}
