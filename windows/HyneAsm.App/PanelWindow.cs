using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>The double-right-click panel: categories as tabs, pads in pages, typing searches all plugins.
/// Same layout and metrics as the Mac panel (PanelView.swift).</summary>
sealed class PanelWindow : Overlay
{
    const double Inset = 8, PadSpacing = 6, TabBarHeight = 34, FooterHeight = 22, EdgeWidth = 30;

    readonly AppModel model;
    PanelState? state;
    PanelPage layout;
    int page, lastTab;
    int? hovered;
    bool pinned;
    public Action? OnOpenSettings;
    readonly FolderFlyout flyout;
    Guid? flyoutFolder;
    FrameworkElement? flyoutAnchor;
    readonly Dictionary<Guid, FrameworkElement> folderPads = new();
    readonly DispatcherTimer flyoutHide = new() { Interval = TimeSpan.FromMilliseconds(180) };
    readonly DispatcherTimer edgeTimer = new();
    const double LeftStrip = 14;
    const string PadFormat = "HyneAsm.PanelPad";
    (int Index, Point At)? dragFrom;
    bool justDragged;

    /// <summary>Pads can be dragged in a category (top level), not in search results.</summary>
    bool CanReorder => state is { Filter.Length: 0, OpenFolderID: null } && state.Tabs.Count > 0 && state.Tabs[state.SelectedTab] is PanelTab.Category;

    void Reorder(int from, int to)
    {
        if (from == to || state?.Tabs[state.SelectedTab] is not PanelTab.Category category) return;
        model.Config.MoveEntry(category.Id, null, from, to);
        model.ConfigChanged();
        state = new PanelState(model.Config, model.SearchIndex, lastTab, model.Usage.Counts);
        hovered = null;
        Render();
    }
    double bodyTop, bodyBottom;

    public PanelWindow(AppModel model)
    {
        this.model = model;
        MouseWheel += (_, e) => TurnPage(e.Delta < 0 ? 1 : -1);
        flyout = new FolderFlyout(this);
        flyout.MouseEnter += (_, _) => flyoutHide.Stop();
        flyout.MouseLeave += (_, _) => ScheduleFlyoutHide();
        flyoutHide.Tick += (_, _) =>
        {
            flyoutHide.Stop();
            Native.GetCursorPos(out var p);
            if (flyout.Contains(p) || (flyoutAnchor is { IsMouseOver: true })) return;
            HideFlyout();
        };
        IsVisibleChanged += (_, _) => { if (!IsVisible) { HideFlyout(); edgeTimer.Stop(); } };
        edgeTimer.Tick += (_, _) => EdgeTick();
    }

    /// <summary>The panel or its folder side list.</summary>
    public new bool Contains(Native.POINT p) => base.Contains(p) || flyout.Contains(p);

    int PageCount => state == null ? 1 : Math.Max(1, (state.Rows.Count + layout.Size - 1) / layout.Size);
    bool IsGrid => model.Config.PanelStyle == PanelStyle.Grid;

