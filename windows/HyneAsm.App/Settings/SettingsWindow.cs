using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>One page of the settings window. <see cref="Build"/> draws it from the current config.</summary>
abstract class Page
{
    protected readonly AppModel Model;
    protected readonly SettingsWindow Window;
    protected Page(AppModel model, SettingsWindow window) { Model = model; Window = window; }
    public abstract UIElement Build();
    /// <summary>Saves the config and redraws the page.</summary>
    protected void Changed() => Model.ConfigChanged();
}

/// <summary>The settings window: a sidebar like the Mac's (pages, Live status) and the page on the right.</summary>
sealed class SettingsWindow : Window
{
    readonly AppModel model;
    readonly Grid root = new();
    readonly ContentControl content = new();
    readonly List<(string Group, string Icon, string Title, string Subtitle, Func<Page> Make)> pages;
    int current;
    Page? page;

    public SettingsWindow(AppModel model, int startPage = 0)
    {
        this.model = model;
        Title = Loc.T("HYNE ASM – Einstellungen", "HYNE ASM – Settings");
        Width = 1100; Height = 740; MinWidth = 900; MinHeight = 560;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Icon = TrayIcon.ImageSource();
        pages = new()
        {
            (Loc.T("Menü", "Menu"), "", Loc.T("Bibliothek", "Library"), Loc.T("Plugins & Kategorien", "Plugins & categories"), () => new LibraryPage(model, this)),
            (Loc.T("Menü", "Menu"), "", Loc.T("Profile", "Profiles"), Loc.T("Menüs wechseln & sichern", "Switch & save menus"), () => new ProfilesPage(model, this)),
            (Loc.T("Menü", "Menu"), "", Loc.T("Suche formen", "Shape Search"), Loc.T("Anpinnen & ausblenden", "Pin & hide results"), () => new SearchPage(model, this)),
            (Loc.T("Einrichtung", "Setup"), "", Loc.T("Tastenkürzel", "Shortcuts"), Loc.T("Fenster, Suche, Panel", "Windows, search, panel"), () => new ShortcutsPage(model, this)),
            (Loc.T("Einrichtung", "Setup"), "", Loc.T("Verhalten", "Behavior"), Loc.T("Panel, Einfügen, Geräte", "Panel, inserting, devices"), () => new BehaviorPage(model, this)),
            (Loc.T("Einblicke", "Insights"), "", Loc.T("Statistik", "Stats"), Loc.T("Was du am meisten nutzt", "What you use most"), () => new StatsPage(model, this)),
        };
        current = Math.Clamp(startPage, 0, pages.Count - 1);
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(232) });
        root.ColumnDefinitions.Add(new ColumnDefinition());
        Grid.SetColumn(content, 1);
        Content = root;
        model.Changed += OnModelChanged;
        Closed += (_, _) => model.Changed -= OnModelChanged;
        Select(current);
    }

    void OnModelChanged() { if (!redrawing) Redraw(); }
    bool redrawing;

    public void Select(int index)
    {
        current = index;
        page = pages[index].Make();
        Redraw();
    }

    /// <summary>Re-reads the config into the sidebar and the page (keeps the page's own state, e.g. a search).</summary>
    public void Redraw()
    {
        if (redrawing) return;
        redrawing = true;
        try
        {
            FontFamily = Theme.Font;
            Background = UI.Canvas;
            root.Children.Clear();
            root.Children.Add(Sidebar());
            content.Content = page!.Build();
            root.Children.Add(content);
        }
        finally { redrawing = false; }
    }

    UIElement Sidebar()
    {
        var list = new StackPanel { Margin = new Thickness(14, 18, 14, 14) };
        var brand = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(6, 0, 0, 14) };
        var logo = new Image { Source = TrayIcon.ImageSource(), Width = 28, Height = 28, Margin = new Thickness(0, 0, 10, 0) };
        brand.Children.Add(logo);
        var name = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        name.Children.Add(UI.Text("HYNE ASM", 15, weight: FontWeights.Bold));
        name.Children.Add(UI.Text("Ableton Shortcuts Manager", 10.5, Theme.TextTertiary));
        brand.Children.Add(name);
        list.Children.Add(brand);
        string? group = null;
        for (var i = 0; i < pages.Count; i++)
        {
            var p = pages[i];
            if (p.Group != group) { group = p.Group; list.Children.Add(UI.Section(group)); }
            list.Children.Add(SidebarItem(i, p.Icon, p.Title, p.Subtitle));
        }
        var status = new StackPanel { Margin = new Thickness(14, 0, 14, 16), VerticalAlignment = VerticalAlignment.Bottom };
        var line = new StackPanel { Orientation = Orientation.Horizontal };
        line.Children.Add(UI.Dot(model.IsConnected ? System.Windows.Media.Color.FromRgb(0x4C, 0xCC, 0x80) : System.Windows.Media.Color.FromRgb(0x88, 0x88, 0x88), 8));
        var t = UI.Text(model.IsConnected ? Loc.T("Mit Live verbunden", "Connected to Live") : Loc.T("Live nicht verbunden", "Live not connected"), 12, weight: FontWeights.SemiBold);
        t.Margin = new Thickness(8, 0, 0, 0);
        line.Children.Add(t);
        status.Children.Add(line);
        status.Children.Add(UI.Caption(model.IsConnected
            ? $"Live {model.Hello?.LiveVersion} · {Loc.Number(model.Catalog.Items.Count)} " + Loc.T("Einträge", "items")
            : Loc.T("In Live ASMbridge wählen", "Select ASMbridge in Live")));
        var dock = new DockPanel { LastChildFill = true };
        DockPanel.SetDock(status, Dock.Bottom);
        dock.Children.Add(status);
        dock.Children.Add(UI.Scroll(list));
        return new Border { Background = UI.Sidebar, BorderBrush = Theme.Stroke, BorderThickness = new Thickness(0, 0, 1, 0), Child = dock };
    }

    UIElement SidebarItem(int index, string icon, string title, string subtitle)
    {
        var selected = index == current;
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(new TextBlock { Text = icon, FontFamily = Theme.Icons, FontSize = 15, Width = 22, Foreground = selected ? Theme.Accent : Theme.TextSecondary, VerticalAlignment = VerticalAlignment.Center });
        var text = new StackPanel { Margin = new Thickness(8, 0, 0, 0) };
        text.Children.Add(UI.Text(title, 13, weight: FontWeights.SemiBold));
        text.Children.Add(UI.Text(subtitle, 11, Theme.TextTertiary));
        row.Children.Add(text);
        var item = new Border
        {
            Child = row, Padding = new Thickness(8, 6, 8, 6), CornerRadius = new CornerRadius(Theme.Radius(8)), Cursor = Cursors.Hand,
            Background = selected ? UI.Hover : System.Windows.Media.Brushes.Transparent, Margin = new Thickness(0, 1, 0, 1),
        };
        item.MouseLeftButtonUp += (_, _) => Select(index);
        return item;
    }
}
