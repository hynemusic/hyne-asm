using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Page "Stats": what gets inserted most, the rarely used entries, and export / import / reset of the counts
/// (they rank search results, so they're worth keeping).</summary>
sealed class StatsPage : Page
{
    public StatsPage(AppModel model, SettingsWindow window) : base(model, window) { }

    public override UIElement Build()
    {
        var counts = Model.Usage.Counts;
        var summary = UsageStats.Summarize(counts, Model.Catalog.Items, Model.Config);
        var panel = new StackPanel { Margin = new Thickness(28, 22, 28, 22), MaxWidth = 820, HorizontalAlignment = HorizontalAlignment.Left };
        var head = new DockPanel { LastChildFill = true };
        var tools = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top };
        tools.Children.Add(UI.Button(Loc.T("Exportieren …", "Export …"), Export, icon: ""));
        tools.Children.Add(UI.Button(Loc.T("Importieren …", "Import …"), Import, icon: ""));
        tools.Children.Add(UI.Button(Loc.T("Zurücksetzen …", "Reset …"), Reset, icon: ""));
        DockPanel.SetDock(tools, Dock.Right);
        head.Children.Add(tools);
        head.Children.Add(UI.Title(Loc.T("Statistik", "Stats")));
        panel.Children.Add(head);
        panel.Children.Add(UI.Caption(summary.Total == 0
            ? Loc.T("Noch nichts eingefügt. Die Zählung bestimmt, was in der Suche oben steht.", "Nothing inserted yet. The counts decide what comes first in search.")
            : Loc.T($"{Loc.Number(summary.Total)} Mal eingefügt · die Top 10 machen {summary.TopShare(10):P0} aus.",
                    $"Inserted {Loc.Number(summary.Total)} times · the top 10 make up {summary.TopShare(10):P0}.")));
        if (Model.Usage.IsReadOnly)
            panel.Children.Add(UI.Caption(Loc.T("usage.json konnte nicht gelesen werden (gesperrt?) – Zählungen werden gerade nicht gespeichert.", "usage.json couldn't be read (locked?) – counts aren't being saved right now.")));

        if (summary.ByKind.Count > 0)
        {
            panel.Children.Add(UI.Section(Loc.T("Nach Art", "By kind")));
            var kinds = new WrapPanel();
            foreach (var (kind, n) in summary.ByKind)
            {
                var chip = UI.Card(new StackPanel { Children = { UI.Text(Loc.Number(n), 18, weight: FontWeights.SemiBold), UI.Text(kind.Title(), 11, Theme.TextTertiary) } });
                chip.Margin = new Thickness(0, 0, 8, 8);
                chip.MinWidth = 110;
                kinds.Children.Add(chip);
            }
            panel.Children.Add(kinds);
        }