    public void ShowAt(Native.POINT p)
    {
        state = new PanelState(model.Config, model.SearchIndex, lastTab, model.Usage.Counts);
        layout = model.Config.PanelPage;
        page = 0;
        hovered = null;
        pinned = Native.IsDown(Native.VK_SHIFT);
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
        hovered = null;
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

    internal void InsertFromFlyout(PanelRow row) => Insert(row);

    void Insert(PanelRow row)
    {
        if (!row.IsAvailable || state == null) return;
        if (row.FolderID is { } folder)
        {
            // Clicking (or Enter on) a folder opens its side list.
            if (folderPads.TryGetValue(folder, out var anchor)) ShowFlyout(anchor, folder);
            else { state.OpenFolder(folder); page = 0; hovered = null; Render(); Reposition(); }
            return;
        }
        // Pinned mode: with Shift held the panel stays for the next insert.
        if (!Native.IsDown(Native.VK_SHIFT)) Hide();
        model.Insert(row);
    }

    void TurnPage(int delta)
    {
        var next = Math.Clamp(page + delta, 0, PageCount - 1);
        if (next == page) return;
        page = next;
        hovered = null;
        Render();
    }

    void SelectTab(int index)
    {
        if (state == null) return;
        state.SelectTab(index);
        lastTab = state.SelectedTab;
        page = 0;
        hovered = null;
        Render();
        Reposition();
    }

    // MARK: Folder side list

    void ShowFlyout(FrameworkElement anchor, Guid folder)
    {
        flyoutHide.Stop();
        if (state == null) return;
        flyoutAnchor = anchor;
        if (flyoutFolder == folder && flyout.IsVisible) return;
        flyoutFolder = folder;
        // Right beside the folder pad, its first row level with the pad's top, over whatever is there.
        var corner = anchor.PointToScreen(new Point(anchor.ActualWidth + 4, 0));
        flyout.Show(state.FolderRows(folder), new Native.POINT { X = (int)corner.X, Y = (int)corner.Y }, IsGrid, ItemWidth, ItemHeight);
    }

    void ScheduleFlyoutHide()
    {
        if (!flyout.IsVisible) return;
        flyoutHide.Stop();
        flyoutHide.Start();
    }

    void HideFlyout()
    {
        flyoutHide.Stop();
        flyoutFolder = null;
        flyoutAnchor = null;
        flyout.Hide();
    }

    // MARK: Page turning at the edges

    void StartEdge()
    {
        if (PageCount <= 1 || edgeTimer.IsEnabled) return;
        edgeTimer.Interval = TimeSpan.FromMilliseconds(150);
        edgeTimer.Start();
    }

    /// <summary>While the pointer rests on an edge strip: turn, then keep turning every 380 ms.</summary>
    void EdgeTick()
    {
        var p = Mouse.GetPosition(this);
        var inBody = p.Y >= bodyTop && p.Y <= bodyBottom;
        var x0 = model.Config.CategoryPlacement == CategoryPlacement.Left ? 132 + Inset * 2 + 13 : Inset;
        var direction = !inBody || !IsMouseOver ? 0 : p.X < x0 + LeftStrip ? -1 : p.X > ActualWidth - Inset - EdgeWidth - 4 ? 1 : 0;
        if (direction == 0) { edgeTimer.Stop(); return; }
        TurnPage(direction);
        edgeTimer.Interval = TimeSpan.FromMilliseconds(380);
    }

    // MARK: Drawing

    double ItemWidth => IsGrid ? (model.Config.PanelSize.ColumnWidth - PadSpacing * 2) / 3 : model.Config.PanelSize.ColumnWidth;
    double ItemHeight => IsGrid ? model.Config.PanelSize.ItemHeight + 38 : model.Config.PanelSize.ItemHeight;
    double VSpacing => IsGrid ? PadSpacing : 4;
    double GridWidth => layout.Columns * ItemWidth + (layout.Columns - 1) * PadSpacing;
    double GridHeight => layout.Rows * ItemHeight + (layout.Rows - 1) * VSpacing;

    void Render()
    {
        if (state == null) return;
        FontFamily = Theme.Display;
        var left = model.Config.CategoryPlacement == CategoryPlacement.Left;
        var root = new StackPanel { Margin = new Thickness(Inset) };
        if (!left || state.Filter.Length > 0 || state.OpenFolderName != null) root.Children.Add(TopRow());
        else root.Children.Add(CategoryHeader());
        folderPads.Clear();
        // Edge strips: resting the pointer on the left or right edge turns the page (like the Mac).
        var body = new DockPanel { Width = LeftStrip + GridWidth + EdgeWidth + 6, Height = GridHeight, LastChildFill = false, Background = Brushes.Transparent };
        var back = EdgeArrow(page > 0 ? "\uE76B" : "", -1);
        back.Width = LeftStrip;
        DockPanel.SetDock(back, Dock.Left);
        body.Children.Add(back);
        var pads = Pads();
        DockPanel.SetDock(pads, Dock.Left);
        body.Children.Add(pads);
        var next = EdgeArrow(page < PageCount - 1 ? "\uE76C" : "", 1);
        DockPanel.SetDock(next, Dock.Right);
        body.Children.Add(next);
        body.Loaded += (_, _) =>
        {
            var top = body.TranslatePoint(new Point(0, 0), this).Y;
            (bodyTop, bodyBottom) = (top, top + body.ActualHeight);
        };
        root.Children.Add(body);
        root.Children.Add(Footer());
        if (!left) { Content = Theme.Chrome(root, 12); return; }
        // Categories as a column on the left (Behavior → Categories: Left).
        var column = new StackPanel { Width = 132, Margin = new Thickness(Inset, Inset, 6, Inset) };
        for (var i = 0; i < state.Tabs.Count; i++)
        {
            var tab = (Border)Tab(i);
            tab.Height = 28;
            tab.Margin = new Thickness(0, 0, 0, 2);
            tab.HorizontalAlignment = HorizontalAlignment.Stretch;
            column.Children.Add(tab);
        }
        var gear = SettingsGear();
        gear.HorizontalAlignment = HorizontalAlignment.Left;
        gear.Margin = new Thickness(4, 8, 0, 0);
        column.Children.Add(gear);
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(column);
        row.Children.Add(new Border { Width = 1, Background = Theme.Stroke, Margin = new Thickness(0, Inset, 0, Inset) });
        root.Margin = new Thickness(12, Inset, Inset, Inset);
        row.Children.Add(root);
        Content = Theme.Chrome(row, 12);
    }

    /// <summary>Categories on the left: the category's name and count above the pads.</summary>
    UIElement CategoryHeader()
    {
        var line = new StackPanel { Orientation = Orientation.Horizontal, Height = 24, Margin = new Thickness(2, 0, 0, 6) };
        var name = state!.Tabs[state.SelectedTab] is PanelTab.Category c ? c.Name : "";
        line.Children.Add(new TextBlock { Text = name, FontSize = 13, FontWeight = FontWeights.SemiBold, Foreground = Theme.TextPrimary, VerticalAlignment = VerticalAlignment.Center });
        line.Children.Add(new TextBlock { Text = state.Rows.Count.ToString(), FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = Theme.TextTertiary, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) });
        return line;
    }

