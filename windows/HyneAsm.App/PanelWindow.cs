using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>The double-right-click panel: categories as tabs, pads in pages, typing searches all plugins.</summary>
sealed class PanelWindow : Overlay
{
    readonly AppModel model;
    PanelState? state;
    PanelPage layout;
    int page, lastTab;
    int? hovered;

    public PanelWindow(AppModel model)
    {
        this.model = model;
        MouseWheel += (_, e) => TurnPage(e.Delta < 0 ? 1 : -1);
    }

    int PageCount => state == null ? 1 : Math.Max(1, (state.Rows.Count + layout.Size - 1) / layout.Size);

    public void ShowAt(Native.POINT p)
    {
        state = new PanelState(model.Config, model.SearchIndex, lastTab, model.Usage.Counts);
        layout = model.Config.PanelPage;
        page = 0;
        hovered = null;
        model.PanelOpened = true;
        Render();
        base.ShowAt(p);
    }

    public void Handle(PanelKey key)
    {
        if (state == null || !IsVisible) return;
        state.Page = page;
        state.PageSize = layout.Size;
        var action = state.Handle(key);
        lastTab = state.SelectedTab;
        if (state.Highlighted is { } h) page = h / layout.Size;
        else page = Math.Min(page, PageCount - 1);
        Perform(action);
        if (IsVisible) { Render(); Reposition(); }
    }

    void Perform(PanelAction action)
    {
        switch (action.Kind)
        {
            case PanelActionKind.Close: Hide(); break;
            case PanelActionKind.Insert when action.Row != null: Insert(action.Row); break;
        }
    }

    void Insert(PanelRow row)
    {
        if (!row.IsAvailable || state == null) return;
        if (row.FolderID is { } folder) { state.OpenFolder(folder); page = 0; Render(); Reposition(); return; }
        // Pinned mode: with Shift held the panel stays for the next insert.
        if (!Native.IsDown(Native.VK_SHIFT)) Hide();
        model.Insert(row);
    }

    void TurnPage(int delta)
    {
        var next = Math.Clamp(page + delta, 0, PageCount - 1);
        if (next == page) return;
        page = next;
        Render();
    }

    void SelectTab(int index)
    {
        if (state == null) return;
        state.SelectTab(index);
        lastTab = state.SelectedTab;
        page = 0;
        Render();
        Reposition();
    }

    // MARK: Drawing

    (double W, double H) CellSize()
    {
        var size = model.Config.PanelSize;
        return model.Config.PanelStyle == PanelStyle.Grid
            ? (size.ColumnWidth / 3, size.ColumnWidth / 3)
            : (size.ColumnWidth, size.ItemHeight);
    }

