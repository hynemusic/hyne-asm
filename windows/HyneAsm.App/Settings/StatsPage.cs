using System.Collections.Generic;
using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Page "Stats" (like the Mac's): tiles, the most inserted as bars coloured by kind, the split by kind,
/// and every count (remove single ones); export / import / reset.</summary>
sealed class StatsPage : Page
{
    int top = 10;

    public StatsPage(AppModel model, SettingsWindow window) : base(model, window) { }

    static Color KindColor(UsageKind k) => k switch
    {
        UsageKind.Plugins => Color.FromRgb(0xFF, 0x8C, 0x1A),
        UsageKind.Live => Color.FromRgb(0xF5, 0x9E, 0x3A),
        UsageKind.MaxForLive => Color.FromRgb(0x3C, 0xC7, 0xB0),
        UsageKind.Presets => Color.FromRgb(0xF5, 0xC0, 0x4A),
        _ => Color.FromRgb(0xA7, 0x7B, 0xF3),
    };

    Dictionary<string, string> entryColors = new();

    /// <summary>The colour the user gave the entry (or its plugin) in the menu, else the colour rules'.</summary>
    Color? LabelOf(UsageStat s) => entryColors.TryGetValue(s.Key, out var id) ? Theme.LabelColor(id) : Theme.LabelColor(s.ColorID);

    void CollectEntryColors()
    {
        entryColors = new(StringComparer.OrdinalIgnoreCase);
        var index = Model.SearchIndex;
        foreach (var e in Model.Config.Categories.SelectMany(c => c.Entries.SelectMany(x => x.Children ?? new List<Entry> { x })))
        {
            if (e.ColorID is not { } color) continue;
            string? key = e.Action != null ? "action|" + Text.Lower(e.Title)
                : e.Chain != null ? "chain|" + Text.Lower(e.Title)
                : index.Resolver.Resolve(e) is { } item && index.UsageKey.TryGetValue(item.Uri, out var k) ? k : null;
            if (key != null) entryColors.TryAdd(key, color);
        }
    }

    public override UIElement Build()
    {
        CollectEntryColors();
        var counts = Model.Usage.Counts;
        var summary = UsageStats.Summarize(counts, Model.Catalog.Items, Model.Config);
        var panel = new StackPanel();
        panel.Children.Add(UI.PageHeader(Loc.T("Statistik", "Stats"),
            Loc.T("Was du am meisten einfügst. Diese Zahlen bestimmen auch die Reihenfolge deiner Suchergebnisse.", "What you insert most. These numbers also rank your search results."),
            UI.Button(Loc.T("Importieren …", "Import …"), Import, ""),
            UI.Button(Loc.T("Exportieren …", "Export …"), Export, ""),
            UI.Button(Loc.T("Zurücksetzen …", "Reset …"), Reset, "")));
        if (Model.Usage.IsReadOnly)
            panel.Children.Add(UI.Caption(Loc.T("usage.json konnte nicht gelesen werden (gesperrt?) – Zählungen werden gerade nicht gespeichert.", "usage.json couldn't be read (locked?) – counts aren't being saved right now.")));

        // Tiles
        var tiles = new Grid { Margin = new Thickness(0, 0, 0, 18) };
        for (var i = 0; i < 4; i++) tiles.ColumnDefinitions.Add(new ColumnDefinition());
        var tileData = new (string Glyph, string Title, string Value, bool Small)[]
        {
            ("", Loc.T("Eingefügt", "Inserts"), Loc.Number(summary.Total), false),
            ("", Loc.T("Verschiedene", "Different"), Loc.Number(summary.Stats.Count), false),
            ("", Loc.T("Am meisten", "Most used"), summary.Stats.FirstOrDefault()?.Name ?? "–", true),
            ("", Loc.T("Anteil Top 10", "Top 10 share"), summary.Total == 0 ? "–" : $"{summary.TopShare(10) * 100:0} %", false),
        };
        for (var i = 0; i < 4; i++)
        {
            var (glyph, title, value, small) = tileData[i];
            var head = new StackPanel { Orientation = Orientation.Horizontal };
            head.Children.Add(UI.Icon(glyph, 13, Theme.Accent));
            var t = UI.Text(title, 13, Theme.TextSecondary, FontWeights.SemiBold);
            t.Margin = new Thickness(8, 0, 0, 0);
            head.Children.Add(t);
            var v = UI.Text(value, small ? 19 : 30, weight: FontWeights.Bold);
            v.Margin = new Thickness(0, small ? 12 : 6, 0, 0);
            var tile = new Border
            {
                Background = UI.Raised, CornerRadius = new CornerRadius(Theme.Radius(12)), BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1),
                Padding = new Thickness(16, 14, 16, 14), Margin = new Thickness(i == 0 ? 0 : 7, 0, i == 3 ? 0 : 7, 0),
                Child = new StackPanel { Children = { head, v } },
            };
            Grid.SetColumn(tile, i);
            tiles.Children.Add(tile);
        }
        panel.Children.Add(tiles);
        if (summary.Stats.Count == 0)
        {
            panel.Children.Add(UI.Card(UI.Row(Loc.T("Noch nichts eingefügt", "Nothing inserted yet"), Loc.T("Füg etwas über das Panel oder die Schnellsuche ein.", "Insert something from the panel or the quick search."), null)));
            return UI.PageColumn(panel);
        }

        // Most inserted
        var most = new StackPanel { Margin = new Thickness(0, 14, 0, 14) };
        var mostHead = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 0, 0, 12) };
        var seg = UI.Segmented(new[] { ("Top 10", 10), ("Top 25", 25) }, top, v => { top = v; Window.Redraw(); });
        DockPanel.SetDock(seg, Dock.Right);
        mostHead.Children.Add(seg);
        mostHead.Children.Add(UI.Text(Loc.T("Am meisten eingefügt", "Most inserted"), 13, Theme.TextSecondary, FontWeights.SemiBold));
        most.Children.Add(mostHead);
        var max = Math.Max(1, summary.Stats[0].Count);
        var rank = 0;
        foreach (var s in summary.Stats.Take(top))
        {
            rank++;
            var g = new Grid { Height = 32 };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(30) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.42, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var r = UI.Text(rank.ToString(), 12.5, Theme.TextTertiary);
            r.HorizontalAlignment = HorizontalAlignment.Center;
            g.Children.Add(r);
            var n = UI.Text(s.Name, 14.5, s.IsAvailable ? Theme.TextPrimary : Theme.TextTertiary);
            Grid.SetColumn(n, 1);
            g.Children.Add(n);
            var barLine = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            var color = LabelOf(s) ?? KindColor(s.Kind);   // the plugin's own colour, else its kind's
            var fill = s.IsAvailable ? color : Color.FromArgb(110, color.R, color.G, color.B);
            var bar = new Border { Height = 20, CornerRadius = new CornerRadius(Theme.Radius(4)), Background = Theme.B(fill), Width = Math.Max(8, 520.0 * s.Count / max), MaxWidth = 520 };
            barLine.Children.Add(bar);
            var c = UI.Text(s.Count.ToString(), 12.5, Theme.TextSecondary, FontWeights.SemiBold);
            c.Margin = new Thickness(10, 0, 0, 0);
            barLine.Children.Add(c);
            Grid.SetColumn(barLine, 2);
            g.Children.Add(barLine);
            most.Children.Add(g);
        }
        most.Children.Add(Legend(summary, withNumbers: false));
        panel.Children.Add(UI.Card(most));

        // By type
        var byType = new StackPanel { Margin = new Thickness(0, 14, 0, 14) };
        byType.Children.Add(UI.Text(Loc.T("Nach Art", "By type"), 13, Theme.TextSecondary, FontWeights.SemiBold));
        var stacked = new Grid { Height = 18, Margin = new Thickness(0, 14, 0, 12) };
        foreach (var (kind, count) in summary.ByKind.Where(k => k.Count > 0))
        {
            stacked.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(count, GridUnitType.Star) });
            var part = new Border { Background = Theme.B(KindColor(kind)), CornerRadius = new CornerRadius(Theme.Radius(4)), Margin = new Thickness(0, 0, 3, 0) };
            Grid.SetColumn(part, stacked.ColumnDefinitions.Count - 1);
            stacked.Children.Add(part);
        }
        byType.Children.Add(stacked);
        byType.Children.Add(Legend(summary, withNumbers: true));
        var typeCard = UI.Card(byType);
        typeCard.Margin = new Thickness(0, 18, 0, 0);
        panel.Children.Add(typeCard);

        // All counts
        panel.Children.Add(UI.Label(Loc.T("Alle", "All"), UI.Text(Loc.T("Ausgegraut: nicht mehr in Live gefunden", "Greyed out: no longer found in Live"), 12.5, Theme.TextSecondary)));
        rank = 0;
        panel.Children.Add(UI.Card(summary.Stats.Select(s => AllRow(s, ++rank, max, summary.Total)).ToArray()));

        if (Model.Config.ShowRarelyUsed)
        {
            var rare = RarelyUsed.Entries(Model.Config, Model.SearchIndex, counts);
            if (rare.Count > 0)
            {
                panel.Children.Add(UI.GroupHeader("", Loc.T("Kaum genutzt", "Rarely used"), Loc.T("Panel-Einträge, die du fast nie einfügst. Aufräumen oder behalten.", "Panel entries you hardly ever insert. Tidy up or keep them.")));
                panel.Children.Add(UI.Card(rare.Take(30).Select(r =>
                {
                    var buttons = new StackPanel { Orientation = Orientation.Horizontal };
                    buttons.Children.Add(UI.SmallButton(Loc.T("Behalten", "Keep"), () => { Model.Config.KeepEntry(r.Entry.Id); Changed(); }));
                    buttons.Children.Add(UI.IconButton("", () => { Model.Config.RemoveEntry(r.Entry.Id, r.CategoryID); Changed(); }, Loc.T("Aus dem Menü entfernen", "Remove from the menu")));
                    return (UIElement)UI.Row(r.Entry.Title, r.Place + " · " + Loc.T($"{r.Count}× eingefügt", $"inserted {r.Count}×"), buttons, UI.IconTile(IconGlyphs.Glyph(r.Entry.IconID), Theme.TextSecondary));
                }).ToArray()));
            }
        }
        return UI.PageColumn(panel);
    }

    static UIElement Legend(UsageSummary summary, bool withNumbers)
    {
        var legend = new WrapPanel { Margin = new Thickness(0, 6, 0, 0) };
        var kinds = withNumbers ? summary.ByKind.Where(k => k.Count > 0).ToList() : Enum.GetValues<UsageKind>().Select(k => (Kind: k, Count: 0)).ToList();
        foreach (var (kind, count) in kinds)
        {
            var item = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 22, 4) };
            item.Children.Add(new Border { Width = 10, Height = 10, CornerRadius = new CornerRadius(withNumbers ? 5 : 2), Background = Theme.B(KindColor(kind)), VerticalAlignment = VerticalAlignment.Center });
            var t = UI.Text(kind.Title(), withNumbers ? 14 : 12.5, withNumbers ? Theme.TextPrimary : Theme.TextSecondary);
            t.Margin = new Thickness(7, 0, 0, 0);
            item.Children.Add(t);
            if (withNumbers)
            {
                var n = UI.Text($"{(summary.Total == 0 ? 0 : count * 100.0 / summary.Total):0} % · {count}", 12.5, Theme.TextTertiary);
                n.Margin = new Thickness(8, 0, 0, 0);
                item.Children.Add(n);
            }
            legend.Children.Add(item);
        }
        return legend;
    }

    UIElement AllRow(UsageStat s, int rank, int max, int total)
    {
        var grid = new Grid { MinHeight = 60, Opacity = s.IsAvailable ? 1 : 0.5 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(34) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var r = UI.Text(rank.ToString(), 12.5, Theme.TextTertiary);
        r.HorizontalAlignment = HorizontalAlignment.Center;
        grid.Children.Add(r);
        var label = LabelOf(s);
        var tile = UI.IconTile(IconGlyphs.Glyph(s.IconID), label is { } lc ? Theme.B(lc) : Theme.Accent);
        tile.Margin = new Thickness(6, 0, 14, 0);
        Grid.SetColumn(tile, 1);
        grid.Children.Add(tile);
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(UI.Text(s.Name, 14.5, weight: FontWeights.SemiBold));
        text.Children.Add(UI.Text(s.Kind.Title(), 12.5, Theme.TextTertiary));
        Grid.SetColumn(text, 2);
        grid.Children.Add(text);
        var right = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var track = new Grid { Width = 210, Height = 6, VerticalAlignment = VerticalAlignment.Center };
        track.Children.Add(new Border { Background = Theme.Ink(0.08), CornerRadius = new CornerRadius(3) });
        track.Children.Add(new Border { Background = Theme.B(LabelOf(s) ?? KindColor(s.Kind)), CornerRadius = new CornerRadius(3), HorizontalAlignment = HorizontalAlignment.Left, Width = 210.0 * s.Count / max });
        right.Children.Add(track);
        var pct = UI.Text($"{(total == 0 ? 0 : s.Count * 100.0 / total):0} %", 12.5, Theme.TextTertiary);
        pct.Width = 62; pct.TextAlignment = TextAlignment.Right;
        right.Children.Add(pct);
        var n = UI.Text(s.Count.ToString(), 15, weight: FontWeights.Bold);
        n.Width = 52; n.TextAlignment = TextAlignment.Right;
        right.Children.Add(n);
        var remove = UI.IconButton("", () => { Model.Usage.Remove(s.Key); Window.Redraw(); }, Loc.T("Zählung entfernen", "Remove this count"));
        remove.Margin = new Thickness(8, 0, 0, 0);
        right.Children.Add(remove);
        Grid.SetColumn(right, 3);
        grid.Children.Add(right);
        return grid;
    }

    void Export()
    {
        var dialog = new Microsoft.Win32.SaveFileDialog { Filter = "HYNE ASM stats (*.hmlusage)|*.hmlusage", FileName = "HYNE ASM stats." + UsageExport.FileExtension };
        if (dialog.ShowDialog(Window) != true) return;
        try { File.WriteAllBytes(dialog.FileName, new UsageExport(Model.Usage.Counts).Data()); }
        catch (Exception e) { UI.Tell(Window, "HYNE ASM", e.Message); }
    }

    void Import()
    {
        var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "HYNE ASM stats (*.hmlusage)|*.hmlusage|usage.json|*.json" };
        if (dialog.ShowDialog(Window) != true) return;
        try
        {
            Model.Usage.Merge(UsageExport.Read(File.ReadAllBytes(dialog.FileName)));
            Window.Redraw();
            Model.Hud.Show(Loc.T("Zählungen übernommen", "Counts imported"));
        }
        catch (Exception) { UI.Tell(Window, "HYNE ASM", Loc.T("Das ist keine Statistik-Datei.", "That isn't a stats file.")); }
    }

    /// <summary>Before counts are thrown away: a copy next to usage.json ("usage-backup-&lt;date&gt;.hmlusage").</summary>
    void Reset()
    {
        if (!UI.Confirm(Window, Loc.T("Alle Zählungen zurücksetzen?", "Reset all counts?"), Loc.T("Vorher wird eine Kopie neben usage.json gesichert.", "A copy is saved next to usage.json first."), Loc.T("Zurücksetzen", "Reset"))) return;
        try
        {
            var backup = Path.Combine(Path.GetDirectoryName(UsageStore.DefaultPath)!, $"usage-backup-{DateTime.Now:yyyy-MM-dd-HHmm}.{UsageExport.FileExtension}");
            File.WriteAllBytes(backup, new UsageExport(Model.Usage.Counts).Data());
        }
        catch (Exception) { /* reset anyway: the user confirmed */ }
        Model.Usage.Reset();
        Window.Redraw();
    }
}
