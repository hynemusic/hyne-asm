using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Page "Library": categories on the left, the selected category's entries in the middle (folders, chains,
/// Live commands, icons, colours, names, order), Live's plugin list on the right to add from.</summary>
sealed class LibraryPage : Page
{
    Guid? selectedCategory;
    string browserSearch = "";
    ListBox? browser;

    public LibraryPage(AppModel model, SettingsWindow window) : base(model, window) { }

    Category? Selected => Model.Config.Categories.FirstOrDefault(c => c.Id == selectedCategory) ?? Model.Config.Categories.FirstOrDefault();

    public override UIElement Build()
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(230) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(340) });
        var categories = Categories();
        var entries = Entries();
        var browse = Browser();
        Grid.SetColumn(entries, 1);
        Grid.SetColumn(browse, 2);
        grid.Children.Add(categories);
        grid.Children.Add(entries);
        grid.Children.Add(browse);
        return grid;
    }

    // MARK: Categories

    UIElement Categories()
    {
        var list = new StackPanel { Margin = new Thickness(16, 18, 10, 16) };
        list.Children.Add(UI.Title(Loc.T("Bibliothek", "Library")));
        list.Children.Add(UI.Section(Loc.T("Kategorien", "Categories")));
        var cats = Model.Config.Categories;
        var selected = Selected;
        for (var i = 0; i < cats.Count; i++)
        {
            var c = cats[i];
            var index = i;
            var row = new DockPanel { LastChildFill = true };
            var count = UI.Text(c.Entries.Count.ToString(), 11, Theme.TextTertiary);
            DockPanel.SetDock(count, Dock.Right);
            row.Children.Add(count);
            if (c.IsFavorites)
            {
                var star = new TextBlock { Text = "", FontFamily = Theme.Icons, FontSize = 10, Foreground = Theme.Accent, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) };
                DockPanel.SetDock(star, Dock.Left);
                row.Children.Add(star);
            }
            row.Children.Add(UI.Text(c.Name, 13, weight: c.Id == selected?.Id ? FontWeights.SemiBold : FontWeights.Normal));
            var item = new Border
            {
                Child = row, Padding = new Thickness(10, 6, 10, 6), CornerRadius = new CornerRadius(Theme.Radius(7)), Cursor = Cursors.Hand,
                Background = c.Id == selected?.Id ? UI.Hover : Brushes.Transparent, Margin = new Thickness(0, 1, 0, 1),
            };
            item.MouseLeftButtonUp += (_, _) => { selectedCategory = c.Id; Window.Redraw(); };
            item.MouseRightButtonUp += (_, e) =>
            {
                e.Handled = true;
                var actions = new List<(string, Action?)>
                {
                    (Loc.T("Umbenennen …", "Rename …"), () => { if (UI.Ask(Window, Loc.T("Kategorie umbenennen", "Rename category"), c.Name) is { } n) { Model.Config.RenameCategory(c.Id, n); Changed(); } }),
                    (Loc.T("Nach oben", "Move up"), index > 0 ? () => { Model.Config.MoveCategory(index, index - 1); Changed(); } : null),
                    (Loc.T("Nach unten", "Move down"), index < cats.Count - 1 ? () => { Model.Config.MoveCategory(index, index + 1); Changed(); } : null),
                };
                if (!c.IsFavorites)
                    actions.Add((Loc.T("Löschen", "Delete"), () =>
                    {
                        if (UI.Confirm(Window, "HYNE ASM", Loc.T($"„{c.Name}“ mit {c.Entries.Count} Einträgen löschen?", $"Delete “{c.Name}” with {c.Entries.Count} entries?")))
                        { Model.Config.DeleteCategory(c.Id); selectedCategory = null; Changed(); }
                    }));
                UI.Menu(item, actions);
            };
            list.Children.Add(item);
        }
        var add = UI.Button(Loc.T("Kategorie", "Category"), () =>
        {
            if (UI.Ask(Window, Loc.T("Neue Kategorie", "New category"), Loc.T("Neue Kategorie", "New category")) is { } n)
            { selectedCategory = Model.Config.AddCategory(n); Changed(); }
        }, icon: "");
        add.Margin = new Thickness(0, 10, 0, 0);
        add.HorizontalAlignment = HorizontalAlignment.Left;
        list.Children.Add(add);
        list.Children.Add(UI.Caption(Loc.T("Rechtsklick: umbenennen, verschieben, löschen.", "Right-click: rename, move, delete.")));
        return new Border { Child = UI.Scroll(list), BorderBrush = Theme.Stroke, BorderThickness = new Thickness(0, 0, 1, 0) };
    }

    // MARK: Entries

    UIElement Entries()
    {
        var category = Selected;
        var panel = new StackPanel { Margin = new Thickness(18, 18, 18, 18) };
        if (category == null) return panel;
        var head = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 0, 0, 6) };
        var tools = new StackPanel { Orientation = Orientation.Horizontal };
        tools.Children.Add(UI.Button(Loc.T("Ordner", "Folder"), () =>
        {
            if (UI.Ask(Window, Loc.T("Neuer Ordner", "New folder"), Loc.T("Ordner", "Folder")) is { } n) { Model.Config.AddFolder(n, category.Id); Changed(); }
        }, icon: ""));
        Border? live = null;
        live = UI.Button(Loc.T("Live-Befehl", "Live command"), () => AddLiveCommand(live!, category.Id, null), icon: "");
        tools.Children.Add(live);
        Border? more = null;
        more = UI.Button("", () => UI.Menu(more!, new (string, Action?)[]
        {
            (Loc.T("Menü importieren (.hmlmenu) …", "Import menu (.hmlmenu) …"), () => TrayIcon.ImportMenu(Model)),
            (Loc.T("Menü exportieren …", "Export menu …"), () => TrayIcon.ExportMenu(Model)),
            (Loc.T("LES-Menü importieren …", "Import LES menu …"), () => TrayIcon.ImportLES(Model)),
            ("-", null),
            (Loc.T("Version sichern …", "Save version …"), SaveVersion),
            (Loc.T("Versionen …", "Versions …"), () => new VersionsWindow(Model) { Owner = Window }.ShowDialog()),
        }), icon: "", tip: Loc.T("Import, Export, Versionen", "Import, export, versions"));
        tools.Children.Add(more);
        DockPanel.SetDock(tools, Dock.Right);
        head.Children.Add(tools);
        var title = new StackPanel();
        title.Children.Add(UI.Title(category.Name));
        title.Children.Add(UI.Caption(Loc.T("Doppelklick auf ein Plugin rechts fügt es hier hinzu. Rechtsklick auf einen Eintrag: Name, Icon, Farbe, Kürzel, Ordner.",
                                            "Double-click a plugin on the right to add it here. Right-click an entry: name, icon, colour, shortcut, folder.")));
        head.Children.Add(title);
        panel.Children.Add(head);
        if (category.Entries.Count == 0)
            panel.Children.Add(UI.Card(UI.Caption(Loc.T("Noch leer. Such rechts nach Plugins, Geräten oder Presets und füg sie per Doppelklick hinzu.",
                                                         "Still empty. Search for plugins, devices or presets on the right and double-click to add them."))));
        for (var i = 0; i < category.Entries.Count; i++)
        {
            var e = category.Entries[i];
            panel.Children.Add(EntryRow(category, e, null, i, category.Entries.Count));
            if (e.Children is { } kids)
                for (var k = 0; k < kids.Count; k++) panel.Children.Add(EntryRow(category, kids[k], e, k, kids.Count));
        }
        return UI.Scroll(panel);
    }

    FrameworkElement EntryRow(Category category, Entry e, Entry? folder, int index, int count)
    {
        var color = Theme.LabelColor(Model.Config.ColorID(e));
        var line = new DockPanel { LastChildFill = true };
        var icon = Theme.Icon(e.IconID, 16, color is { } c ? Theme.B(c) : e.IsFolder ? Theme.Accent : Theme.TextSecondary);
        icon.Width = 26;
        DockPanel.SetDock(icon, Dock.Left);
        line.Children.Add(icon);
        var right = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        if (!e.IsFolder && e.Action == null && e.Chain == null && Model.Config.ItemShortcutFor(Item(e)) is { } sc)
            right.Children.Add(UI.Text(Keys.Describe(sc.Combo), 11, Theme.TextTertiary));
        if (e.IsFolder) right.Children.Add(UI.Text(Loc.T($"{e.Children!.Count} Einträge", $"{e.Children!.Count} entries"), 11, Theme.TextTertiary));
        var up = UI.IconButton("", () => { Model.Config.MoveEntry(category.Id, folder?.Id, index, index - 1); Changed(); }, Loc.T("Nach oben", "Move up"));
        var down = UI.IconButton("", () => { Model.Config.MoveEntry(category.Id, folder?.Id, index, index + 1); Changed(); }, Loc.T("Nach unten", "Move down"));
        up.Margin = new Thickness(10, 0, 4, 0);
        up.IsEnabled = index > 0; up.Opacity = index > 0 ? 1 : 0.3;
        down.IsEnabled = index < count - 1; down.Opacity = index < count - 1 ? 1 : 0.3;
        right.Children.Add(up);
        right.Children.Add(down);
        DockPanel.SetDock(right, Dock.Right);
        line.Children.Add(right);
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 0, 0) };
        text.Children.Add(UI.Text(e.Title, 13, weight: FontWeights.SemiBold));
        var detail = e.IsFolder ? Loc.T("Ordner", "Folder")
            : e.Action != null ? Loc.T("Live-Befehl", "Live command")
            : e.Chain != null ? Loc.T("Kette: ", "Chain: ") + string.Join(" → ", e.Chain.Select(s => s.Name))
            : string.Join(" / ", e.Path.Prepend(e.DisplayName != null ? e.Name : "").Where(s => s.Length > 0));
        if (detail.Length > 0) text.Children.Add(UI.Text(detail, 11, Theme.TextTertiary));
        line.Children.Add(text);
        var row = new Border
        {
            Child = line, Padding = new Thickness(8, 6, 8, 6), CornerRadius = new CornerRadius(Theme.Radius(8)), Background = UI.Raised,
            Margin = new Thickness(folder != null ? 30 : 0, 2, 0, 2), BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1),
        };
        if (color is { } stripe) { row.BorderBrush = Theme.B(stripe); row.BorderThickness = new Thickness(3, 1, 1, 1); }
        row.MouseRightButtonUp += (_, ev) => { ev.Handled = true; EntryMenu(row, category, e, folder); };
        row.MouseLeftButtonDown += (_, ev) => { if (ev.ClickCount == 2) Rename(category, e); };
        return row;
    }

    static PluginItem Item(Entry e) => new(e.Uri, e.Name, e.Source, e.Path);

    void Rename(Category category, Entry e)
    {
        if (e.IsFolder)
        {
            if (UI.Ask(Window, Loc.T("Ordner umbenennen", "Rename folder"), e.Name) is { } n) { Model.Config.RenameFolder(e.Id, category.Id, n); Changed(); }
            return;
        }
        var name = UI.Ask(Window, Loc.T("Anzeigename (leer = Originalname)", "Display name (empty = original name)"), e.Title);
        if (name == null) return;
        Model.Config.SetDisplayName(name == e.Name ? null : name, e.Id, category.Id);
        Changed();
    }

    void EntryMenu(FrameworkElement at, Category category, Entry e, Entry? folder)
    {
        var items = new List<(string, Action?)>
        {
            (Loc.T("Umbenennen …", "Rename …"), () => Rename(category, e)),
            (Loc.T("Icon …", "Icon …"), () => IconPicker(at, category, e)),
            (Loc.T("Farbe …", "Colour …"), () => ColorPicker(at, category, e)),
        };
        if (!e.IsFolder && e.Action == null && e.Chain == null)
            items.Add((Loc.T("Tastenkürzel …", "Shortcut …"), () => ShortcutDialog.Show(Window, Model, Item(e), e.Title)));
        if (!e.IsFolder)
        {
            var folders = category.Entries.Where(x => x.IsFolder && x.Id != folder?.Id).ToList();
            foreach (var f in folders)
            {
                var id = f.Id;
                items.Add((Loc.T($"In Ordner „{f.Title}“", $"Into folder “{f.Title}”"), () => { Model.Config.MoveEntry(e.Id, id, category.Id); Changed(); }));
            }
            if (folder != null) items.Add((Loc.T("Aus dem Ordner nehmen", "Take out of the folder"), () => { Model.Config.MoveEntry(e.Id, null, category.Id); Changed(); }));
        }
        else
        {
            Border? anchor = null;
            items.Add((Loc.T("Live-Befehl in diesen Ordner …", "Live command into this folder …"), () => AddLiveCommand(at, category.Id, e.Id)));
            items.Add((Loc.T("Ordner auflösen", "Dissolve folder"), () => { Model.Config.DissolveFolder(e.Id, category.Id); Changed(); }));
            _ = anchor;
        }
        items.Add(("-", null));
        items.Add((Loc.T("Entfernen", "Remove"), () => { Model.Config.RemoveEntry(e.Id, category.Id); Changed(); }));
        UI.Menu(at, items);
    }

    void IconPicker(FrameworkElement at, Category category, Entry e)
    {
        var wrap = new WrapPanel { Width = 330, Margin = new Thickness(8) };
        var popup = new Popup { PlacementTarget = at, Placement = PlacementMode.Bottom, StaysOpen = false, AllowsTransparency = true };
        foreach (var id in IconCatalog.AllIDs)
        {
            var icon = id;
            var cell = new Border
            {
                Width = 36, Height = 36, CornerRadius = new CornerRadius(6), Cursor = Cursors.Hand, ToolTip = id, Margin = new Thickness(2),
                Background = id == e.IconID ? Theme.Accent : UI.Hover, Child = Theme.Icon(id, 16, id == e.IconID ? Theme.OnAccent : Theme.TextPrimary),
            };
            cell.MouseLeftButtonUp += (_, _) => { popup.IsOpen = false; Model.Config.SetIcon(icon, e.Id, category.Id); Changed(); };
            wrap.Children.Add(cell);
        }
        popup.Child = new Border { Background = UI.Surface, BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(10), Child = wrap };
        popup.IsOpen = true;
    }

    void ColorPicker(FrameworkElement at, Category category, Entry e)
    {
        var items = new List<(string, Action?)> { (Loc.T("Keine (Regel folgen)", "None (follow the rules)"), () => { Model.Config.SetColor(null, e.Id, category.Id); Changed(); }) };
        foreach (var c in ColorPalette.All)
        {
            var id = c.Id;
            items.Add(("● " + c.Label, () => { Model.Config.SetColor(id, e.Id, category.Id); Changed(); }));
        }
        UI.Menu(at, items);
    }

    void AddLiveCommand(FrameworkElement at, Guid category, Guid? folder)
    {
        var items = new List<(string, Action?)>();
        foreach (var kind in Enum.GetValues<LiveActionKind>())
        {
            var k = kind;
            items.Add((k.Title(), () =>
            {
                var action = new LiveAction(k);
                if (k.TakesValue())
                {
                    var prompt = k == LiveActionKind.SetTempo ? Loc.T("Tempo (BPM)", "Tempo (BPM)") : Loc.T("Taktart, z. B. 3/4", "Time signature, e.g. 3/4");
                    var initial = k == LiveActionKind.SetTempo ? "120" : "4/4";
                    if (UI.Ask(Window, prompt, initial) is not { } text) return;
                    if (k == LiveActionKind.SetTempo && double.TryParse(text.Replace(',', '.'), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var bpm))
                        action = new LiveAction(k, Math.Clamp(bpm, 20, 999));
                    else if (k == LiveActionKind.SetTimeSignature && text.Split('/') is [var n, var d] && int.TryParse(n, out var num) && int.TryParse(d, out var den))
                        action = new LiveAction(k, num, den);
                    else return;
                }
                Model.Config.AddAction(action, category, folder);
                Changed();
            }));
        }
        UI.Menu(at, items);
    }

    void SaveVersion()
    {
        if (UI.Ask(Window, Loc.T("Version sichern als", "Save version as"), DateTime.Now.ToString("g")) is not { } name) return;
        Model.Versions.Save(name, Model.Config.Categories, isAutomatic: false);
        Model.Hud.Show(Loc.T("Version gesichert", "Version saved"));
    }

    // MARK: Live's plugin list

    sealed record BrowserRow(string Label, PluginItem? Item, bool IsHeader, string Detail);

    UIElement Browser()
    {
        var panel = new DockPanel { Margin = new Thickness(12, 18, 16, 16), LastChildFill = true };
        var top = new StackPanel();
        top.Children.Add(UI.Text(Loc.T("Aus Live hinzufügen", "Add from Live"), 15, weight: FontWeights.SemiBold));
        var search = UI.TextBox(browserSearch, Loc.T("Plugins, Geräte, Presets suchen", "Search plugins, devices, presets"));
        search.Margin = new Thickness(0, 8, 0, 8);
        top.Children.Add(search);
        DockPanel.SetDock(top, Dock.Top);
        panel.Children.Add(top);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0) };
        buttons.Children.Add(UI.Button(Loc.T("Hinzufügen", "Add"), AddSelected, primary: true, icon: ""));
        buttons.Children.Add(UI.Button(Loc.T("Als Kette", "As chain"), AddChain, icon: "",
            tip: Loc.T("Mehrere markierte Einträge (Strg+Klick) werden nacheinander eingefügt.", "Several selected items (Ctrl+click) are inserted one after the other.")));
        buttons.Children.Add(UI.IconButton("", Model.RefreshCatalog, Loc.T("Live-Liste neu laden", "Reload Live's list")));
        DockPanel.SetDock(buttons, Dock.Bottom);
        panel.Children.Add(buttons);

        browser = new ListBox
        {
            SelectionMode = SelectionMode.Extended, Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = Theme.TextPrimary,
        };
        VirtualizingPanel.SetIsVirtualizing(browser, true);
        ScrollViewer.SetHorizontalScrollBarVisibility(browser, ScrollBarVisibility.Disabled);
        browser.ItemTemplate = RowTemplate();
        browser.ItemContainerStyle = ContainerStyle();
        Fill(browser, browserSearch);
        browser.MouseDoubleClick += (_, _) => AddSelected();
        search.TextChanged += (_, _) => { browserSearch = search.Text; Fill(browser, browserSearch); };
        panel.Children.Add(Model.Catalog.Items.Count == 0
            ? UI.Caption(Loc.T("Noch keine Liste – verbinde Live mit ASMbridge.", "No list yet – connect Live with ASMbridge."))
            : browser);
        return new Border { Child = panel, BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1, 0, 0, 0), Background = UI.Surface };
    }

    void Fill(ListBox list, string search)
    {
        var rows = new List<BrowserRow>();
        foreach (var g in PluginGrouping.Groups(Model.Catalog.Items, search))
        {
            rows.Add(new BrowserRow(g.Title, null, true, ""));
            foreach (var i in g.Items.Take(search.Length > 0 ? 200 : 400)) rows.Add(new BrowserRow(i.Name, i, false, PluginGrouping.FormatLabel(i)));
        }
        list.ItemsSource = rows;
    }

    static DataTemplate RowTemplate()
    {
        var dock = new FrameworkElementFactory(typeof(DockPanel));
        var detail = new FrameworkElementFactory(typeof(TextBlock));
        detail.SetBinding(TextBlock.TextProperty, new Binding(nameof(BrowserRow.Detail)));
        detail.SetValue(TextBlock.FontSizeProperty, 11.0);
        detail.SetValue(TextBlock.ForegroundProperty, Theme.TextTertiary);
        detail.SetValue(DockPanel.DockProperty, Dock.Right);
        detail.SetValue(FrameworkElement.MarginProperty, new Thickness(8, 0, 0, 0));
        dock.AppendChild(detail);
        var label = new FrameworkElementFactory(typeof(TextBlock));
        label.SetBinding(TextBlock.TextProperty, new Binding(nameof(BrowserRow.Label)));
        label.SetValue(TextBlock.TextTrimmingProperty, TextTrimming.CharacterEllipsis);
        dock.AppendChild(label);
        return new DataTemplate { VisualTree = dock };
    }

    static Style ContainerStyle()
    {
        var style = new Style(typeof(ListBoxItem));
        style.Setters.Add(new Setter(Control.ForegroundProperty, Theme.TextPrimary));
        style.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(6, 3, 6, 3)));
        style.Setters.Add(new Setter(Control.FontSizeProperty, 12.5));
        var header = new DataTrigger { Binding = new Binding(nameof(BrowserRow.IsHeader)), Value = true };
        header.Setters.Add(new Setter(Control.FontWeightProperty, FontWeights.SemiBold));
        header.Setters.Add(new Setter(Control.ForegroundProperty, Theme.Accent));
        header.Setters.Add(new Setter(UIElement.FocusableProperty, false));
        header.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(4, 10, 4, 3)));
        style.Triggers.Add(header);
        return style;
    }

    List<PluginItem> SelectedItems() =>
        browser?.SelectedItems.Cast<BrowserRow>().Where(r => r.Item != null).Select(r => r.Item!).ToList() ?? new();

    void AddSelected()
    {
        if (Selected is not { } category) return;
        var items = SelectedItems();
        if (items.Count == 0) return;
        foreach (var item in items) Model.Config.AddEntry(item, category.Id);
        Changed();
        Model.Hud.Show(Loc.T($"{items.Count} zu „{category.Name}“ hinzugefügt", $"{items.Count} added to “{category.Name}”"));
    }

    void AddChain()
    {
        if (Selected is not { } category) return;
        var items = SelectedItems();
        if (items.Count < 2) { Model.Hud.Show(Loc.T("Mehrere Einträge mit Strg+Klick markieren", "Select several items with Ctrl+click")); return; }
        if (UI.Ask(Window, Loc.T("Name der Kette", "Chain name"), string.Join(" + ", items.Select(i => i.Name).Take(3))) is not { } name) return;
        Model.Config.AddChain(name, items, category.Id);
        Changed();
    }
}