        if (summary.Stats.Count > 0)
        {
            panel.Children.Add(UI.Section(Loc.T("Am meisten eingefügt", "Inserted most")));
            var top = new StackPanel();
            var max = Math.Max(1, summary.Stats[0].Count);
            foreach (var s in summary.Stats.Take(25))
            {
                var bar = new Grid { Width = 220, Height = 8, VerticalAlignment = VerticalAlignment.Center };
                bar.Children.Add(new Border { Background = Theme.Ink(0.08), CornerRadius = new CornerRadius(4) });
                bar.Children.Add(new Border
                {
                    Background = Theme.LabelColor(s.ColorID) is { } c ? Theme.B(c) : Theme.Accent, CornerRadius = new CornerRadius(4),
                    HorizontalAlignment = HorizontalAlignment.Left, Width = 220.0 * s.Count / max,
                });
                var right = new StackPanel { Orientation = Orientation.Horizontal };
                right.Children.Add(bar);
                var n = UI.Text(Loc.Number(s.Count), 12, Theme.TextSecondary, FontWeights.SemiBold);
                n.Width = 50; n.TextAlignment = TextAlignment.Right;
                right.Children.Add(n);
                var line = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 3, 0, 3) };
                DockPanel.SetDock(right, Dock.Right);
                line.Children.Add(right);
                var icon = Theme.Icon(s.IconID, 14, Theme.TextTertiary);
                icon.Width = 24;
                DockPanel.SetDock(icon, Dock.Left);
                line.Children.Add(icon);
                line.Children.Add(UI.Text(s.Name + (s.IsAvailable ? "" : Loc.T("  (nicht mehr in Live)", "  (no longer in Live)")), 13, s.IsAvailable ? null : Theme.TextTertiary));
                top.Children.Add(line);
            }
            panel.Children.Add(UI.Card(top));
        }

        if (Model.Config.ShowRarelyUsed)
        {
            var rare = RarelyUsed.Entries(Model.Config, Model.SearchIndex, counts);
            if (rare.Count > 0)
            {
                panel.Children.Add(UI.Section(Loc.T("Kaum genutzt", "Rarely used")));
                var list = new StackPanel();
                list.Children.Add(UI.Caption(Loc.T("Panel-Einträge, die du fast nie einfügst. Aufräumen oder behalten.", "Panel entries you hardly ever insert. Tidy up or keep them.")));
                foreach (var r in rare.Take(30))
                {
                    var buttons = new StackPanel { Orientation = Orientation.Horizontal };
                    buttons.Children.Add(UI.Button(Loc.T("Behalten", "Keep"), () => { Model.Config.KeepEntry(r.Entry.Id); Changed(); }));
                    buttons.Children.Add(UI.Button(Loc.T("Entfernen", "Remove"), () => { Model.Config.RemoveEntry(r.Entry.Id, r.CategoryID); Changed(); }));
                    list.Children.Add(UI.Row(r.Entry.Title, r.Place + " · " + Loc.T($"{r.Count}× eingefügt", $"inserted {r.Count}×"), buttons));
                }
                panel.Children.Add(UI.Card(list));
            }
        }
        return UI.Scroll(panel);
    }

    void Export()
    {
        var dialog = new Microsoft.Win32.SaveFileDialog { Filter = "HYNE ASM stats (*.hmlusage)|*.hmlusage", FileName = "HYNE ASM stats." + UsageExport.FileExtension };
        if (dialog.ShowDialog(Window) != true) return;
        try { File.WriteAllBytes(dialog.FileName, new UsageExport(Model.Usage.Counts).Data()); }
        catch (Exception e) { MessageBox.Show(Window, e.Message, "HYNE ASM"); }
    }

    void Import()
    {
        var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "HYNE ASM stats (*.hmlusage)|*.hmlusage|usage.json|*.json" };
        if (dialog.ShowDialog(Window) != true) return;
        try
        {
            Model.Usage.Merge(UsageExport.Read(File.ReadAllBytes(dialog.FileName)));
            Changed();
            Model.Hud.Show(Loc.T("Zählungen übernommen", "Counts imported"));
        }
        catch (Exception) { MessageBox.Show(Window, Loc.T("Das ist keine Statistik-Datei.", "That isn't a stats file."), "HYNE ASM"); }
    }

    /// <summary>Before counts are thrown away: a copy next to usage.json ("usage-backup-&lt;date&gt;.hmlusage").</summary>
    void Reset()
    {
        if (!UI.Confirm(Window, "HYNE ASM", Loc.T("Alle Zählungen zurücksetzen? Vorher wird eine Kopie neben usage.json gesichert.", "Reset all counts? A copy is saved next to usage.json first."))) return;
        try
        {
            var backup = Path.Combine(Path.GetDirectoryName(UsageStore.DefaultPath)!, $"usage-backup-{DateTime.Now:yyyy-MM-dd-HHmm}.{UsageExport.FileExtension}");
            File.WriteAllBytes(backup, new UsageExport(Model.Usage.Counts).Data());
        }
        catch (Exception) { /* reset anyway: the user confirmed */ }
        Model.Usage.Reset();
        Changed();
    }
}
