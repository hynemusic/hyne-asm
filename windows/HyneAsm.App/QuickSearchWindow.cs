using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>The quick search: a field in the upper middle of the screen, results below (same look as the Mac's).
/// Like the panel it never takes focus from Live — keys arrive through the keyboard hook.</summary>
sealed class QuickSearchWindow : Overlay
{
    const double Width_ = 620, FieldHeight = 58, RowHeight = 42;
    const int Visible = 8;
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

    public void Warm()
    {
        state = new QuickSearchState(new QuickSearch(model.Config, model.SearchIndex, model.Usage.Counts));
        Render();
        Prewarm();
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
        FontFamily = Theme.Display;
        var root = new StackPanel { Width = Width_ };
        root.Children.Add(Field());
        var results = state.Results;
        if (results.Count > 0)
        {
            root.Children.Add(new Border { Height = 1, Background = Theme.Stroke });
            var list = new StackPanel { Margin = new Thickness(8) };
            var start = Math.Max(0, Math.Min(state.Highlighted - Visible / 2, results.Count - Visible));
            for (var i = start; i < Math.Min(results.Count, start + Visible); i++) list.Children.Add(Row(results[i], i));
            root.Children.Add(list);
        }
        Content = Theme.Chrome(root, 16);
    }

    UIElement Field()
    {
        var typing = state!.Query.Length > 0;
        var line = new DockPanel { Height = FieldHeight, Margin = new Thickness(18, 0, 18, 0), LastChildFill = true };
        var hints = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        hints.Children.Add(Hint("↵", Loc.T("einfügen", "insert")));
        hints.Children.Add(Hint("esc", Loc.T("schließen", "close")));
        DockPanel.SetDock(hints, Dock.Right);
        line.Children.Add(hints);
        var icon = new TextBlock { Text = "", FontFamily = Theme.Icons, FontSize = 18, Foreground = typing ? Theme.Accent : Theme.TextTertiary, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) };
        DockPanel.SetDock(icon, Dock.Left);
        line.Children.Add(icon);
        var text = new TextBlock { FontSize = 20, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
        if (typing)
        {
            text.Inlines.Add(new System.Windows.Documents.Run(state.Query)
            {
                Foreground = state.IsQuerySelected ? Theme.OnAccent : Theme.TextPrimary,
                Background = state.IsQuerySelected ? Theme.Accent : Brushes.Transparent,
            });
            if (!state.IsQuerySelected) text.Inlines.Add(new System.Windows.Documents.Run("▏") { Foreground = Theme.Accent });
        }
        else
        {
            // Caret before the placeholder, like a real empty field.
            text.Inlines.Add(new System.Windows.Documents.Run("▏") { Foreground = Theme.Accent });
            text.Inlines.Add(new System.Windows.Documents.Run(Loc.T("Plugins und Presets suchen …", "Search plugins and presets …")) { Foreground = Theme.TextTertiary });
        }
        line.Children.Add(text);
        return line;
    }

    static UIElement Hint(string key, string text)
    {
        var hint = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(10, 0, 0, 0) };
        var cap = Theme.KeyCap(key, Theme.TextSecondary, Theme.Ink(0.07));
        cap.VerticalAlignment = VerticalAlignment.Center;
        hint.Children.Add(cap);
        hint.Children.Add(new TextBlock { Text = text, FontSize = 11, Foreground = Theme.TextTertiary, Margin = new Thickness(5, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, FontFamily = Theme.Font });
        return hint;
    }

    /// <summary>Same rows as the panel's list: plate, icon in the label colour, short glowing stripe, lit when chosen.</summary>
    UIElement Row(QuickResult result, int index)
    {
        var holder = new Border { Height = RowHeight, Margin = new Thickness(0, 0, 0, 4), Cursor = Cursors.Hand, Background = Brushes.Transparent };
        holder.Child = Plate(result, index == state!.Highlighted);
        holder.Opacity = result.Row.IsAvailable ? 1 : 0.5;
        holder.MouseEnter += (_, _) => { if (state.Highlighted != index) { state.Highlight(index); Render(); } };
        holder.MouseLeftButtonUp += (_, _) => Insert(result.Row);
        return holder;
    }

    static Border Plate(QuickResult result, bool active)
    {
        var r = result.Row;
        var color = Theme.LabelColor(r.ColorID);
        var onLit = Theme.Current.OnLitPad;
        var line = new DockPanel { LastChildFill = true, Margin = new Thickness(10, 0, 10, 2) };
        var icon = Theme.Icon(r.IconID, 15, active ? Theme.B(Color.FromArgb(190, onLit.R, onLit.G, onLit.B)) : color is { } c ? Theme.B(c) : Theme.TextTertiary);
        icon.Width = 20;
        icon.Margin = new Thickness(0, 0, 9, 0);
        DockPanel.SetDock(icon, Dock.Left);
        line.Children.Add(icon);
        var badges = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        if (r.IsNew) badges.Children.Add(Theme.NewBadge());
        if (active)
        {
            var enter = Theme.KeyCap("↵", Theme.B(onLit), Theme.B(Color.FromArgb(38, onLit.R, onLit.G, onLit.B)));
            enter.Margin = new Thickness(4, 0, 0, 0);
            badges.Children.Add(enter);
        }
        DockPanel.SetDock(badges, Dock.Right);
        line.Children.Add(badges);
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock
        {
            Text = r.Title, FontSize = 12, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis,
            Foreground = active ? Theme.B(onLit) : r.IsAvailable ? Theme.TextPrimary : Theme.TextTertiary,
        });
        var place = result.Place ?? Loc.T("Alle Plugins", "All plugins") + " · " + PluginGrouping.FormatLabel(new PluginItem(r.Uri, r.Name, r.Source, r.Path));
        text.Children.Add(new TextBlock
        {
            Text = place, FontSize = 11, FontFamily = Theme.Font, TextTrimming = TextTrimming.CharacterEllipsis,
            Foreground = active ? Theme.B(Color.FromArgb(178, onLit.R, onLit.G, onLit.B)) : Theme.TextTertiary,
        });
        line.Children.Add(text);
        var grid = new Grid();
        grid.Children.Add(line);
        var stripe = (FrameworkElement)Theme.Stripe(active, color, 64, 3);
        stripe.VerticalAlignment = VerticalAlignment.Bottom;
        stripe.Margin = new Thickness(0, 0, 0, 4);
        grid.Children.Add(stripe);
        return Theme.Plate(grid, active, color ?? Theme.Current.Accent);
    }
}