    void Render()
    {
        if (state == null) return;
        var root = new StackPanel { Margin = new Thickness(10) };
        root.Children.Add(Tabs());
        root.Children.Add(Header());
        root.Children.Add(Pads());
        if (PageCount > 1) root.Children.Add(PageDots());
        Content = new Border
        {
            Background = Theme.Background, BorderBrush = Theme.Border, BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12), Child = root,
        };
    }

    UIElement Tabs()
    {
        var bar = new WrapPanel { Margin = new Thickness(2, 0, 2, 6) };
        for (var i = 0; i < state!.Tabs.Count; i++)
        {
            var index = i;
            var name = state.Tabs[i] is PanelTab.Category c ? c.Name : "";
            var selected = i == state.SelectedTab && state.Filter.Length == 0;
            var label = new TextBlock
            {
                Text = name, FontSize = 12.5, FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal,
                Foreground = selected ? Theme.Accent : Theme.Dim, Padding = new Thickness(8, 4, 8, 4), Cursor = Cursors.Hand,
            };
            label.MouseLeftButtonUp += (_, _) => SelectTab(index);
            bar.Children.Add(new Border
            {
                Child = label, BorderBrush = selected ? Theme.Accent : Brushes.Transparent, BorderThickness = new Thickness(0, 0, 0, 2),
                Background = Brushes.Transparent,
            });
        }
        return bar;
    }

    UIElement Header()
    {
        var text = new TextBlock { FontSize = 13, Margin = new Thickness(6, 0, 6, 6), Cursor = Cursors.Arrow };
        if (state!.OpenFolderName is { } folder && state.Filter.Length == 0)
        {
            text.Text = "‹  " + folder;
            text.Foreground = Theme.Text;
            text.Cursor = Cursors.Hand;
            text.MouseLeftButtonUp += (_, _) => { state.CloseFolder(); page = 0; Render(); Reposition(); };
        }
        else if (state.Filter.Length == 0)
        {
            text.Text = Loc.T("Tippen zum Suchen · Rechtsklick auf ein Pad: Favorit", "Type to search · right-click a pad: favorite");
            text.Foreground = Theme.Faint;
        }
        else
        {
            text.Inlines.Add(new System.Windows.Documents.Run("⌕  ") { Foreground = Theme.Dim });
            text.Inlines.Add(new System.Windows.Documents.Run(state.Filter)
            {
                Foreground = Theme.Text, Background = state.IsFilterSelected ? Theme.Accent : Brushes.Transparent,
            });
            text.Inlines.Add(new System.Windows.Documents.Run("▏") { Foreground = Theme.Accent });
        }
        return text;
    }

    UIElement Pads()
    {
        var (w, h) = CellSize();
        var grid = new Grid();
        for (var c = 0; c < layout.Columns; c++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(w) });
        for (var r = 0; r < layout.Rows; r++) grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(h) });
        var rows = state!.Rows;
        var first = page * layout.Size;
        for (var slot = 0; slot < layout.Size; slot++)
        {
            var index = first + slot;
            var (row, column) = layout.Position(slot);
            UIElement cell = index < rows.Count ? Pad(rows[index], index, slot) : EmptyPad();
            Grid.SetRow(cell, row);
            Grid.SetColumn(cell, column);
            grid.Children.Add(cell);
        }
        if (rows.Count == 0)
        {
            var empty = new TextBlock
            {
                Text = state.Filter.Length > 0
                    ? Loc.T("Nichts gefunden", "Nothing found")
                    : model.Catalog.Items.Count == 0
                        ? Loc.T("Noch keine Plugin-Liste – ist Live mit ASMbridge verbunden?", "No plugin list yet – is Live connected with ASMbridge?")
                        : Loc.T("Leer – tippe, um alle Plugins zu durchsuchen", "Empty – type to search all plugins"),
                Foreground = Theme.Dim, FontSize = 13, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(20),
            };
            Grid.SetColumnSpan(empty, layout.Columns);
            Grid.SetRowSpan(empty, layout.Rows);
            grid.Children.Add(empty);
        }
        return grid;
    }

    static UIElement EmptyPad() => new Border
    {
        Margin = new Thickness(3), CornerRadius = new CornerRadius(8), Background = Theme.PadTop, Opacity = 0.25,
    };

    UIElement Pad(PanelRow row, int index, int slot)
    {
        var isGrid = model.Config.PanelStyle == PanelStyle.Grid;
        var highlighted = state!.Highlighted == index;
        var content = new Grid();
        var title = new TextBlock
        {
            Text = row.Title, Foreground = Theme.Text, FontSize = isGrid ? 12 : 13, TextWrapping = isGrid ? TextWrapping.Wrap : TextWrapping.NoWrap,
            TextTrimming = TextTrimming.CharacterEllipsis, TextAlignment = isGrid ? TextAlignment.Center : TextAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = isGrid ? HorizontalAlignment.Center : HorizontalAlignment.Left,
            Margin = isGrid ? new Thickness(6, 14, 6, 6) : new Thickness(30, 0, 8, 0),
        };
        content.Children.Add(title);
        if (slot < 9)
            content.Children.Add(new TextBlock
            {
                Text = (slot + 1).ToString(), Foreground = Theme.Faint, FontSize = 10.5, Margin = new Thickness(7, 5, 0, 0),
                HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = isGrid ? VerticalAlignment.Top : VerticalAlignment.Center,
            });
        string? badge = row.FolderID != null ? "▸ " + row.ChildCount : row.IsNew ? "NEW" : row.Chain != null ? "⛓" : null;
        if (badge != null)
            content.Children.Add(new TextBlock
            {
                Text = badge, Foreground = row.IsNew ? Theme.Accent : Theme.Dim, FontSize = 10, Margin = new Thickness(0, 5, 7, 4),
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = isGrid ? VerticalAlignment.Bottom : VerticalAlignment.Center,
            });
        var stripe = ColorPalette.Color(row.ColorID) is { } color ? Theme.Of(color) : null;
        var pad = new Border
        {
            Margin = new Thickness(3), CornerRadius = new CornerRadius(8), Child = content, Cursor = Cursors.Hand,
            Background = hovered == index ? Theme.PadHover : Theme.Pad, Opacity = row.IsAvailable ? 1 : 0.4,
            BorderBrush = highlighted ? Theme.Accent : stripe ?? Theme.Border,
            BorderThickness = highlighted ? new Thickness(2) : stripe != null ? new Thickness(3, 1, 1, 1) : new Thickness(1),
            ToolTip = row.IsGlobal && row.Path.Count > 0 ? string.Join(" › ", row.Path) : null,
        };
        pad.MouseEnter += (_, _) => { hovered = index; pad.Background = Theme.PadHover; };
        pad.MouseLeave += (_, _) => { if (hovered == index) hovered = null; pad.Background = Theme.Pad; };
        pad.MouseLeftButtonUp += (_, _) => Insert(row);
        pad.MouseRightButtonUp += (_, e) => { e.Handled = true; ShowPadMenu(pad, row); };
        return pad;
    }

    void ShowPadMenu(FrameworkElement pad, PanelRow row)
    {
        if (row.FolderID != null || row.Action != null || row.Chain != null || row.Uri.Length == 0) return;
        var menu = new ContextMenu();
        var fav = new MenuItem { Header = model.IsFavorite(row) ? Loc.T("Aus Favoriten entfernen", "Remove from Favorites") : Loc.T("Zu Favoriten", "Add to Favorites") };
        fav.Click += (_, _) => { model.ToggleFavorite(row); Rebuild(); };
        menu.Items.Add(fav);
        var add = new MenuItem { Header = Loc.T("Zu Kategorie hinzufügen", "Add to category") };
        foreach (var category in model.Config.Categories.Where(c => !c.IsFavorites))
        {
            var item = new MenuItem { Header = category.Name };
            var id = category.Id;
            item.Click += (_, _) => { model.AddToCategory(row, id); Rebuild(); };
            add.Items.Add(item);
        }
        if (add.Items.Count > 0) menu.Items.Add(add);
        menu.PlacementTarget = pad;
        menu.IsOpen = true;
    }

    /// <summary>After a menu change: same tab, same filter, fresh rows.</summary>
    void Rebuild()
    {
        if (state == null) return;
        var filter = state.Filter;
        state = new PanelState(model.Config, model.SearchIndex, state.SelectedTab, model.Usage.Counts);
        foreach (var ch in System.Globalization.StringInfo.GetTextElementEnumerator(filter).AsEnumerable())
            state.Handle(PanelKey.OfCharacter(ch));
        Render();
        Reposition();
    }

    UIElement PageDots()
    {
        var dots = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 6, 0, 0) };
        for (var i = 0; i < PageCount; i++)
        {
            var index = i;
            var dot = new TextBlock
            {
                Text = "●", FontSize = 9, Margin = new Thickness(3, 0, 3, 0), Cursor = Cursors.Hand,
                Foreground = i == page ? Theme.Accent : Theme.Faint,
            };
            dot.MouseLeftButtonUp += (_, _) => { page = index; Render(); };
            dots.Children.Add(dot);
        }
        return dots;
    }
}

static class TextElementExtensions
{
    public static IEnumerable<string> AsEnumerable(this System.Globalization.TextElementEnumerator e)
    {
        while (e.MoveNext()) yield return e.GetTextElement();
    }
}
