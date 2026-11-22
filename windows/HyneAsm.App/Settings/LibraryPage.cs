using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Page "Library", laid out like the Mac's: Live's plugins & presets on the left (a tree to add from),
/// the categories in the middle, the selected category as a panel preview on the right.
/// Double-click or drag to add; Shift/Ctrl pick several; drag pads to reorder; right-click for name, icon, colour.</summary>
sealed class LibraryPage : Page
{
    const string ItemsFormat = "HyneAsm.Items", EntriesFormat = "HyneAsm.Entries";

    Guid? selectedCategory;
    Guid? openFolder;
    string search = "";
    readonly HashSet<string> expanded = new();
    readonly List<object> browserSelection = new();   // PluginItem or LiveActionKind
    object? browserAnchor;
    readonly HashSet<Guid> selectedEntries = new();
    Guid? entryAnchor;
    bool padPreview = true;
    TextBox? searchBox;
    FrameworkElement? searchField;
    readonly ScrollViewer browserScroll = UI.Scroll(new StackPanel());
    readonly ScrollViewer previewScroll = UI.Scroll(new StackPanel());
    Point dragStart;

    public LibraryPage(AppModel model, SettingsWindow window) : base(model, window) { }

    Category? Selected => Model.Config.Categories.FirstOrDefault(c => c.Id == selectedCategory) ?? Model.Config.Categories.FirstOrDefault();