/// <summary>Saved states of the menu: restore or delete (automatic ones are made before every import or restore).</summary>
sealed class VersionsWindow : Window
{
    public VersionsWindow(AppModel model)
    {
        Title = Loc.T("Menü-Versionen", "Menu versions");
        Width = 520; Height = 460;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = UI.Surface;
        FontFamily = Theme.Font;
        ShowInTaskbar = false;
        var list = new StackPanel { Margin = new Thickness(18) };
        void Fill()
        {
            list.Children.Clear();
            list.Children.Add(UI.Title(Loc.T("Versionen", "Versions")));
            List<MenuVersion> versions;
            try { versions = model.Versions.List(); } catch (Exception) { versions = new(); }
            if (versions.Count == 0) list.Children.Add(UI.Caption(Loc.T("Noch keine Versionen.", "No versions yet.")));
            foreach (var v in versions)
            {
                var buttons = new StackPanel { Orientation = Orientation.Horizontal };
                buttons.Children.Add(UI.Button(Loc.T("Wiederherstellen", "Restore"), () =>
                {
                    if (!UI.Confirm(this, "HYNE ASM", Loc.T($"Menü auf „{v.Name}“ zurücksetzen? Der jetzige Stand wird vorher gesichert.", $"Reset the menu to “{v.Name}”? The current state is saved first."))) return;
                    model.RestoreVersion(v);
                    Fill();
                }));
                buttons.Children.Add(UI.IconButton("", () => { model.Versions.Delete(v.Id); Fill(); }, Loc.T("Löschen", "Delete")));
                list.Children.Add(UI.Row(v.Name, $"{v.Date.ToLocalTime():g} · {v.CategoryCount} " + Loc.T("Kategorien", "categories") + $" · {v.EntryCount} " + Loc.T("Einträge", "entries") + (v.IsAutomatic ? " · " + Loc.T("automatisch", "automatic") : ""), buttons));
            }
        }
        Fill();
        Content = UI.Scroll(list);
    }
}