    TextBlock SettingsGear()
    {
        var gear = new TextBlock
        {
            Text = "\uE713", FontFamily = Theme.Icons, FontSize = 12, Foreground = Theme.TextTertiary, Width = 26, TextAlignment = TextAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Right, Cursor = Cursors.Hand,
            Background = Brushes.Transparent, ToolTip = Loc.T("Einstellungen", "Settings"),
        };
        gear.MouseLeftButtonUp += (_, _) => OnOpenSettings?.Invoke();
        return gear;
    }

    FrameworkElement EdgeArrow(string glyph, int delta)
    {
        var arrow = new TextBlock
        {
            Text = glyph, FontFamily = Theme.Icons, FontSize = 13, Foreground = Theme.TextTertiary, Width = EdgeWidth,
            TextAlignment = TextAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Cursor = Cursors.Hand,
            Background = Brushes.Transparent, Height = GridHeight, Padding = new Thickness(0, GridHeight / 2 - 9, 0, 0),
        };
        arrow.MouseLeftButtonUp += (_, _) => TurnPage(delta);
        arrow.MouseEnter += (_, _) => StartEdge();
        return arrow;
    }

    /// <summary>Categories on top: the tabs, or while searching the search field, or an open folder.</summary>
    UIElement TopRow()
    {
        var row = new DockPanel { Height = TabBarHeight - 8, Margin = new Thickness(0, 0, 0, 8), LastChildFill = true };
        if (state!.OpenFolderName is { } folder && state.Filter.Length == 0)
        {
            var esc = EscHint();
            DockPanel.SetDock(esc, Dock.Right);
            row.Children.Add(esc);
            var back = new StackPanel { Orientation = Orientation.Horizontal, Cursor = Cursors.Hand, Background = Brushes.Transparent, VerticalAlignment = VerticalAlignment.Center };
            back.Children.Add(new TextBlock { Text = "", FontFamily = Theme.Icons, FontSize = 10, Foreground = Theme.TextTertiary, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(2, 0, 6, 0) });
            back.Children.Add(Theme.Icon("folder", 13, Theme.Accent));
            back.Children.Add(new TextBlock { Text = folder, FontSize = 13, FontWeight = FontWeights.SemiBold, Foreground = Theme.TextPrimary, Margin = new Thickness(6, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
            back.MouseLeftButtonUp += (_, _) => { state.CloseFolder(); page = 0; Render(); Reposition(); };
            row.Children.Add(back);
            return row;
        }
        if (state.Filter.Length > 0) return FilterField();
        // Tab bar with a hairline underneath.
        var tabs = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        for (var i = 0; i < state.Tabs.Count; i++) tabs.Children.Add(Tab(i));
        var bar = new Grid { Height = TabBarHeight - 8, Margin = new Thickness(0, 0, 0, 8) };
        bar.Children.Add(new Border { Height = 1, Background = Theme.Stroke, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, -5) });
        bar.Children.Add(tabs);
        bar.Children.Add(SettingsGear());
        return bar;
    }

    UIElement Tab(int index)
    {
        var selected = index == state!.SelectedTab;
        var name = state.Tabs[index] is PanelTab.Category c ? c.Name : "";
        var isFavorites = state.Tabs[index] is PanelTab.Category cat && model.Config.Categories.FirstOrDefault(x => x.Id == cat.Id)?.IsFavorites == true;
        var content = new StackPanel { Orientation = Orientation.Horizontal };
        if (isFavorites)
            content.Children.Add(new TextBlock { Text = "", FontFamily = Theme.Icons, FontSize = 10, Foreground = selected ? Theme.Accent : Theme.TextTertiary, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 5, 0) });
        content.Children.Add(new TextBlock
        {
            Text = name, FontSize = 12.5, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center,
            Foreground = selected ? Theme.TextPrimary : Theme.TextSecondary,
        });
        var tab = new Border
        {
            Child = content, Padding = new Thickness(9, 0, 9, 0), Height = 26, Cursor = Cursors.Hand, Margin = new Thickness(0, 0, 2, 0),
            CornerRadius = new CornerRadius(Theme.Radius(6)), Background = selected ? Theme.Ink(0.06) : Brushes.Transparent,
        };
        tab.MouseLeftButtonUp += (_, _) => SelectTab(index);
        // Like the Mac: pointing at a category shows it right away.
        tab.MouseEnter += (_, _) => { if (state != null && state.SelectedTab != index && state.Filter.Length == 0) SelectTab(index); };
        return tab;
    }

    /// <summary>What has been typed so far, drawn like a search field.</summary>
    UIElement FilterField()
    {
        var line = new DockPanel { LastChildFill = true, VerticalAlignment = VerticalAlignment.Center };
        var esc = EscHint();
        DockPanel.SetDock(esc, Dock.Right);
        line.Children.Add(esc);
        var icon = new TextBlock { Text = "", FontFamily = Theme.Icons, FontSize = 11, Foreground = Theme.Accent, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 7, 0) };
        DockPanel.SetDock(icon, Dock.Left);
        line.Children.Add(icon);
        var text = new TextBlock { FontSize = 13, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
        text.Inlines.Add(new System.Windows.Documents.Run(state!.Filter)
        {
            Foreground = state.IsFilterSelected ? Theme.OnAccent : Theme.TextPrimary,
            Background = state.IsFilterSelected ? Theme.Accent : Brushes.Transparent,
        });
        if (!state.IsFilterSelected) text.Inlines.Add(new System.Windows.Documents.Run("▏") { Foreground = Theme.Accent, FontWeight = FontWeights.Normal });
        line.Children.Add(text);
        return new Border
        {
            Height = 26, Margin = new Thickness(0, 0, 0, 8), Padding = new Thickness(9, 0, 9, 0), Child = line,
            CornerRadius = new CornerRadius(Theme.Radius(7)), Background = Theme.Ink(0.06), BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1),
        };
    }

