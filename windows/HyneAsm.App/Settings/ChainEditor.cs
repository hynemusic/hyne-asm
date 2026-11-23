using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>The chain creator (like the Mac's sheet): a name, the steps in order (reorder, remove), and
/// "Add Step …" with a search over Live's plugins, devices and presets. One key then inserts them all.</summary>
sealed class ChainEditor : Window
{
    readonly AppModel model;
    readonly List<PluginItem> steps;
    readonly TextBox name;
    readonly StackPanel stepList = new();
    readonly StackPanel picker = new() { Visibility = Visibility.Collapsed };
    readonly StackPanel results = new();
    readonly TextBox search;
    readonly Border save;
    bool saved;

    public static void Create(Window owner, AppModel model, Guid category, List<PluginItem> preset)
    {
        var editor = new ChainEditor(model, Loc.T("Neue Kette", "New Chain"), "", preset) { Owner = owner };
        editor.ShowDialog();
        if (!editor.saved) return;
        model.Config.AddChain(editor.name.Text.Trim(), editor.steps, category);
        model.ConfigChanged();
    }

    public static void Edit(Window owner, AppModel model, Guid category, Entry chain)
    {
        var editor = new ChainEditor(model, Loc.T("Kette bearbeiten", "Edit Chain"), chain.Title, chain.Chain?.ToList() ?? new()) { Owner = owner };
        editor.ShowDialog();
        if (!editor.saved) return;
        model.Config.UpdateChain(chain.Id, category, editor.name.Text.Trim(), editor.steps);
        model.ConfigChanged();
    }

    ChainEditor(AppModel model, string title, string initialName, List<PluginItem> initialSteps)
    {
        this.model = model;
        steps = initialSteps;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.WidthAndHeight;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        FontFamily = Theme.Font;

        var root = new StackPanel { Width = 520 };
        root.Children.Add(UI.Text(title, 22, weight: FontWeights.Bold));
        var sub = UI.Text(Loc.T("Eine Taste fügt diese Einträge der Reihe nach ein.", "One key inserts these items in order."), 14, Theme.TextSecondary);
        sub.Margin = new Thickness(0, 4, 0, 16);
        root.Children.Add(sub);
        name = UI.TextBox(initialName, Loc.T("Name, z. B. „Vocal Basic“", "Name, e.g. “Vocal Basic”"));
        name.TextChanged += (_, _) => UpdateSave();
        root.Children.Add(name);
        var list = new Border
        {
            Margin = new Thickness(0, 16, 0, 14), MinHeight = 160, CornerRadius = new CornerRadius(Theme.Radius(12)), Background = UI.Raised,
            BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1), Padding = new Thickness(10),
            Child = new ScrollViewer { Content = stepList, MaxHeight = 300, VerticalScrollBarVisibility = ScrollBarVisibility.Auto },
        };
        root.Children.Add(list);

        var add = UI.SmallButton(Loc.T("Schritt hinzufügen …", "Add Step …"), TogglePicker, "");
        add.Margin = new Thickness(0);
        add.HorizontalAlignment = HorizontalAlignment.Left;
        root.Children.Add(add);
        (var field, search) = UI.SearchField("", Loc.T("Plugins, Geräte, Presets suchen", "Search plugins, devices, presets"));
        field.Margin = new Thickness(0, 10, 0, 6);
        search.TextChanged += (_, _) => FillResults();
        search.KeyDown += (_, e) => { if (e.Key == Key.Enter && results.Children.Count > 0 && results.Children[0] is FrameworkElement first && first.Tag is PluginItem item) Add(item); };
        picker.Children.Add(field);
        picker.Children.Add(new ScrollViewer { Content = results, MaxHeight = 240, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        root.Children.Add(picker);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 18, 0, 0) };
        buttons.Children.Add(UI.Button(Loc.T("Abbrechen", "Cancel"), Close));
        save = UI.Primary(Loc.T("Sichern", "Save"), () => { if (CanSave) { saved = true; Close(); } });
        buttons.Children.Add(save);
        root.Children.Add(buttons);

        Content = new Border
        {
            Background = UI.Canvas, BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(Theme.Radius(16)),
            Padding = new Thickness(30, 26, 30, 26), Child = root, Margin = new Thickness(16),
            Effect = new DropShadowEffect { BlurRadius = 26, ShadowDepth = 6, Opacity = 0.5, Color = Colors.Black },
        };
        KeyDown += (_, e) => { if (e.Key == Key.Escape) Close(); };
        Loaded += (_, _) => { name.Focus(); if (steps.Count == 0) TogglePicker(); };
        FillSteps();
    }

    bool CanSave => name.Text.Trim().Length > 0 && steps.Count > 0;

    void UpdateSave() => save.Opacity = CanSave ? 1 : 0.45;

    void TogglePicker()
    {
        picker.Visibility = picker.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
        if (picker.Visibility == Visibility.Visible) { search.Focus(); FillResults(); }
    }

    void FillSteps()
    {
        stepList.Children.Clear();
        if (steps.Count == 0)
        {
            var empty = UI.Text(Loc.T("Noch keine Schritte", "No steps yet"), 15, Theme.TextTertiary);
            empty.HorizontalAlignment = HorizontalAlignment.Center;
            empty.Margin = new Thickness(0, 50, 0, 50);
            stepList.Children.Add(empty);
        }
        for (var i = 0; i < steps.Count; i++)
        {
            var index = i;
            var item = steps[i];
            var buttons = new StackPanel { Orientation = Orientation.Horizontal };
            var up = UI.IconButton("", () => { if (index > 0) { (steps[index - 1], steps[index]) = (steps[index], steps[index - 1]); FillSteps(); } }, Loc.T("Früher", "Earlier"));
            up.Opacity = index > 0 ? 1 : 0.3;
            buttons.Children.Add(up);
            var down = UI.IconButton("", () => { if (index < steps.Count - 1) { (steps[index + 1], steps[index]) = (steps[index], steps[index + 1]); FillSteps(); } }, Loc.T("Später", "Later"));
            down.Opacity = index < steps.Count - 1 ? 1 : 0.3;
            buttons.Children.Add(down);
            buttons.Children.Add(UI.IconButton("", () => { steps.RemoveAt(index); FillSteps(); }, Loc.T("Entfernen", "Remove")));
            var lead = new StackPanel { Orientation = Orientation.Horizontal };
            var n = UI.Text((i + 1).ToString(), 12.5, Theme.Accent, FontWeights.Bold);
            n.Width = 20;
            lead.Children.Add(n);
            lead.Children.Add(Theme.Icon(IconGuesser.Guess(item), 15, Theme.TextSecondary));
            stepList.Children.Add(UI.Row(item.Name, PluginGrouping.FormatLabel(item), buttons, lead, 46));
        }
        UpdateSave();
    }

    void FillResults()
    {
        results.Children.Clear();
        var q = search.Text.Trim();
        var items = model.Catalog.Items;
        IEnumerable<PluginItem> hits = q.Length == 0
            ? model.Usage.Counts.OrderByDescending(p => p.Value).Select(p => items.FirstOrDefault(i => model.SearchIndex.UsageKey.TryGetValue(i.Uri, out var k) && k == p.Key)).OfType<PluginItem>()
            : items.Select(i => (Item: i, Score: SearchMatcher.Score(i.Name, q))).Where(x => x.Score != null).OrderByDescending(x => x.Score).Select(x => x.Item);
        foreach (var item in hits.Take(12))
        {
            var row = UI.Row(item.Name, PluginGrouping.FormatLabel(item), null, Theme.Icon(IconGuesser.Guess(item), 15, Theme.TextTertiary), 40);
            var b = new Border { Child = row, Padding = new Thickness(10, 0, 10, 0), CornerRadius = new CornerRadius(Theme.Radius(7)), Background = Brushes.Transparent, Cursor = Cursors.Hand, Tag = item };
            b.MouseEnter += (_, _) => b.Background = UI.Hover;
            b.MouseLeave += (_, _) => b.Background = Brushes.Transparent;
            b.MouseLeftButtonUp += (_, _) => Add(item);
            results.Children.Add(b);
        }
        if (items.Count == 0) results.Children.Add(UI.Caption(Loc.T("Keine Plugin-Liste – ist Live mit ASMbridge verbunden?", "No plugin list – is Live connected with ASMbridge?")));
    }

    void Add(PluginItem item)
    {
        steps.Add(item);
        if (name.Text.Trim().Length == 0 && steps.Count == 1) name.Text = item.Name;
        FillSteps();
        search.SelectAll();
        search.Focus();
    }
}