    public override UIElement Build()
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.25, GridUnitType.Star), MinWidth = 320 });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.8, GridUnitType.Star), MinWidth = 220 });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 300 });
        var browser = Browser();
        var categories = Categories();
        var preview = Preview();
        Grid.SetColumn(categories, 1);
        Grid.SetColumn(preview, 2);
        grid.Children.Add(browser);
        grid.Children.Add(categories);
        grid.Children.Add(preview);
        return grid;
    }

    static FrameworkElement Column(UIElement head, UIElement body, string? footer, bool divider = true)
    {
        var dock = new DockPanel { LastChildFill = true, Margin = new Thickness(18, 22, 18, 12) };
        DockPanel.SetDock(head, Dock.Top);
        dock.Children.Add(head);
        if (footer != null)
        {
            var foot = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 10, 0, 0) };
            var i = UI.Icon("", 11, Theme.TextTertiary);
            i.Margin = new Thickness(0, 0, 6, 0);
            foot.Children.Add(i);
            foot.Children.Add(UI.Text(footer, 12, Theme.TextTertiary));
            DockPanel.SetDock(foot, Dock.Bottom);
            dock.Children.Add(foot);
        }
        dock.Children.Add(body);
        return new Border { Child = dock, BorderBrush = Theme.Stroke, BorderThickness = new Thickness(0, 0, divider ? 1 : 0, 0) };
    }

    static FrameworkElement Head(string title, string? count, params UIElement[] tools)
    {
        var line = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 0, 0, 14), Height = 30 };
        var right = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var t in tools) right.Children.Add(t);
        DockPanel.SetDock(right, Dock.Right);
        line.Children.Add(right);
        var left = new StackPanel { Orientation = Orientation.Horizontal };
        left.Children.Add(UI.Text(title, 16, weight: FontWeights.Bold));
        if (count != null) { var c = UI.Text(count, 13, Theme.TextTertiary, FontWeights.SemiBold); c.Margin = new Thickness(10, 0, 0, 0); left.Children.Add(c); }
        line.Children.Add(left);
        return line;
    }

    // MARK: Plugins & Presets (left)

    sealed record BrowserGroup(string Key, string Title, string Glyph, List<object> Items);

    List<(string Section, List<BrowserGroup> Groups)> Sections()
    {
        var live = new List<BrowserGroup>();
        var actions = Enum.GetValues<LiveActionKind>().Cast<object>()
            .Where(k => search.Length == 0 || SearchMatcher.Score(((LiveActionKind)k).Title(), search) != null).ToList();
        if (actions.Count > 0) live.Add(new BrowserGroup("live-actions", Loc.T("Live-Befehle", "Live Actions"), "", actions));
        var presets = new List<BrowserGroup>();
        var devices = new List<BrowserGroup>();
        var plugins = new List<BrowserGroup>();
        foreach (var g in PluginGrouping.Groups(Model.Catalog.Items, search))
        {
            var items = g.Items.Cast<object>().ToList();
            if (g.Title.StartsWith(PresetFormat.GroupPrefix)) presets.Add(new BrowserGroup(g.Title, g.Title[PresetFormat.GroupPrefix.Length..], "", items));
            else if (g.Title.StartsWith("Live · ")) devices.Add(new BrowserGroup(g.Title, g.Title["Live · ".Length..], "", items));
            else plugins.Add(new BrowserGroup(g.Title, g.Title, "", items));
        }
        return new() { ("Live", live), (Loc.T("Eigene Presets", "Your Presets"), presets), (Loc.T("Live-Devices", "Live Devices"), devices), ("Plugins", plugins) };
    }

    FrameworkElement Browser()
    {
        if (searchField == null)
        {
            var (f, box) = UI.SearchField(search, Loc.T("Plugins und Presets suchen", "Search plugins and presets"));
            searchField = f;
            searchBox = box;
            box.TextChanged += (_, _) => { search = box.Text; RefreshBrowser(top: true); };
        }
        var field = searchField;
        if (field.Parent is Panel old) old.Children.Remove(field);
        var head = new StackPanel();
        head.Children.Add(Head(Loc.T("Plugins & Presets", "Plugins & Presets"), Loc.Number(Model.Catalog.Items.Count),
            UI.IconButton("", Model.RefreshCatalog, Loc.T("Live-Liste neu laden", "Reload Live's list"))));
        head.Children.Add(field);
        field.Margin = new Thickness(0, 0, 0, 12);

        RefreshBrowser();
        Detach(browserScroll);
        return Column(head, browserScroll, Loc.T("Doppelklick oder ziehen zum Hinzufügen. Umschalt oder Strg für mehrere.", "Double-click or drag to add. Hold Shift or Ctrl to pick several."));
    }

    static void Detach(FrameworkElement e)
    {
        if (e.Parent is Panel p) p.Children.Remove(e);
        else if (e.Parent is Decorator d) d.Child = null;
        else if (e.Parent is ContentControl c) c.Content = null;
    }

    /// <summary>Rebuilds the list only (keeps the search field focused and the scroll position).</summary>
    void RefreshBrowser(bool top = false)
    {
        var offset = top ? 0 : browserScroll.VerticalOffset;
        var list = new StackPanel();
        if (Model.Catalog.Items.Count == 0)
            list.Children.Add(UI.Caption(Loc.T("Noch keine Liste – verbinde Live mit ASMbridge.", "No list yet – connect Live with ASMbridge.")));
        var visible = new List<object>();   // in display order, for Shift ranges
        foreach (var (section, groups) in Sections())
        {
            if (groups.Count == 0) continue;
            var label = UI.Text(section, 12.5, Theme.TextTertiary, FontWeights.SemiBold);
            label.Margin = new Thickness(6, 12, 0, 6);
            list.Children.Add(label);
            foreach (var g in groups)
            {
                var open = expanded.Contains(g.Key) || (search.Length > 0 && g.Items.Count <= 40);
                list.Children.Add(GroupRow(g, open));
                if (!open) continue;
                foreach (var item in g.Items.Take(300)) { visible.Add(item); list.Children.Add(ItemRow(item, visible)); }
            }
        }
        browserScroll.Content = list;
        browserScroll.Dispatcher.BeginInvoke(() => browserScroll.ScrollToVerticalOffset(offset), System.Windows.Threading.DispatcherPriority.Loaded);
    }

    FrameworkElement GroupRow(BrowserGroup g, bool open)
    {
        var line = new DockPanel { LastChildFill = true };
        var count = UI.Text(g.Items.Count.ToString(), 12.5, Theme.TextTertiary);
        DockPanel.SetDock(count, Dock.Right);
        line.Children.Add(count);
        var chev = UI.Icon(open ? "" : "", 9, Theme.TextTertiary);
        chev.Width = 18;
        DockPanel.SetDock(chev, Dock.Left);
        line.Children.Add(chev);
        var icon = UI.Icon(g.Glyph, 14, Theme.TextSecondary);
        icon.Width = 28;
        DockPanel.SetDock(icon, Dock.Left);
        line.Children.Add(icon);
        line.Children.Add(UI.Text(g.Title, 14));
        var row = new Border { Child = line, Padding = new Thickness(6, 6, 10, 6), CornerRadius = new CornerRadius(Theme.Radius(6)), Background = Brushes.Transparent, Cursor = Cursors.Hand };
        row.MouseEnter += (_, _) => row.Background = Theme.Ink(0.04);
        row.MouseLeave += (_, _) => row.Background = Brushes.Transparent;
        row.MouseLeftButtonUp += (_, _) => { if (!expanded.Remove(g.Key)) expanded.Add(g.Key); RefreshBrowser(); };
        return row;
    }

    FrameworkElement ItemRow(object item, List<object> visible)
    {
        var selected = browserSelection.Contains(item);
        var (title, detail, glyph) = item switch
        {
            PluginItem p => (p.Name, PluginGrouping.FormatLabel(p), IconGlyphs.Glyph(IconGuesser.Guess(p))),
            LiveActionKind k => (k.Title(), Loc.T("Befehl", "Command"), IconGlyphs.Glyph(k.IconID())),
            _ => ("", "", ""),
        };
        var line = new DockPanel { LastChildFill = true };
        var d = UI.Text(detail, 11.5, selected ? Theme.OnAccent : Theme.TextTertiary);
        DockPanel.SetDock(d, Dock.Right);
        line.Children.Add(d);
        var icon = new TextBlock { Text = glyph, FontFamily = Theme.Icons, FontSize = 12, Width = 24, Foreground = selected ? Theme.OnAccent : Theme.TextTertiary, VerticalAlignment = VerticalAlignment.Center };
        DockPanel.SetDock(icon, Dock.Left);
        line.Children.Add(icon);
        line.Children.Add(UI.Text(title, 13, selected ? Theme.OnAccent : Theme.TextPrimary));
        var row = new Border
        {
            Child = line, Padding = new Thickness(46, 4, 10, 4), CornerRadius = new CornerRadius(Theme.Radius(6)),
            Background = selected ? Theme.Accent : Brushes.Transparent, Cursor = Cursors.Hand,
        };
        if (!selected)
        {
            row.MouseEnter += (_, _) => row.Background = Theme.Ink(0.05);
            row.MouseLeave += (_, _) => row.Background = Brushes.Transparent;
        }
        row.PreviewMouseLeftButtonDown += (_, e) =>
        {
            dragStart = e.GetPosition(Window);
            if (e.ClickCount == 2) { e.Handled = true; Add(new List<object> { item }, Selected?.Id, openFolder); return; }
            if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift) && browserAnchor != null && visible.Contains(browserAnchor))
            {
                var a = visible.IndexOf(browserAnchor);
                var b = visible.IndexOf(item);
                browserSelection.Clear();
                browserSelection.AddRange(visible.Skip(Math.Min(a, b)).Take(Math.Abs(a - b) + 1));
            }
            else if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) { if (!browserSelection.Remove(item)) browserSelection.Add(item); browserAnchor = item; }
            else if (!selected) { browserSelection.Clear(); browserSelection.Add(item); browserAnchor = item; }
            else return;   // keep a multi-selection so it can be dragged
            RefreshBrowser();
        };
        row.MouseMove += (_, e) =>
        {
            if (e.LeftButton != MouseButtonState.Pressed || !Far(e.GetPosition(Window))) return;
            var items = browserSelection.Contains(item) ? browserSelection.ToList() : new List<object> { item };
            DragDrop.DoDragDrop(row, new DataObject(ItemsFormat, items), DragDropEffects.Copy);
        };
        return row;
    }

    bool Far(Point p) => Math.Abs(p.X - dragStart.X) > 6 || Math.Abs(p.Y - dragStart.Y) > 6;

    /// <summary>Adds plugins, presets or Live commands to a category (or one of its folders).</summary>
    void Add(List<object> items, Guid? category, Guid? folder, int? at = null)
    {
        if (category is not { } cat || items.Count == 0) return;
        var target = Model.Config.Categories.First(c => c.Id == cat);
        var container = folder is { } f ? target.Entries.FirstOrDefault(e => e.Id == f)?.Children ?? target.Entries : target.Entries;
        var before = container.Count;
        foreach (var item in items)
        {
            if (item is PluginItem p) Model.Config.AddEntry(p, cat, folder);
            else if (item is LiveActionKind k && ActionFor(k) is { } action) Model.Config.AddAction(action, cat, folder);
        }
        if (at is { } index)
            for (var i = before; i < container.Count; i++) Model.Config.MoveEntry(cat, folder, i, Math.Min(index + i - before, container.Count - 1));
        Changed();
        Model.Hud.Show(Loc.T($"{container.Count - before} zu „{target.Name}“ hinzugefügt", $"{container.Count - before} added to “{target.Name}”"));
    }

    LiveAction? ActionFor(LiveActionKind k)
    {
        if (!k.TakesValue()) return new LiveAction(k);
        var tempo = k == LiveActionKind.SetTempo;
        if (UI.Ask(Window, tempo ? Loc.T("Tempo (BPM)", "Tempo (BPM)") : Loc.T("Taktart", "Time signature"), tempo ? "120" : "4/4",
                tempo ? null : Loc.T("Zum Beispiel 3/4 oder 7/8.", "For example 3/4 or 7/8.")) is not { } text) return null;
        if (tempo && double.TryParse(text.Replace(',', '.'), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var bpm))
            return new LiveAction(k, Math.Clamp(bpm, 20, 999));
        if (!tempo && text.Split('/') is [var n, var d] && int.TryParse(n, out var num) && int.TryParse(d, out var den)) return new LiveAction(k, num, den);
        return null;
    }

    // MARK: Categories (middle)

    FrameworkElement Categories()
    {
        var cats = Model.Config.Categories;
        var head = Head(Loc.T("Kategorien", "Categories"), cats.Count.ToString(), UI.IconButton("", () =>
        {
            if (UI.Ask(Window, Loc.T("Neue Kategorie", "New category"), Loc.T("Neue Kategorie", "New category")) is { Length: > 0 } n)
            { selectedCategory = Model.Config.AddCategory(n); openFolder = null; Changed(); }
        }, Loc.T("Kategorie hinzufügen", "Add category")));
        var list = new StackPanel();
        var selected = Selected;
        for (var i = 0; i < cats.Count; i++) list.Children.Add(CategoryRow(cats[i], i, cats.Count, cats[i].Id == selected?.Id));
        return Column(head, UI.Scroll(list), null);
    }

    FrameworkElement CategoryRow(Category c, int index, int count, bool selected)
    {
        var line = new DockPanel { LastChildFill = true };
        var n = UI.Text(c.Entries.Count.ToString(), 12.5, Theme.TextTertiary);
        DockPanel.SetDock(n, Dock.Right);
        line.Children.Add(n);
        var icon = UI.Icon(c.IsFavorites ? "" : "", 13, c.IsFavorites ? Theme.Accent : Theme.TextTertiary);
        icon.Width = 28;
        DockPanel.SetDock(icon, Dock.Left);
        line.Children.Add(icon);
        line.Children.Add(UI.Text(c.Name, 14.5, weight: selected ? FontWeights.SemiBold : FontWeights.Normal));
        var row = new Border
        {
            Child = line, Padding = new Thickness(10, 8, 10, 8), CornerRadius = new CornerRadius(Theme.Radius(8)), Cursor = Cursors.Hand,
            Background = selected ? UI.Raised : Brushes.Transparent, Margin = new Thickness(0, 2, 0, 2), BorderThickness = new Thickness(1.5),
            BorderBrush = Brushes.Transparent, AllowDrop = true,
        };
        if (selected) UI.Glow(row);
        row.MouseLeftButtonUp += (_, _) => { selectedCategory = c.Id; openFolder = null; selectedEntries.Clear(); Window.Redraw(); };
        row.MouseRightButtonUp += (_, e) =>
        {
            e.Handled = true;
            var items = new List<UI.MenuItem>
            {
                new(Loc.T("Umbenennen …", "Rename …"), () => { if (UI.Ask(Window, Loc.T("Kategorie umbenennen", "Rename category"), c.Name) is { Length: > 0 } name) { Model.Config.RenameCategory(c.Id, name); Changed(); } }, Glyph: ""),
                new(Loc.T("Nach oben", "Move up"), index > 0 ? () => { Model.Config.MoveCategory(index, index - 1); Changed(); } : null, Glyph: ""),
                new(Loc.T("Nach unten", "Move down"), index < count - 1 ? () => { Model.Config.MoveCategory(index, index + 1); Changed(); } : null, Glyph: ""),
            };
            if (!c.IsFavorites)
            {
                items.Add(UI.Separator);
                items.Add(new(Loc.T("Löschen …", "Delete …"), () =>
                {
                    if (UI.Confirm(Window, Loc.T($"„{c.Name}“ löschen?", $"Delete “{c.Name}”?"), Loc.T($"Die Kategorie mit {c.Entries.Count} Einträgen wird entfernt.", $"The category and its {c.Entries.Count} entries are removed."), Loc.T("Löschen", "Delete")))
                    { Model.Config.DeleteCategory(c.Id); selectedCategory = null; Changed(); }
                }, Glyph: ""));
            }
            UI.Menu(row, items);
        };
        // Drop plugins from the left, or pads from the preview (moves them here).
        row.DragOver += (_, e) => { e.Effects = e.Data.GetDataPresent(ItemsFormat) ? DragDropEffects.Copy : e.Data.GetDataPresent(EntriesFormat) ? DragDropEffects.Move : DragDropEffects.None; row.Background = UI.AccentTint(0.18); e.Handled = true; };
        row.DragLeave += (_, _) => row.Background = selected ? UI.Raised : Brushes.Transparent;
        row.Drop += (_, e) =>
        {
            if (e.Data.GetData(ItemsFormat) is List<object> items) Add(items, c.Id, null);
            else if (e.Data.GetData(EntriesFormat) is (Guid from, List<Guid> ids) && from != c.Id) MoveToCategory(from, ids, c.Id);
        };
        return row;
    }

    void MoveToCategory(Guid from, List<Guid> ids, Guid to)
    {
        var source = Model.Config.Categories.First(x => x.Id == from);
        var target = Model.Config.Categories.First(x => x.Id == to);
        foreach (var id in ids)
        {
            var e = source.Entries.FirstOrDefault(x => x.Id == id) ?? source.Entries.Where(x => x.IsFolder).SelectMany(x => x.Children!).FirstOrDefault(x => x.Id == id);
            if (e == null) continue;
            Model.Config.RemoveEntry(id, from);
            target.Entries.Add(e);
        }
        selectedEntries.Clear();
        Changed();
    }

    // MARK: Panel preview (right)

    FrameworkElement Preview()
    {
        var category = Selected;
        if (category == null) return new Border();
        var folder = openFolder is { } fid ? category.Entries.FirstOrDefault(e => e.Id == fid && e.IsFolder) : null;
        if (folder == null) openFolder = null;
        var entries = folder?.Children ?? category.Entries;

        var toggle = UI.Link(Loc.T("Panel-Vorschau", "Panel preview"), () => { padPreview = !padPreview; Window.Redraw(); }, padPreview ? "" : "", accent: padPreview);
        Border? folderButton = null;
        folderButton = UI.IconButton("", () =>
        {
            if (UI.Ask(Window, Loc.T("Neuer Ordner", "New folder"), Loc.T("Ordner", "Folder")) is { Length: > 0 } n) { Model.Config.AddFolder(n, category.Id); Changed(); }
        }, Loc.T("Neuer Ordner", "New folder"));
        Border? live = null;
        live = UI.IconButton("", () => UI.Menu(live!, Enum.GetValues<LiveActionKind>().Select(k =>
            new UI.MenuItem(k.Title(), () => Add(new List<object> { k }, category.Id, openFolder), Glyph: IconGlyphs.Glyph(k.IconID()))).ToList(), atMouse: false),
            Loc.T("Live-Befehl hinzufügen", "Add a Live command"));
        var chain = UI.IconButton("", () => NewChain(category), Loc.T("Kette aus den links markierten Einträgen", "Chain from the items selected on the left"));
        var head = new StackPanel();
        head.Children.Add(Head(folder?.Title ?? category.Name, entries.Count.ToString(), toggle, chain, live, folderButton));
        var hints = new WrapPanel { Margin = new Thickness(0, -4, 0, 14) };
        foreach (var (key, text) in new[] { (Loc.T("Umschalt", "Shift"), Loc.T("Bereich", "range")), (Loc.T("Strg", "Ctrl"), Loc.T("einzeln", "single")), (Loc.T("Strg+G", "Ctrl+G"), Loc.T("Ordner", "group")), (Loc.T("Entf", "Del"), Loc.T("entfernen", "remove")) })
        {
            var h = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 14, 4) };
            h.Children.Add(KeyChip(key));
            var t = UI.Text(text, 12.5, Theme.TextSecondary);
            t.Margin = new Thickness(6, 0, 0, 0);
            h.Children.Add(t);
            hints.Children.Add(h);
        }
        head.Children.Add(hints);
        if (folder != null)
        {
            var back = UI.Link("‹  " + category.Name, () => { openFolder = null; selectedEntries.Clear(); Window.Redraw(); });
            back.HorizontalAlignment = HorizontalAlignment.Left;
            back.Margin = new Thickness(0, -6, 0, 10);
            head.Children.Add(back);
        }

        FrameworkElement body;
        if (entries.Count == 0)
            body = UI.Caption(Loc.T("Noch leer. Zieh Plugins von links hierher oder doppelklick sie.", "Still empty. Drag plugins here from the left or double-click them."));
        else body = padPreview ? Pads(category, folder, entries) : Rows(category, folder, entries);
        var offset = previewScroll.VerticalOffset;
        previewScroll.Content = body;
        Detach(previewScroll);
        previewScroll.Dispatcher.BeginInvoke(() => previewScroll.ScrollToVerticalOffset(offset), System.Windows.Threading.DispatcherPriority.Loaded);
        var drop = new Border { Child = previewScroll, Background = Brushes.Transparent, AllowDrop = true };
        drop.DragOver += (_, e) => { e.Effects = e.Data.GetDataPresent(ItemsFormat) ? DragDropEffects.Copy : DragDropEffects.None; e.Handled = true; };
        drop.Drop += (_, e) => { if (e.Data.GetData(ItemsFormat) is List<object> items) Add(items, category.Id, folder?.Id); };
        return Column(head, drop, Loc.T("Ziehen zum Umsortieren. Rechtsklick für Icon, Name und Farbe.", "Drag to reorder. Right-click for icon, name and colour."), divider: false);
    }

    static Border KeyChip(string key) => new()
    {
        Background = Theme.Ink(0.08), CornerRadius = new CornerRadius(Theme.Radius(4)), Padding = new Thickness(6, 1, 6, 1),
        Child = UI.Text(key, 11.5, Theme.TextPrimary, FontWeights.SemiBold),
    };

    PadData Data(Entry e, int? number)
    {
        var available = e.IsFolder || e.Action != null || e.Chain != null || Model.Catalog.Items.Count == 0 || Model.SearchIndex.Resolver.Resolve(e) != null;
        return new PadData(e.Title, e.IconID, Model.Config.ColorID(e), e.IsFolder, e.Children?.Count ?? 0, Model.NewUris.Contains(e.Uri), available, number);
    }

    /// <summary>The entries as the panel draws them: its page layout (grid or list), pages one under the other.</summary>
    FrameworkElement Pads(Category category, Entry? folder, List<Entry> entries)
    {
        var layout = Model.Config.PanelPage;
        var isGrid = Model.Config.PanelStyle == PanelStyle.Grid;
        var height = isGrid ? Model.Config.PanelSize.ItemHeight + 38 : Model.Config.PanelSize.ItemHeight;
        var stack = new StackPanel();
        var pages = (entries.Count + layout.Size - 1) / layout.Size;
        for (var p = 0; p < pages; p++)
        {
            var grid = new Grid { Margin = new Thickness(0, 0, 0, 16) };
            var used = Math.Min(layout.Size, entries.Count - p * layout.Size);
            var columns = layout.ColumnMajor ? Math.Max(1, (int)Math.Ceiling(used / (double)layout.Rows)) : layout.Columns;
            columns = Math.Max(columns, Math.Min(layout.Columns, 2));
            var rows = layout.ColumnMajor ? Math.Min(layout.Rows, used) : (int)Math.Ceiling(used / (double)layout.Columns);
            for (var c = 0; c < columns; c++) grid.ColumnDefinitions.Add(new ColumnDefinition());
            for (var r = 0; r < rows; r++) grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(height + 6) });
            for (var slot = 0; slot < used; slot++)
            {
                var index = p * layout.Size + slot;
                var (row, column) = layout.Position(slot);
                if (column >= columns || row >= rows) continue;
                var pad = PadHolder(category, folder, entries, index, slot);
                Grid.SetRow(pad, row);
                Grid.SetColumn(pad, column);
                grid.Children.Add(pad);
            }
            if (pages > 1) stack.Children.Add(UI.Text(Loc.T($"Seite {p + 1}", $"Page {p + 1}"), 11.5, Theme.TextTertiary, FontWeights.SemiBold));
            stack.Children.Add(grid);
        }
        return stack;
    }

    FrameworkElement PadHolder(Category category, Entry? folder, List<Entry> entries, int index, int slot)
    {
        var e = entries[index];
        var isGrid = Model.Config.PanelStyle == PanelStyle.Grid;
        var holder = new Border { Margin = new Thickness(3), Background = Brushes.Transparent, Cursor = Cursors.Hand, AllowDrop = true };
        var data = Data(e, slot);
        bool Selected() => selectedEntries.Contains(e.Id);
        holder.Child = PadView.Build(data, isGrid, false, Selected());
        holder.MouseEnter += (_, _) => holder.Child = PadView.Build(data, isGrid, true, Selected());
        holder.MouseLeave += (_, _) => holder.Child = PadView.Build(data, isGrid, false, Selected());
        WireEntry(holder, category, folder, entries, index);
        return holder;
    }

    /// <summary>The entries as plain rows (preview switched off).</summary>
    FrameworkElement Rows(Category category, Entry? folder, List<Entry> entries)
    {
        var stack = new StackPanel();
        for (var i = 0; i < entries.Count; i++)
        {
            var e = entries[i];
            var line = new DockPanel { LastChildFill = true };
            var color = Theme.LabelColor(Model.Config.ColorID(e));
            var icon = Theme.Icon(e.IconID, 14, color is { } c ? Theme.B(c) : Theme.TextSecondary);
            icon.Width = 26;
            DockPanel.SetDock(icon, Dock.Left);
            line.Children.Add(icon);
            line.Children.Add(UI.Text(e.Title, 13.5));
            var row = new Border
            {
                Child = line, Padding = new Thickness(8, 7, 8, 7), Margin = new Thickness(0, 1, 0, 1), CornerRadius = new CornerRadius(Theme.Radius(7)),
                Background = selectedEntries.Contains(e.Id) ? UI.AccentTint(0.2) : UI.Raised, AllowDrop = true, Cursor = Cursors.Hand,
            };
            WireEntry(row, category, folder, entries, i);
            stack.Children.Add(row);
        }
        return stack;
    }

    /// <summary>Selection (click, Ctrl, Shift), open folders, rename, menu, drag to reorder, drops from the left.</summary>
    void WireEntry(Border element, Category category, Entry? folder, List<Entry> entries, int index)
    {
        var e = entries[index];
        element.PreviewMouseLeftButtonDown += (_, ev) =>
        {
            dragStart = ev.GetPosition(Window);
            if (ev.ClickCount == 2)
            {
                ev.Handled = true;
                if (e.IsFolder) { openFolder = e.Id; selectedEntries.Clear(); Window.Redraw(); }
                else Rename(category, e);
                return;
            }
            if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift) && entryAnchor is { } a && entries.FindIndex(x => x.Id == a) is var ai and >= 0)
            {
                selectedEntries.Clear();
                for (var i = Math.Min(ai, index); i <= Math.Max(ai, index); i++) selectedEntries.Add(entries[i].Id);
            }
            else if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) { if (!selectedEntries.Remove(e.Id)) selectedEntries.Add(e.Id); entryAnchor = e.Id; }
            else if (!selectedEntries.Contains(e.Id)) { selectedEntries.Clear(); selectedEntries.Add(e.Id); entryAnchor = e.Id; }
            else return;
            Window.Redraw();
        };
        element.MouseMove += (_, ev) =>
        {
            if (ev.LeftButton != MouseButtonState.Pressed || !Far(ev.GetPosition(Window))) return;
            var ids = selectedEntries.Contains(e.Id) ? entries.Where(x => selectedEntries.Contains(x.Id)).Select(x => x.Id).ToList() : new List<Guid> { e.Id };
            DragDrop.DoDragDrop(element, new DataObject(EntriesFormat, (category.Id, ids)), DragDropEffects.Move);
        };
        element.MouseRightButtonUp += (_, ev) =>
        {
            ev.Handled = true;
            if (!selectedEntries.Contains(e.Id)) { selectedEntries.Clear(); selectedEntries.Add(e.Id); entryAnchor = e.Id; }
            EntryMenu(element, category, e, folder);
        };
        element.DragOver += (_, ev) =>
        {
            ev.Effects = ev.Data.GetDataPresent(ItemsFormat) ? DragDropEffects.Copy : ev.Data.GetDataPresent(EntriesFormat) ? DragDropEffects.Move : DragDropEffects.None;
            element.Opacity = 0.6;
            ev.Handled = true;
        };
        element.DragLeave += (_, _) => element.Opacity = 1;
        element.Drop += (_, ev) =>
        {
            ev.Handled = true;
            element.Opacity = 1;
            if (ev.Data.GetData(ItemsFormat) is List<object> items)
            {
                if (e.IsFolder) Add(items, category.Id, e.Id);           // onto a folder: into it
                else Add(items, category.Id, folder?.Id, index);       // onto a pad: in its place
                return;
            }
            if (ev.Data.GetData(EntriesFormat) is (Guid from, List<Guid> ids))
            {
                if (from != category.Id) { MoveToCategory(from, ids, category.Id); return; }
                if (e.IsFolder && !ids.Contains(e.Id))
                {
                    foreach (var id in ids) if (category.Entries.All(x => x.Id != id || !x.IsFolder)) Model.Config.MoveEntry(id, e.Id, category.Id);
                    Changed();
                    return;
                }
                // Reorder: the dragged entries take the place of the one dropped on.
                var target = index;
                foreach (var id in ids)
                {
                    var current = entries.FindIndex(x => x.Id == id);
                    if (current < 0) continue;
                    Model.Config.MoveEntry(category.Id, folder?.Id, current, target);
                    if (current > target) target++;
                }
                Changed();
            }
        };
    }

    static PluginItem Item(Entry e) => new(e.Uri, e.Name, e.Source, e.Path);

    void Rename(Category category, Entry e)
    {
        if (e.IsFolder)
        {
            if (UI.Ask(Window, Loc.T("Ordner umbenennen", "Rename folder"), e.Name) is { Length: > 0 } n) { Model.Config.RenameFolder(e.Id, category.Id, n); Changed(); }
            return;
        }
        var name = UI.Ask(Window, Loc.T("Anzeigename", "Display name"), e.Title, Loc.T($"Leer lassen für den Originalnamen „{e.Name}“.", $"Leave empty for the original name “{e.Name}”."));
        if (name == null) return;
        Model.Config.SetDisplayName(name.Length == 0 || name == e.Name ? null : name, e.Id, category.Id);
        Changed();
    }

    void EntryMenu(FrameworkElement at, Category category, Entry e, Entry? folder)
    {
        var ids = selectedEntries.ToList();
        var many = ids.Count > 1;
        var items = new List<UI.MenuItem>();
        if (!many)
        {
            items.Add(new(Loc.T("Umbenennen …", "Rename …"), () => Rename(category, e), Glyph: ""));
            items.Add(new(Loc.T("Icon", "Icon"), Submenu: IconCatalog.AllIDs.Select(id => new UI.MenuItem(id, () => { Model.Config.SetIcon(id, e.Id, category.Id); Changed(); }, Checked: id == e.IconID, Glyph: IconGlyphs.Glyph(id))).ToList(), Glyph: IconGlyphs.Glyph(e.IconID)));
        }
        items.Add(new(Loc.T("Farbe", "Colour"), Submenu: new[] { new UI.MenuItem(Loc.T("Keine (Regel folgen)", "None (follow the rules)"), () => SetColor(category, ids, null), Checked: e.ColorID == null) }
            .Concat(ColorPalette.All.Select(c => new UI.MenuItem(c.Label, () => SetColor(category, ids, c.Id), Checked: e.ColorID == c.Id, Swatch: Theme.LabelColor(c.Id)))).ToList(), Glyph: ""));
        if (!many && !e.IsFolder && e.Action == null && e.Chain == null)
            items.Add(new(Loc.T("Tastenkürzel …", "Shortcut …"), () => ShortcutDialog.Show(Window, Model, Item(e), e.Title), Glyph: ""));
        if (!many && e.IsFolder) items.Add(new(Loc.T("Öffnen", "Open"), () => { openFolder = e.Id; selectedEntries.Clear(); Window.Redraw(); }, Glyph: ""));
        items.Add(UI.Separator);
        var folders = category.Entries.Where(x => x.IsFolder && x.Id != folder?.Id && !ids.Contains(x.Id)).ToList();
        if (!e.IsFolder && folders.Count > 0)
            items.Add(new(Loc.T("In Ordner", "Into folder"), Submenu: folders.Select(f => new UI.MenuItem(f.Title, () => { foreach (var id in ids) Model.Config.MoveEntry(id, f.Id, category.Id); Changed(); }, Glyph: "")).ToList(), Glyph: ""));
        if (folder != null) items.Add(new(Loc.T("Aus dem Ordner nehmen", "Take out of the folder"), () => { foreach (var id in ids) Model.Config.MoveEntry(id, null, category.Id); Changed(); }, Glyph: ""));
        if (folder == null && !e.IsFolder) items.Add(new(Loc.T("Als Ordner gruppieren …", "Group into a folder …") + "   Ctrl+G", () => Group(category), Glyph: ""));
        if (!many && e.IsFolder) items.Add(new(Loc.T("Ordner auflösen", "Dissolve folder"), () => { Model.Config.DissolveFolder(e.Id, category.Id); Changed(); }, Glyph: ""));
        var others = Model.Config.Categories.Where(c => c.Id != category.Id).ToList();
        if (others.Count > 0)
            items.Add(new(Loc.T("In Kategorie verschieben", "Move to category"), Submenu: others.Select(c => new UI.MenuItem(c.Name, () => MoveToCategory(category.Id, ids, c.Id))).ToList(), Glyph: ""));
        items.Add(UI.Separator);
        items.Add(new(many ? Loc.T($"{ids.Count} entfernen", $"Remove {ids.Count}") : Loc.T("Entfernen", "Remove"), () => RemoveSelected(category), Glyph: ""));
        UI.Menu(at, items);
    }

    void SetColor(Category category, List<Guid> ids, string? color)
    {
        foreach (var id in ids) Model.Config.SetColor(color, id, category.Id);
        Changed();
    }

    void RemoveSelected(Category category)
    {
        foreach (var id in selectedEntries.ToList()) Model.Config.RemoveEntry(id, category.Id);
        selectedEntries.Clear();
        Changed();
    }

    /// <summary>Ctrl+G: the selected entries into a new folder, where the first of them was.</summary>
    void Group(Category category)
    {
        var ids = category.Entries.Where(x => selectedEntries.Contains(x.Id) && !x.IsFolder).Select(x => x.Id).ToList();
        if (ids.Count == 0) return;
        if (UI.Ask(Window, Loc.T("Neuer Ordner", "New folder"), Loc.T("Ordner", "Folder")) is not { Length: > 0 } name) return;
        var first = category.Entries.FindIndex(x => x.Id == ids[0]);
        var folderId = Model.Config.AddFolder(name, category.Id);
        foreach (var id in ids) Model.Config.MoveEntry(id, folderId, category.Id);
        var at = category.Entries.FindIndex(x => x.Id == folderId);
        Model.Config.MoveEntry(category.Id, null, at, Math.Min(first, category.Entries.Count - 1));
        selectedEntries.Clear();
        Changed();
    }

    void NewChain(Category category)
    {
        var items = browserSelection.OfType<PluginItem>().ToList();
        if (items.Count < 2) { UI.Tell(Window, Loc.T("Kette", "Chain"), Loc.T("Markier links mehrere Plugins, Geräte oder Presets (Strg+Klick). Sie werden nacheinander eingefügt.", "Select several plugins, devices or presets on the left (Ctrl+click). They are inserted one after the other.")); return; }
        if (UI.Ask(Window, Loc.T("Name der Kette", "Chain name"), string.Join(" + ", items.Select(i => i.Name).Take(3))) is not { Length: > 0 } name) return;
        Model.Config.AddChain(name, items, category.Id, openFolder);
        Changed();
    }

    public override bool Key(KeyEventArgs e)
    {
        if (searchBox?.IsKeyboardFocused == true || Selected is not { } category) return false;
        if ((e.Key == System.Windows.Input.Key.Delete || e.Key == System.Windows.Input.Key.Back) && selectedEntries.Count > 0) { RemoveSelected(category); return true; }
        if (e.Key == System.Windows.Input.Key.G && Keyboard.Modifiers == ModifierKeys.Control) { Group(category); return true; }
        if (e.Key == System.Windows.Input.Key.A && Keyboard.Modifiers == ModifierKeys.Control)
        {
            var list = (openFolder is { } f ? category.Entries.FirstOrDefault(x => x.Id == f)?.Children : null) ?? category.Entries;
            foreach (var x in list) selectedEntries.Add(x.Id);
            Window.Redraw();
            return true;
        }
        if (e.Key == System.Windows.Input.Key.Escape && selectedEntries.Count > 0) { selectedEntries.Clear(); Window.Redraw(); return true; }
        return false;
    }
}
