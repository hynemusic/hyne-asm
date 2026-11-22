using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>The quick search: a field in the upper middle of the screen, results below. Like the panel it never
/// takes focus from Live — keys arrive through the keyboard hook.</summary>
sealed class QuickSearchWindow : Overlay
{
    const int Visible = 10;
    readonly AppModel model;
    QuickSearchState? state;

    public QuickSearchWindow(AppModel model) { this.model = model; }

    public void Toggle() { if (IsVisible) Hide(); else Open(); }

    public void Open()
    {
        state = new QuickSearchState(new QuickSearch(model.Config, model.SearchIndex, model.Usage.Counts));
        Render();
        Native.GetCursorPos(out var p);
        ShowAt(p, centerOnScreen: true);
    }

    public void Handle(PanelKey key)
    {
        if (state == null || !IsVisible) return;
        var action = state.Handle(key);
        switch (action.Kind)
        {
            case PanelActionKind.Close: Hide(); return;
            case PanelActionKind.Insert when action.Row != null: Insert(action.Row); return;
            default: Render(); Reposition(); return;
        }
    }

    void Insert(PanelRow row)
    {
        if (!row.IsAvailable) return;
        Hide();
        model.Insert(row);
    }

    void Render()
    {
        if (state == null) return;
        var root = new StackPanel { Width = 560, Margin = new Thickness(14, 12, 14, 12) };
        var query = new TextBlock { FontSize = 19, Margin = new Thickness(4, 0, 4, 8) };
        if (state.Query.Length == 0)
        {
            query.Text = Loc.T("Plugin, Preset oder Befehl suchen …", "Search plugins, presets or commands …");
            query.Foreground = Theme.Faint;
        }
        else
        {
            query.Inlines.Add(new System.Windows.Documents.Run(state.Query)
            {
                Foreground = Theme.Text, Background = state.IsQuerySelected ? Theme.Accent : System.Windows.Media.Brushes.Transparent,
            });
            query.Inlines.Add(new System.Windows.Documents.Run("▏") { Foreground = Theme.Accent });
        }
        root.Children.Add(query);
        var results = state.Results;
        var start = Math.Max(0, Math.Min(state.Highlighted - Visible / 2, results.Count - Visible));
        for (var i = start; i < Math.Min(results.Count, start + Visible); i++)
        {
            var result = results[i];
            var line = new DockPanel { LastChildFill = true };
            var place = new TextBlock { Text = result.Place ?? "", Foreground = Theme.Dim, FontSize = 12, VerticalAlignment = VerticalAlignment.Center };
            DockPanel.SetDock(place, Dock.Right);
            line.Children.Add(place);
            line.Children.Add(new TextBlock
            {
                Text = result.Row.Title, Foreground = Theme.Text, FontSize = 14, TextTrimming = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center,
            });
            var row = new Border
            {
                Child = line, Padding = new Thickness(10, 6, 10, 6), CornerRadius = new CornerRadius(6), Cursor = Cursors.Hand,
                Background = i == state.Highlighted ? Theme.PadHover : System.Windows.Media.Brushes.Transparent,
                BorderBrush = i == state.Highlighted ? Theme.Accent : System.Windows.Media.Brushes.Transparent,
                BorderThickness = new Thickness(1), Opacity = result.Row.IsAvailable ? 1 : 0.4,
            };
            var r = result.Row;
            row.MouseLeftButtonUp += (_, _) => Insert(r);
            root.Children.Add(row);
        }
        if (results.Count == 0 && state.Query.Length > 0)
            root.Children.Add(new TextBlock { Text = Loc.T("Nichts gefunden", "Nothing found"), Foreground = Theme.Dim, Margin = new Thickness(10, 4, 10, 4) });
        Content = new Border
        {
            Background = Theme.Background, BorderBrush = Theme.Border, BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(14), Child = root,
        };
    }
}
