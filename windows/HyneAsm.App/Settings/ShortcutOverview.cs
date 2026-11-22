using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Shortcut overview (the Mac's KnownShortcutsView): a drawn keyboard where every key shows who uses it
/// (Live, Windows, HYNE ASM), modifier keys filter, hovering a key or a shortcut highlights the other side,
/// and a searchable list on the right.</summary>
sealed class ShortcutOverview : Window
{
    const double Unit = 40, Gap = 5;

    readonly List<KnownShortcut> all;
    readonly Dictionary<string, ushort?> code = new();
    WinModifiers filter;
    KnownShortcut.AppKind? app;
    ushort? hoveredKey;
    string? hoveredShortcut;
    string query = "";
    readonly ContentControl keyboard = new();
    readonly StackPanel list = new();
    readonly ScrollViewer listScroll;

    record struct KeySpec(string Label, double Width, ushort? Vk, WinModifiers Modifier = WinModifiers.None);

    static readonly KeySpec[][] Rows =
    {
        new[] { K("Esc", 1, 0x1B) }.Concat(Enumerable.Range(1, 12).Select(i => K("F" + i, 1, (ushort)(0x6F + i)))).ToArray(),
        new[] { K("`", 1, 0xC0) }.Concat("1234567890".Select(c => K(c.ToString(), 1, c))).Concat(new[] { K("-", 1, 0xBD), K("=", 1, 0xBB), K("⌫", 2, 0x08) }).ToArray(),
        new[] { K("⇥", 1.5, 0x09) }.Concat("QWERTYUIOP".Select(c => K(c.ToString(), 1, c))).Concat(new[] { K("[", 1, 0xDB), K("]", 1, 0xDD), K("\\", 1.5, 0xDC) }).ToArray(),
        new[] { K("Caps", 1.75, null) }.Concat("ASDFGHJKL".Select(c => K(c.ToString(), 1, c))).Concat(new[] { K(";", 1, 0xBA), K("'", 1, 0xDE), K("↵", 2.25, 0x0D) }).ToArray(),
        new[] { M("⇧", 2.25, WinModifiers.Shift) }.Concat("ZXCVBNM".Select(c => K(c.ToString(), 1, c))).Concat(new[] { K(",", 1, 0xBC), K(".", 1, 0xBE), K("/", 1, 0xBF), M("⇧", 2.75, WinModifiers.Shift) }).ToArray(),
        new[] { M(Loc.T("Strg", "Ctrl"), 1.25, WinModifiers.Ctrl), M("Win", 1.25, WinModifiers.Win), M("Alt", 1.25, WinModifiers.Alt), K(Loc.T("Leertaste", "Space"), 6.25, 0x20),
                M("Alt", 1.25, WinModifiers.Alt), K("←", 1, 0x25), K("↑", 1, 0x26), K("↓", 1, 0x28), K("→", 1, 0x27), K(Loc.T("Entf", "Del"), 1.25, 0x2E) },
    };

    static KeySpec K(string label, double w, ushort? vk) => new(label, w, vk);
    static KeySpec K(string label, double w, char c) => new(label, w, c);
    static KeySpec M(string label, double w, WinModifiers m) => new(label, w, null, m);

    static Color AppColor(KnownShortcut.AppKind a) => a switch
    {
        KnownShortcut.AppKind.Live => Color.FromRgb(0xFF, 0x8C, 0x1A),
        KnownShortcut.AppKind.Windows => Color.FromRgb(0x3C, 0xAB, 0xF7),
        _ => Color.FromRgb(0x4C, 0xCC, 0x80),
    };

    public ShortcutOverview(AppModel model)
    {
        Title = Loc.T("Tastenkürzel-Übersicht", "Shortcut Overview");
        Width = 1240; Height = 640;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = UI.Canvas;
        FontFamily = Theme.Font;
        ShowInTaskbar = false;
        all = KnownShortcuts.All.Concat(KnownShortcuts.Hyne(model.Config)).ToList();
        foreach (var s in all) code[s.Id] = s.Pressed.Code ?? (s.Pressed.Char is { } c ? KnownShortcuts.UsLayoutVk(c) : null);
        listScroll = UI.Scroll(list);

        var root = new DockPanel { Margin = new Thickness(28, 24, 28, 24), LastChildFill = true };
        var head = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 0, 0, 20) };
        var done = UI.Primary(Loc.T("Fertig", "Done"), Close);
        DockPanel.SetDock(done, Dock.Right);
        head.Children.Add(done);
        var text = new StackPanel();
        text.Children.Add(UI.Text(Loc.T("Tastenkürzel-Übersicht", "Shortcut Overview"), 22, weight: FontWeights.Bold));
        text.Children.Add(UI.Caption(Loc.T("Fahr über eine Taste oder ein Kürzel. Klick auf Strg, Alt, ⇧ oder Win, um nach Modifiern zu filtern. Live 12 und Windows: die gängigen Standardkürzel.",
                                           "Hover a key or a shortcut. Click Ctrl, Alt, Shift or Win to filter by modifiers. Live 12 and Windows: the common default shortcuts.")));
        head.Children.Add(text);
        DockPanel.SetDock(head, Dock.Top);
        root.Children.Add(head);

        var side = new DockPanel { Width = 380, Margin = new Thickness(24, 0, 0, 0), LastChildFill = true };
        var filters = new StackPanel();
        var appPicker = new ContentControl();
        void Apps() => appPicker.Content = UI.Segmented(new (string, KnownShortcut.AppKind?)[] { (Loc.T("Alle", "All"), null), ("Live", KnownShortcut.AppKind.Live), ("Windows", KnownShortcut.AppKind.Windows), ("HYNE ASM", KnownShortcut.AppKind.Hyne) },
            app, v => { app = v; Apps(); Redraw(); });
        Apps();
        filters.Children.Add(appPicker);
        var (field, box) = UI.SearchField("", Loc.T("Suchen", "Search"));
        field.Margin = new Thickness(0, 10, 0, 10);
        box.TextChanged += (_, _) => { query = box.Text.Trim().ToLowerInvariant(); FillList(); };
        filters.Children.Add(field);
        DockPanel.SetDock(filters, Dock.Top);
        side.Children.Add(filters);
        side.Children.Add(new Border { Child = listScroll, Background = UI.Raised, CornerRadius = new CornerRadius(Theme.Radius(12)), BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1), Padding = new Thickness(4) });
        DockPanel.SetDock(side, Dock.Right);
        root.Children.Add(side);

        var left = new StackPanel();
        left.Children.Add(keyboard);
        left.Children.Add(Legend());
        root.Children.Add(left);
        Content = root;
        Redraw();
    }

    IEnumerable<KnownShortcut> Visible => all.Where(s => (app == null || s.App == app) && (filter == WinModifiers.None || s.Modifiers == filter));

    void Redraw() { DrawKeyboard(); FillList(); }

    void DrawKeyboard()
    {
        var visible = Visible.ToList();
        var byKey = visible.Where(s => code[s.Id] != null).GroupBy(s => code[s.Id]!.Value).ToDictionary(g => g.Key, g => g.ToList());
        var hovered = hoveredShortcut != null ? all.FirstOrDefault(s => s.Id == hoveredShortcut) : null;
        var rows = new StackPanel();
        for (var r = 0; r < Rows.Length; r++)
        {
            var line = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, Gap) };
            foreach (var key in Rows[r])
            {
                var isMod = key.Modifier != WinModifiers.None;
                var lit = hovered != null
                    ? isMod ? hovered.Modifiers.HasFlag(key.Modifier) : key.Vk != null && key.Vk == code[hovered.Id]
                    : isMod ? filter.HasFlag(key.Modifier) : key.Vk != null && key.Vk == hoveredKey;
                var uses = key.Vk is { } vk && byKey.TryGetValue(vk, out var l) ? l : new List<KnownShortcut>();
                line.Children.Add(Cap(key, r == 0, lit, uses));
            }
            rows.Children.Add(line);
        }
        keyboard.Content = new Border
        {
            Child = rows, Padding = new Thickness(14, 14, 14, 9), Background = UI.KeyboardBase, CornerRadius = new CornerRadius(Theme.Radius(12)),
            BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1), HorizontalAlignment = HorizontalAlignment.Left,
        };
    }

    FrameworkElement Cap(KeySpec key, bool shortRow, bool lit, List<KnownShortcut> uses)
    {
        var isMod = key.Modifier != WinModifiers.None;
        var on = isMod && filter.HasFlag(key.Modifier);
        var grid = new Grid();
        var label = UI.Text(key.Label, key.Label.Length > 2 ? 11 : 13.5, lit || on ? Theme.OnAccent : Theme.TextPrimary, FontWeights.SemiBold);
        label.HorizontalAlignment = HorizontalAlignment.Center;
        grid.Children.Add(label);
        var dots = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 4) };
        foreach (var a in new[] { KnownShortcut.AppKind.Live, KnownShortcut.AppKind.Windows, KnownShortcut.AppKind.Hyne }.Where(a => uses.Any(u => u.App == a)))
            dots.Children.Add(new Border { Width = 5, Height = 5, CornerRadius = new CornerRadius(2.5), Margin = new Thickness(1.5, 0, 1.5, 0), Background = Theme.B(AppColor(a)) });
        grid.Children.Add(dots);
        var cap = new Border
        {
            Width = key.Width * Unit + (key.Width - 1) * Gap, Height = shortRow ? Unit * 0.7 : Unit, Margin = new Thickness(0, 0, Gap, 0), Child = grid,
            CornerRadius = new CornerRadius(Theme.Radius(6)), BorderThickness = new Thickness(1),
            Background = lit || on ? Theme.Accent : uses.Count > 0 ? UI.Hover : UI.Raised, BorderBrush = Theme.Stroke,
            Cursor = isMod ? Cursors.Hand : null,
            ToolTip = uses.Count > 0 ? string.Join("\n", uses.Select(u => $"{Keys.Describe(code[u.Id] ?? 0, u.Modifiers)}   {u.Title}  ({Keys.AppName(u.App)})")) : null,
        };
        if (isMod) cap.MouseLeftButtonUp += (_, _) => { filter ^= key.Modifier; Redraw(); };
        else if (key.Vk is { } vk)
        {
            cap.MouseEnter += (_, _) => { hoveredKey = vk; hoveredShortcut = null; FillList(scrollToKey: true); };
            cap.MouseLeave += (_, _) => { if (hoveredKey == vk) { hoveredKey = null; FillList(); } };
        }
        return cap;
    }

    UIElement Legend()
    {
        var legend = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(4, 12, 0, 0) };
        foreach (var a in new[] { KnownShortcut.AppKind.Live, KnownShortcut.AppKind.Windows, KnownShortcut.AppKind.Hyne })
        {
            legend.Children.Add(UI.Dot(AppColor(a), 8));
            var t = UI.Text(a == KnownShortcut.AppKind.Live ? "Ableton Live 12" : Keys.AppName(a), 12.5, Theme.TextSecondary);
            t.Margin = new Thickness(6, 0, 20, 0);
            legend.Children.Add(t);
        }
        legend.Children.Add(UI.Link(Loc.T("Modifier-Filter löschen", "Clear modifier filter"), () => { filter = WinModifiers.None; Redraw(); }, accent: false));
        return legend;
    }

    void FillList(bool scrollToKey = false)
    {
        list.Children.Clear();
        var items = Visible.Where(s => query.Length == 0 || s.Title.ToLowerInvariant().Contains(query) || Keys.Describe(code[s.Id] ?? 0, s.Modifiers).ToLowerInvariant().Contains(query)).ToList();
        if (items.Count == 0) list.Children.Add(UI.Caption(Loc.T("Keine Kürzel", "No shortcuts")));
        FrameworkElement? first = null;
        foreach (var s in items)
        {
            var onKey = hoveredKey != null && code[s.Id] == hoveredKey;
            var highlighted = onKey || hoveredShortcut == s.Id;
            var line = new DockPanel { LastChildFill = true };
            var keys = UI.Text(Keys.Describe(code[s.Id] ?? 0, s.Modifiers), 12.5, highlighted ? Theme.OnAccent : Theme.TextPrimary, FontWeights.Bold);
            DockPanel.SetDock(keys, Dock.Right);
            line.Children.Add(keys);
            var dot = UI.Dot(AppColor(s.App), 7);
            dot.Margin = new Thickness(0, 0, 10, 0);
            DockPanel.SetDock(dot, Dock.Left);
            line.Children.Add(dot);
            var text = new StackPanel();
            text.Children.Add(UI.Text(s.Title, 13, highlighted ? Theme.OnAccent : Theme.TextPrimary));
            text.Children.Add(UI.Text(s.Section, 11, highlighted ? Theme.OnAccent : Theme.TextTertiary));
            line.Children.Add(text);
            var row = new Border
            {
                Child = line, Padding = new Thickness(10, 5, 12, 5), CornerRadius = new CornerRadius(Theme.Radius(6)),
                Background = highlighted ? Theme.Accent : Brushes.Transparent, Opacity = hoveredKey != null && !onKey ? 0.45 : 1,
            };
            var id = s.Id;
            row.MouseEnter += (_, _) => { if (hoveredShortcut != id) { hoveredShortcut = id; hoveredKey = null; DrawKeyboard(); row.Background = Theme.Accent; } };
            row.MouseLeave += (_, _) => { if (hoveredShortcut == id) { hoveredShortcut = null; DrawKeyboard(); row.Background = Brushes.Transparent; } };
            if (onKey && first == null) first = row;
            list.Children.Add(row);
        }
        if (scrollToKey && first != null) first.BringIntoView();
    }
}
