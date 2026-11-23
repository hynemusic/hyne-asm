using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>One page of the settings window. <see cref="Build"/> draws it from the current config.</summary>
abstract class Page
{
    protected readonly AppModel Model;
    protected readonly SettingsWindow Window;
    protected Page(AppModel model, SettingsWindow window) { Model = model; Window = window; }
    public abstract UIElement Build();
    /// <summary>Saves the config; the window redraws from the model's change event.</summary>
    protected void Changed() => Model.ConfigChanged();
    /// <summary>Keys pressed while the page is shown (Delete, Ctrl+G in the Library). True = handled.</summary>
    public virtual bool Key(KeyEventArgs e) => false;
}

/// <summary>The settings window, laid out like the Mac's: sidebar with the pages (glowing selection), Live status,
/// theme and language at the bottom; the page on the right.</summary>
sealed class SettingsWindow : Window
{
    readonly AppModel model;
    readonly Grid root = new();
    readonly ContentControl content = new();
    readonly List<(int Group, string Icon, string Title, Func<Page> Make)> pages;
    readonly Dictionary<int, Page> made = new();
    int current;
    bool redrawing;

    public SettingsWindow(AppModel model, int startPage = 0)
    {
        this.model = model;
        Title = Loc.T("HYNE ASM – Einstellungen", "HYNE ASM – Settings");
        Width = 1320; Height = 820; MinWidth = 1000; MinHeight = 600;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Icon = TrayIcon.ImageSource();
        pages = new()
        {
            (0, "", Loc.T("Bibliothek", "Library"), () => new LibraryPage(model, this)),
            (0, "", Loc.T("Profile", "Profiles"), () => new ProfilesPage(model, this)),
            (0, "", Loc.T("Suche formen", "Shape Search"), () => new SearchPage(model, this)),
            (1, "", Loc.T("Tastenkürzel", "Shortcuts"), () => new ShortcutsPage(model, this)),
            (1, "", Loc.T("Verhalten", "Behavior"), () => new BehaviorPage(model, this)),
            (2, "", Loc.T("Statistik", "Stats"), () => new StatsPage(model, this)),
        };
        current = Math.Clamp(startPage, 0, pages.Count - 1);
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(272) });
        root.ColumnDefinitions.Add(new ColumnDefinition());
        Grid.SetColumn(content, 1);
        Content = root;
        model.Changed += OnModelChanged;
        Closed += (_, _) => model.Changed -= OnModelChanged;
        PreviewKeyDown += (_, e) => { if (Page.Key(e)) e.Handled = true; };
        Redraw();
    }

    Page Page => made.TryGetValue(current, out var p) ? p : made[current] = pages[current].Make();

    void OnModelChanged() => Redraw();

    public void Select(int index) { current = index; Redraw(); }

    /// <summary>Win+G from the keyboard hook (Windows would otherwise open the Game Bar).</summary>
    public void GroupSelection() { if (Page is LibraryPage library) library.GroupSelection(); }

    /// <summary>Re-reads the config into the sidebar and the page (pages keep their own state, e.g. a search).</summary>
    public void Redraw()
    {
        if (redrawing) return;
        redrawing = true;
        try
        {
            FontFamily = Theme.Font;
            Background = UI.Canvas;
            UI.ThemeTitleBar(this);
            root.Children.Clear();
            root.Children.Add(Sidebar());
            content.Content = Page.Build();
            root.Children.Add(content);
        }
        finally { redrawing = false; }
    }

    UIElement Sidebar()
    {
        var list = new StackPanel { Margin = new Thickness(10, 16, 10, 10) };
        var brand = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(8, 0, 0, 30) };
        var logo = new Image { Source = TrayIcon.ImageSource(), Width = 38, Height = 38, Margin = new Thickness(0, 0, 12, 0) };
        RenderOptions.SetBitmapScalingMode(logo, BitmapScalingMode.HighQuality);
        brand.Children.Add(logo);
        var name = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        name.Children.Add(UI.Text("HYNE ASM", 17, weight: FontWeights.Bold));
        name.Children.Add(UI.Text("Ableton Shortcuts Manager", 12, Theme.TextSecondary));
        brand.Children.Add(name);
        list.Children.Add(brand);
        var group = 0;
        for (var i = 0; i < pages.Count; i++)
        {
            if (pages[i].Group != group) { group = pages[i].Group; list.Children.Add(new Border { Height = 18 }); }
            list.Children.Add(SidebarItem(i));
        }

        var bottom = new StackPanel { Margin = new Thickness(14, 0, 14, 14) };
        var status = new Grid { Margin = new Thickness(0, 0, 0, 12) };
        status.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(18) });
        status.ColumnDefinitions.Add(new ColumnDefinition());
        status.Children.Add(UI.Dot(model.IsConnected ? Color.FromRgb(0x4C, 0xCC, 0x80) : Color.FromRgb(0x88, 0x84, 0x7E), 8));
        var lines = new StackPanel();
        lines.Children.Add(UI.Text(model.IsConnected ? Loc.T("Mit Live verbunden", "Connected to Live") : Loc.T("Live nicht verbunden", "Live not connected"), 13, weight: FontWeights.SemiBold));
        lines.Children.Add(UI.Text(model.IsConnected
            ? $"Live {model.Hello?.LiveVersion} · {Loc.Number(model.Catalog.Items.Count)} " + Loc.T("Einträge", "items")
            : Loc.T("In Live ASMbridge wählen", "Select ASMbridge in Live"), 12.5, Theme.TextSecondary));
        Grid.SetColumn(lines, 1);
        status.Children.Add(lines);
        bottom.Children.Add(status);
        bottom.Children.Add(ThemePicker());
        bottom.Children.Add(LanguagePicker());

        var dock = new DockPanel { LastChildFill = true };
        DockPanel.SetDock(bottom, Dock.Bottom);
        dock.Children.Add(bottom);
        dock.Children.Add(UI.Scroll(list));
        return new Border { Background = UI.Sidebar, BorderBrush = Theme.Stroke, BorderThickness = new Thickness(0, 0, 1, 0), Child = dock };
    }

    UIElement SidebarItem(int index)
    {
        var selected = index == current;
        var (_, icon, title, _) = pages[index];
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        var tile = new Border
        {
            Width = 30, Height = 30, CornerRadius = new CornerRadius(Theme.Radius(7)), Background = selected ? UI.AccentTint(0.15) : Theme.Ink(0.06),
            Child = UI.Icon(icon, 14, selected ? Theme.Accent : Theme.TextSecondary),
        };
        ((TextBlock)tile.Child).HorizontalAlignment = HorizontalAlignment.Center;
        row.Children.Add(tile);
        var t = UI.Text(title, 16, weight: FontWeights.SemiBold);
        t.Margin = new Thickness(12, 0, 0, 0);
        row.Children.Add(t);
        var item = new Border
        {
            Child = row, Padding = new Thickness(6, 6, 8, 6), CornerRadius = new CornerRadius(Theme.Radius(9)), Cursor = Cursors.Hand,
            Background = selected ? UI.Raised : Brushes.Transparent, Margin = new Thickness(0, 2, 0, 2), BorderThickness = new Thickness(1.5),
            BorderBrush = Brushes.Transparent,
        };
        if (selected) UI.Glow(item);
        else
        {
            item.MouseEnter += (_, _) => item.Background = Theme.Ink(0.04);
            item.MouseLeave += (_, _) => item.Background = Brushes.Transparent;
        }
        item.MouseLeftButtonUp += (_, _) => Select(index);
        return item;
    }

    /// <summary>Theme card: a tiny preview of the panel in the theme, its name, opens the list of themes.</summary>
    UIElement ThemePicker()
    {
        var c = model.Config;
        var row = new DockPanel { LastChildFill = true };
        var chevrons = UI.Icon("", 11, Theme.TextTertiary);
        DockPanel.SetDock(chevrons, Dock.Right);
        row.Children.Add(chevrons);
        var preview = MiniTheme(c.Theme);
        DockPanel.SetDock(preview, Dock.Left);
        row.Children.Add(preview);
        var text = new StackPanel { Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(UI.Text(Loc.T("Design", "Theme"), 11.5, Theme.TextSecondary));
        text.Children.Add(UI.Text(c.Theme.Title(), 13.5, weight: FontWeights.SemiBold));
        row.Children.Add(text);
        var card = new Border
        {
            Child = row, Padding = new Thickness(10, 7, 10, 7), CornerRadius = new CornerRadius(Theme.Radius(9)), Background = UI.Raised,
            Cursor = Cursors.Hand, Margin = new Thickness(0, 0, 0, 12), BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1),
        };
        card.MouseLeftButtonUp += (_, _) => UI.Menu(card, Enum.GetValues<AppTheme>().Select(t =>
            new UI.MenuItem(t.Title() + "  ·  " + t.Subtitle(), () => { c.Theme = t; model.ConfigChanged(); }, Checked: t == c.Theme,
                Swatch: Palette.Make(t).Accent)).ToList(), atMouse: false);
        return card;
    }

    /// <summary>The Mac's little theme picture: a panel with two rows, a highlighted one and the accent.</summary>
    static FrameworkElement MiniTheme(AppTheme theme)
    {
        var p = Palette.Make(theme);
        var stack = new StackPanel { Margin = new Thickness(4, 5, 4, 5) };
        stack.Children.Add(new Border { Height = 4, Width = 14, CornerRadius = new CornerRadius(2), Background = Theme.B(p.Accent), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 3) });
        stack.Children.Add(new Border { Height = 5, CornerRadius = new CornerRadius(2), Background = Theme.B(p.Accent), Margin = new Thickness(0, 0, 0, 3) });
        stack.Children.Add(new Border { Height = 5, CornerRadius = new CornerRadius(2), Background = Theme.B(p.PanelRow) });
        return new Border { Width = 38, Height = 28, CornerRadius = new CornerRadius(5), Background = Theme.B(p.PanelSurface), BorderBrush = Theme.B(p.PanelStroke), BorderThickness = new Thickness(1), Child = stack };
    }

    UIElement LanguagePicker()
    {
        var c = model.Config;
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        var globe = UI.Icon("", 14, Theme.TextSecondary);
        globe.Margin = new Thickness(2, 0, 10, 0);
        row.Children.Add(globe);
        var title = c.Language switch { HyneAsm.Core.Language.De => "Deutsch", HyneAsm.Core.Language.En => "English", _ => Loc.T("Automatisch", "Automatic") };
        var pill = new StackPanel { Orientation = Orientation.Horizontal };
        pill.Children.Add(UI.Text(title, 13.5, weight: FontWeights.Medium));
        var chev = UI.Icon("", 10, Theme.TextTertiary);
        chev.Margin = new Thickness(14, 0, 0, 0);
        pill.Children.Add(chev);
        var box = new Border { Child = pill, Padding = new Thickness(10, 4, 8, 4), CornerRadius = new CornerRadius(Theme.Radius(6)), Background = UI.Raised, Cursor = Cursors.Hand };
        box.MouseLeftButtonUp += (_, _) => UI.Menu(box, new (string, HyneAsm.Core.Language?)[] { (Loc.T("Automatisch", "Automatic"), null), ("Deutsch", HyneAsm.Core.Language.De), ("English", HyneAsm.Core.Language.En) }
            .Select(o => new UI.MenuItem(o.Item1, () => { c.Language = o.Item2; model.ConfigChanged(); }, Checked: c.Language == o.Item2)).ToList(), atMouse: false);
        row.Children.Add(box);
        return row;
    }
}