    static UIElement EscHint() => new Border
    {
        BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(Theme.Radius(4)), Height = 15,
        Padding = new Thickness(5, 0, 5, 0), VerticalAlignment = VerticalAlignment.Center,
        Child = new TextBlock { Text = "esc", FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = Theme.TextTertiary, VerticalAlignment = VerticalAlignment.Center },
    };

    FrameworkElement Pads()
    {
        var canvas = new Canvas { Width = GridWidth, Height = GridHeight, Background = Brushes.Transparent };
        var rows = state!.Rows;
        var first = page * layout.Size;
        for (var slot = 0; slot < layout.Size && first + slot < rows.Count; slot++)
        {
            var (r, c) = layout.Position(slot);
            var pad = Pad(rows[first + slot], first + slot, slot);
            Canvas.SetLeft(pad, c * (ItemWidth + PadSpacing));
            Canvas.SetTop(pad, r * (ItemHeight + VSpacing));
            canvas.Children.Add(pad);
        }
        if (rows.Count == 0)
            canvas.Children.Add(new TextBlock
            {
                Width = GridWidth, Height = GridHeight, Padding = new Thickness(24, GridHeight / 2 - 20, 24, 0),
                Text = state.Filter.Length > 0
                    ? Loc.T("Nichts gefunden", "Nothing found")
                    : model.Catalog.Items.Count == 0
                        ? Loc.T("Noch keine Plugin-Liste – ist Live mit ASMbridge verbunden?", "No plugin list yet – is Live connected with ASMbridge?")
                        : Loc.T("Leer – tippe, um alle Plugins zu durchsuchen", "Empty – type to search all plugins"),
                Foreground = Theme.TextTertiary, FontSize = 12, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center,
            });
        return canvas;
    }

    /// <summary>A pad in a fixed-size holder; hovering swaps only its plate (no redraw of the whole panel).</summary>
    FrameworkElement Pad(PanelRow row, int index, int slot)
    {
        var holder = new Border { Width = ItemWidth, Height = ItemHeight, Cursor = Cursors.Hand, Background = Brushes.Transparent };
        bool Lit() => state!.Highlighted == index || hovered == index;
        holder.Child = Plate(row, slot, Lit());
        holder.Opacity = row.IsAvailable ? 1 : 0.5;
        holder.ToolTip = row.IsAvailable ? (row.Path.Count > 0 ? string.Join(" / ", row.Path) : null) : Loc.T("Nicht mehr in Live gefunden", "No longer found in Live");
        holder.MouseEnter += (_, _) =>
        {
            hovered = index;
            holder.Child = Plate(row, slot, true);
            if (row.FolderID is { } f) ShowFlyout(holder, f); else ScheduleFlyoutHide();
        };
        holder.MouseLeave += (_, _) =>
        {
            if (hovered == index) hovered = null;
            holder.Child = Plate(row, slot, Lit());
            if (row.FolderID != null) ScheduleFlyoutHide();
        };
        if (row.FolderID is { } fid) folderPads[fid] = holder;
        holder.MouseLeftButtonUp += (_, _) => { if (justDragged) { justDragged = false; return; } Insert(row); };
        holder.MouseRightButtonUp += (_, e) => { e.Handled = true; ShowPadMenu(holder, row); };
        // Drag a pad onto another to move it there (in a category, not while searching).
        holder.AllowDrop = true;
        holder.PreviewMouseLeftButtonDown += (_, e) => dragFrom = (index, e.GetPosition(this));
        holder.MouseMove += (_, e) =>
        {
            if (e.LeftButton != MouseButtonState.Pressed || dragFrom is not { } d || d.Index != index || !CanReorder) return;
            var p = e.GetPosition(this);
            if (Math.Abs(p.X - d.At.X) < 6 && Math.Abs(p.Y - d.At.Y) < 6) return;
            justDragged = true;
            HideFlyout();
            DragDrop.DoDragDrop(holder, new DataObject(PadFormat, index), DragDropEffects.Move);
            dragFrom = null;
        };
        holder.DragOver += (_, e) => { e.Effects = e.Data.GetDataPresent(PadFormat) ? DragDropEffects.Move : DragDropEffects.None; holder.Opacity = 0.55; e.Handled = true; };
        holder.DragLeave += (_, _) => holder.Opacity = row.IsAvailable ? 1 : 0.5;
        holder.Drop += (_, e) => { if (e.Data.GetData(PadFormat) is int from) Reorder(from, index); };
        return holder;
    }

    Border Plate(PanelRow row, int slot, bool active) => PadView.Build(PadData.Of(row, slot), IsGrid, active);

    /// <summary>Bottom line: what typing does (or that the panel is pinned, or how many hits), page dots on the right.</summary>
    UIElement Footer()
    {
        var line = new DockPanel { Height = FooterHeight, Margin = new Thickness(2, 6, 4, 0), LastChildFill = true };
        if (PageCount > 1)
        {
            UIElement dots;
            if (PageCount > 7)
                dots = new TextBlock { Text = $"{page + 1} / {PageCount}", FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = Theme.TextSecondary, VerticalAlignment = VerticalAlignment.Center };
            else
            {
                var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
                for (var i = 0; i < PageCount; i++)
                {
                    var p = i;
                    var dot = new Border
                    {
                        Width = 16, Height = 6, CornerRadius = new CornerRadius(3), Margin = new Thickness(2.5, 6, 2.5, 6), Cursor = Cursors.Hand,
                        Background = i == page ? Theme.TextPrimary : Theme.B(Theme.Current.PadStripe),
                    };
                    dot.MouseLeftButtonUp += (_, _) => { page = p; hovered = null; Render(); };
                    row.Children.Add(dot);
                }
                dots = row;
            }
            DockPanel.SetDock(dots, Dock.Right);
            line.Children.Add(dots);
        }
        var n = state!.Rows.Count;
        var text = pinned
            ? Loc.T("Angeheftet, nach dem nächsten Einfügen ⇧ loslassen", "Pinned. Let go of Shift to close after the next insert")
            : state.Filter.Length == 0 ? Loc.T("Tippen zum Suchen", "Type to search")
            : n == 1 ? Loc.T("1 Treffer", "1 result") : Loc.T($"{n} Treffer", $"{n} results");
        line.Children.Add(new TextBlock { Text = text, FontSize = 11, Foreground = pinned ? Theme.Accent : Theme.TextTertiary, VerticalAlignment = VerticalAlignment.Center, FontFamily = Theme.Font });
        return line;
    }

    void ShowPadMenu(FrameworkElement pad, PanelRow row)
    {
        if (row.FolderID != null || row.Action != null || row.Chain != null || row.Uri.Length == 0) return;
        var menu = new ContextMenu();
        var fav = new MenuItem { Header = model.IsFavorite(row) ? Loc.T("Aus Favoriten entfernen", "Remove from Favorites") : Loc.T("Zu Favoriten hinzufügen", "Add to Favorites") };
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
        // Insert another format of the same plugin (VST3 / VST2).
        var others = model.SearchIndex.Alternatives(row.UsageKey).Where(v => v.Uri != row.Uri).ToList();
        if (others.Count > 0)
        {
            menu.Items.Add(new Separator());
            foreach (var v in others)
            {
                var uri = v.Uri;
                var item = new MenuItem { Header = Loc.T($"Als {PluginVariants.Label(v)} einfügen", $"Insert as {PluginVariants.Label(v)}") };
                item.Click += (_, _) => { Hide(); model.InsertUris(new[] { uri }, row.UsageKey); };
                menu.Items.Add(item);
            }
        }
        menu.PlacementTarget = pad;
        menu.IsOpen = true;
    }

    /// <summary>After a menu change: same tab, same filter, fresh rows.</summary>
    void Rebuild()
    {
        if (state == null) return;
        var filter = state.Filter;
        state = new PanelState(model.Config, model.SearchIndex, state.SelectedTab, model.Usage.Counts);
        var e = System.Globalization.StringInfo.GetTextElementEnumerator(filter);
        while (e.MoveNext()) state.Handle(PanelKey.OfCharacter(e.GetTextElement()));
        Render();
        Reposition();
    }
}
