using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Settings surfaces per theme (the Mac's canvas / sidebar / surface / raised / hover values).</summary>
sealed record SettingsColors(Color Canvas, Color Sidebar, Color Surface, Color Raised, Color Hover, Color KeyboardBase)
{
    static Color H(uint v) => Color.FromRgb((byte)(v >> 16), (byte)(v >> 8), (byte)v);

    public static SettingsColors For(AppTheme t) => t switch
    {
        AppTheme.Ableton => new(H(0x1E1E1E), H(0x262626), H(0x2C2C2C), H(0x3A3A3A), H(0x464646), H(0x161616)),
        AppTheme.Hyne => new(H(0x171717), H(0x222222), H(0x2A2A2A), H(0x3A3A3A), H(0x424242), H(0x131313)),
        AppTheme.Light => new(H(0xF5F5F7), H(0xEBEBEE), Colors.White, H(0xF0F0F3), H(0xE4E4E9), H(0xDADADF)),
        AppTheme.Retro => new(H(0xBFBFC1), H(0xA9A9AC), H(0xCBCBCD), H(0xD6D6D8), H(0xDFDFE1), H(0x9C9C9F)),
        _ => new(H(0x0C0B0A), H(0x141311), H(0x121110), H(0x1D1C1A), H(0x262421), H(0x0C0B0A)),
    };

    public static SettingsColors Current => For(Theme.Id);
}

/// <summary>Building blocks of the settings window, drawn like the Mac's (DesignSystem.swift): cards with hairline
/// rows, accent buttons, switches, key caps, and themed menus and dialogs instead of Windows' own.</summary>
static class UI
{
    static SettingsColors C => SettingsColors.Current;
    public static Brush Canvas => Theme.B(C.Canvas);
    public static Brush Sidebar => Theme.B(C.Sidebar);
    public static Brush Surface => Theme.B(C.Surface);
    public static Brush Raised => Theme.B(C.Raised);
    public static Brush Hover => Theme.B(C.Hover);
    public static Brush KeyboardBase => Theme.B(C.KeyboardBase);
    public static Color AccentColor => Theme.Current.Accent;
    public static Brush AccentTint(double a) => Theme.B(Color.FromArgb((byte)(a * 255), AccentColor.R, AccentColor.G, AccentColor.B));

    public static TextBlock Text(string text, double size = 13, Brush? brush = null, FontWeight? weight = null, bool wrap = false) => new()
    {
        Text = text, FontSize = size, Foreground = brush ?? Theme.TextPrimary, FontWeight = weight ?? FontWeights.Normal,
        TextWrapping = wrap ? TextWrapping.Wrap : TextWrapping.NoWrap, TextTrimming = wrap ? TextTrimming.None : TextTrimming.CharacterEllipsis,
        VerticalAlignment = VerticalAlignment.Center,
    };

    public static TextBlock Caption(string text) => Text(text, 12, Theme.TextTertiary, wrap: true);
    public static TextBlock Icon(string glyph, double size, Brush brush) => new()
    {
        Text = glyph, FontFamily = Theme.Icons, FontSize = size, Foreground = brush, VerticalAlignment = VerticalAlignment.Center,
    };

    /// <summary>Page head: big title and the explanation under it, buttons top right.</summary>
    public static FrameworkElement PageHeader(string title, string subtitle, params UIElement[] buttons)
    {
        var head = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 0, 0, 22) };
        var tools = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 4, 0, 0) };
        foreach (var b in buttons) tools.Children.Add(b);
        DockPanel.SetDock(tools, Dock.Right);
        head.Children.Add(tools);
        var text = new StackPanel();
        text.Children.Add(Text(title, 26, weight: FontWeights.Bold));
        var sub = Text(subtitle, 14, Theme.TextSecondary, wrap: true);
        sub.Margin = new Thickness(0, 6, 24, 0);
        sub.MaxWidth = 720;
        sub.HorizontalAlignment = HorizontalAlignment.Left;
        text.Children.Add(sub);
        head.Children.Add(text);
        return head;
    }

    /// <summary>The page column: centred, at most ~1120 wide, scrolls.</summary>
    public static FrameworkElement PageColumn(UIElement content) => Scroll(new Border
    {
        MaxWidth = 1120, Padding = new Thickness(40, 34, 40, 34), HorizontalAlignment = HorizontalAlignment.Stretch, Child = content,
    });

    /// <summary>Group head: accent icon and bold title, a link on the right, explanation underneath.</summary>
    public static FrameworkElement GroupHeader(string glyph, string title, string? caption = null, UIElement? trailing = null)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 24, 0, 10) };
        var line = new DockPanel { LastChildFill = true };
        if (trailing != null) { DockPanel.SetDock(trailing, Dock.Right); line.Children.Add(trailing); }
        var left = new StackPanel { Orientation = Orientation.Horizontal };
        var icon = Icon(glyph, 16, Theme.Accent);
        icon.Margin = new Thickness(0, 0, 10, 0);
        left.Children.Add(icon);
        left.Children.Add(Text(title, 18, weight: FontWeights.Bold));
        line.Children.Add(left);
        panel.Children.Add(line);
        if (caption != null) { var c = Caption(caption); c.Margin = new Thickness(0, 6, 0, 0); c.FontSize = 12.5; panel.Children.Add(c); }
        return panel;
    }

    /// <summary>Small grey label over a list ("Profiles", "Saved versions"), optional text on the right.</summary>
    public static FrameworkElement Label(string text, UIElement? trailing = null)
    {
        var line = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 22, 0, 8) };
        if (trailing != null) { DockPanel.SetDock(trailing, Dock.Right); line.Children.Add(trailing); }
        line.Children.Add(Text(text, 12.5, Theme.TextSecondary, FontWeights.SemiBold));
        return line;
    }

    /// <summary>A card; several rows are separated by hairlines.</summary>
    public static Border Card(params UIElement[] rows)
    {
        var stack = new StackPanel();
        for (var i = 0; i < rows.Length; i++)
        {
            if (i > 0) stack.Children.Add(new Border { Height = 1, Background = Theme.Stroke, Margin = new Thickness(-20, 0, -20, 0) });
            stack.Children.Add(rows[i]);
        }
        return new Border
        {
            Background = Raised, CornerRadius = new CornerRadius(Theme.Radius(12)), BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1),
            Padding = new Thickness(20, 4, 20, 4), Child = stack, ClipToBounds = true,
        };
    }

    /// <summary>Title and explanation on the left, a control on the right.</summary>
    public static FrameworkElement Row(string title, string? detail, UIElement? trailing, UIElement? leading = null, double minHeight = 58)
    {
        var grid = new Grid { MinHeight = minHeight };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        if (leading != null) { ((FrameworkElement)leading).Margin = new Thickness(0, 0, 14, 0); grid.Children.Add(leading); }
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 10, 16, 10) };
        text.Children.Add(Text(title, 14, weight: FontWeights.SemiBold));
        if (detail != null) { var d = Text(detail, 12.5, Theme.TextTertiary, wrap: true); d.Margin = new Thickness(0, 3, 0, 0); text.Children.Add(d); }
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        if (trailing != null) { Grid.SetColumn(trailing, 2); ((FrameworkElement)trailing).VerticalAlignment = VerticalAlignment.Center; grid.Children.Add(trailing); }
        return grid;
    }

    static Border Clickable(Border b, Action onClick)
    {
        b.Cursor = Cursors.Hand;
        b.MouseEnter += (_, _) => b.Opacity = 0.82;
        b.MouseLeave += (_, _) => b.Opacity = 1;
        b.MouseLeftButtonUp += (_, e) => { e.Handled = true; onClick(); };
        return b;
    }

    static StackPanel IconText(string? glyph, string title, Brush fg, double size)
    {
        var content = new StackPanel { Orientation = Orientation.Horizontal };
        if (glyph != null)
        {
            var i = Icon(glyph, size, fg);
            i.Margin = new Thickness(0, 0, title.Length > 0 ? 8 : 0, 0);
            content.Children.Add(i);
        }
        if (title.Length > 0) content.Children.Add(Text(title, size, fg, FontWeights.SemiBold));
        return content;
    }

    /// <summary>Accent text on a raised plate (the top-right buttons: Import …, Export …).</summary>
    public static Border Button(string title, Action onClick, string? icon = null, string? tip = null) => Clickable(new Border
    {
        Child = IconText(icon, title, Theme.Accent, 14), Background = Raised, CornerRadius = new CornerRadius(Theme.Radius(8)),
        Padding = new Thickness(14, 7, 14, 7), Margin = new Thickness(10, 0, 0, 0), ToolTip = tip, VerticalAlignment = VerticalAlignment.Center,
        BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1),
    }, onClick);

    /// <summary>Filled accent button (Save Current Menu).</summary>
    public static Border Primary(string title, Action onClick, string? icon = null) => Clickable(new Border
    {
        Child = IconText(icon, title, Theme.OnAccent, 14), Background = Theme.Accent, CornerRadius = new CornerRadius(Theme.Radius(7)),
        Padding = new Thickness(16, 7, 16, 7), Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center,
    }, onClick);

    /// <summary>Small accent button inside a row (Restore …, LES Import …).</summary>
    public static Border SmallButton(string title, Action onClick, string? icon = null) => Clickable(new Border
    {
        Child = IconText(icon, title, Theme.Accent, 13), Background = AccentTint(0.10), CornerRadius = new CornerRadius(Theme.Radius(7)),
        Padding = new Thickness(12, 5, 12, 5), Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center,
    }, onClick);

    /// <summary>Plain accent text link (+ New Profile, Restore Defaults).</summary>
    public static Border Link(string title, Action onClick, string? icon = null, bool accent = true) => Clickable(new Border
    {
        Child = IconText(icon, title, accent ? Theme.Accent : Theme.TextSecondary, 13), Background = Brushes.Transparent,
        Padding = new Thickness(4, 2, 4, 2), VerticalAlignment = VerticalAlignment.Center,
    }, onClick);

    /// <summary>A bare icon (pencil, trash, share) in a row.</summary>
    public static Border IconButton(string glyph, Action onClick, string tip, Brush? brush = null) => Clickable(new Border
    {
        Child = Icon(glyph, 14, brush ?? Theme.TextSecondary), Background = Brushes.Transparent, Padding = new Thickness(9, 6, 9, 6),
        ToolTip = tip, VerticalAlignment = VerticalAlignment.Center,
    }, onClick);

    /// <summary>An on/off switch: accent track with a light knob, grey when off.</summary>
    public static FrameworkElement Toggle(bool on, Action<bool> changed)
    {
        var knob = new Border
        {
            Width = 30, Height = 24, CornerRadius = new CornerRadius(12), Margin = new Thickness(3),
            Background = Theme.B(on ? Color.FromRgb(0xFF, 0xEE, 0xE0) : Color.FromRgb(0xE8, 0xE8, 0xE8)),
            HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left,
        };
        var track = new Border
        {
            Width = 68, Height = 30, CornerRadius = new CornerRadius(15), Child = knob, Cursor = Cursors.Hand, VerticalAlignment = VerticalAlignment.Center,
            Background = on ? Theme.Accent : Theme.Ink(0.14),
        };
        if (on) track.Effect = new DropShadowEffect { Color = AccentColor, BlurRadius = 10, ShadowDepth = 0, Opacity = 0.35 };
        track.MouseLeftButtonUp += (_, e) => { e.Handled = true; changed(!on); };
        return track;
    }

    /// <summary>A row of choices, one selected (filled with the accent).</summary>
    public static FrameworkElement Segmented<T>(IEnumerable<(string Title, T Value)> options, T selected, Action<T> pick, double minWidth = 0)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        var wrap = new Border { Background = Theme.Ink(0.06), CornerRadius = new CornerRadius(Theme.Radius(7)), Padding = new Thickness(2), Child = row, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Left };
        foreach (var (title, value) in options)
        {
            var isOn = EqualityComparer<T>.Default.Equals(value, selected);
            var v = value;
            var t = Text(title, 14, isOn ? Brushes.White : Theme.TextPrimary, FontWeights.Medium);
            t.HorizontalAlignment = HorizontalAlignment.Center;
            var seg = new Border
            {
                Child = t, Padding = new Thickness(14, 5, 14, 5), MinWidth = minWidth, CornerRadius = new CornerRadius(Theme.Radius(6)),
                Background = isOn ? Theme.Accent : Brushes.Transparent, Cursor = Cursors.Hand,
            };
            seg.MouseLeftButtonUp += (_, e) => { e.Handled = true; if (!isOn) pick(v); };
            row.Children.Add(seg);
        }
        return wrap;
    }

    /// <summary>"Columns 2 ⌃⌄": value with small up/down chevrons.</summary>
    public static FrameworkElement Stepper(string label, int value, int min, int max, Action<int> changed)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 4, 0, 4) };
        var l = Text(label, 14, Theme.TextSecondary);
        l.Width = 72; l.TextAlignment = TextAlignment.Right;
        row.Children.Add(l);
        var v = Text(value.ToString(), 15, weight: FontWeights.SemiBold);
        v.Width = 26; v.TextAlignment = TextAlignment.Center;
        row.Children.Add(v);
        var arrows = new StackPanel();
        var up = Icon("", 10, value < max ? Theme.TextSecondary : Theme.Ink(0.2));
        var down = Icon("", 10, value > min ? Theme.TextSecondary : Theme.Ink(0.2));
        foreach (var (arrow, delta) in new[] { (up, 1), (down, -1) })
        {
            var b = new Border { Child = arrow, Padding = new Thickness(4, 1, 4, 1), Background = Brushes.Transparent, Cursor = Cursors.Hand };
            b.MouseLeftButtonUp += (_, e) => { e.Handled = true; var n = value + delta; if (n >= min && n <= max) changed(n); };
            arrows.Children.Add(b);
        }
        row.Children.Add(new Border { Child = arrows, Background = Theme.Ink(0.06), CornerRadius = new CornerRadius(5), Margin = new Thickness(4, 0, 0, 0) });
        return row;
    }

    public static TextBox TextBox(string text, string placeholder = "")
    {
        var box = new TextBox
        {
            Text = text, FontSize = 14, Padding = new Thickness(10, 7, 10, 7), Background = Theme.Ink(0.04), Foreground = Theme.TextPrimary,
            CaretBrush = Theme.Accent, BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1), SelectionBrush = Theme.Accent,
            VerticalContentAlignment = VerticalAlignment.Center,
        };
        if (placeholder.Length > 0) Placeholder(box, placeholder);
        return box;
    }

    /// <summary>Grey hint text inside an empty text box.</summary>
    static void Placeholder(TextBox box, string text)
    {
        var hint = new VisualBrush(new TextBlock { Text = text, Foreground = Theme.TextTertiary, FontSize = 14 })
        { AlignmentX = AlignmentX.Left, AlignmentY = AlignmentY.Center, Stretch = Stretch.None, Transform = new TranslateTransform(12, 0) };
        var plain = box.Background;
        void Update() => box.Background = box.Text.Length == 0 ? hint : plain;
        box.TextChanged += (_, _) => Update();
        box.Loaded += (_, _) => { plain = box.Background is VisualBrush ? plain : box.Background; Update(); };
        Update();
    }

    /// <summary>Search field with a magnifier (Library, overview).</summary>
    public static (FrameworkElement View, TextBox Box) SearchField(string text, string placeholder)
    {
        var box = TextBox(text, placeholder);
        box.Background = Brushes.Transparent;
        box.BorderThickness = new Thickness(0);
        box.Padding = new Thickness(4, 6, 6, 6);
        var line = new DockPanel { LastChildFill = true };
        var icon = Icon("", 13, Theme.TextTertiary);
        icon.Margin = new Thickness(12, 0, 4, 0);
        DockPanel.SetDock(icon, Dock.Left);
        line.Children.Add(icon);
        line.Children.Add(box);
        return (new Border { Child = line, Background = Theme.Ink(0.05), CornerRadius = new CornerRadius(Theme.Radius(8)), BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1) }, box);
    }

    public static ScrollViewer Scroll(UIElement content) => new()
    {
        Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        Focusable = false,
    };

    /// <summary>A colour dot (none = outline).</summary>
    public static Border Dot(Color? c, double size = 12) => new()
    {
        Width = size, Height = size, CornerRadius = new CornerRadius(size / 2), VerticalAlignment = VerticalAlignment.Center,
        Background = c is { } col ? Theme.B(col) : Brushes.Transparent, BorderBrush = Theme.TextTertiary, BorderThickness = new Thickness(c == null ? 1 : 0),
    };

    /// <summary>Square icon tile (history clock, LES import, stats rows).</summary>
    public static Border IconTile(string glyph, Brush brush, double size = 34) => new()
    {
        Width = size, Height = size, CornerRadius = new CornerRadius(Theme.Radius(8)), Background = Theme.Ink(0.06),
        Child = new TextBlock { Text = glyph, FontFamily = Theme.Icons, FontSize = size * 0.45, Foreground = brush, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
    };

    // MARK: Themed menu

    /// <summary>One line of a menu: a title with an action, a submenu, a separator ("-"), or a check mark.</summary>
    public sealed record MenuItem(string Title, Action? Action = null, IReadOnlyList<MenuItem>? Submenu = null, bool Checked = false, string? Glyph = null, Color? Swatch = null);

    public static MenuItem Separator => new("-");

    /// <summary>A menu in the theme's colours (not Windows' white one), at the mouse or under an element.</summary>
    public static void Menu(FrameworkElement at, IReadOnlyList<MenuItem> items, bool atMouse = true)
    {
        var popup = new Popup
        {
            PlacementTarget = at, Placement = atMouse ? PlacementMode.MousePoint : PlacementMode.Bottom, StaysOpen = false,
            AllowsTransparency = true, PopupAnimation = PopupAnimation.Fade,
        };
        var subs = new List<Popup>();
        popup.Child = MenuPanel(items, () => popup.IsOpen = false, subs);
        popup.Closed += (_, _) => { foreach (var p in subs) p.IsOpen = false; };
        popup.IsOpen = true;
    }

    static FrameworkElement MenuPanel(IReadOnlyList<MenuItem> items, Action close, List<Popup> subs)
    {
        var stack = new StackPanel { MinWidth = 210 };
        foreach (var item in items)
        {
            if (item.Title == "-") { stack.Children.Add(new Border { Height = 1, Background = Theme.Stroke, Margin = new Thickness(6, 4, 6, 4) }); continue; }
            var line = new DockPanel { LastChildFill = true };
            if (item.Submenu != null) { var chev = Icon("", 9, Theme.TextTertiary); DockPanel.SetDock(chev, Dock.Right); line.Children.Add(chev); }
            var lead = new Border { Width = 22 };
            if (item.Checked) lead.Child = Icon("", 11, Theme.Accent);
            else if (item.Swatch is { } sw) lead.Child = Dot(sw, 10);
            else if (item.Glyph != null) lead.Child = Icon(item.Glyph, 12, Theme.TextSecondary);
            DockPanel.SetDock(lead, Dock.Left);
            line.Children.Add(lead);
            var enabled = item.Action != null || item.Submenu != null;
            line.Children.Add(Text(item.Title, 13, enabled ? Theme.TextPrimary : Theme.TextTertiary));
            var row = new Border { Child = line, Padding = new Thickness(8, 6, 10, 6), CornerRadius = new CornerRadius(Theme.Radius(5)), Background = Brushes.Transparent };
            if (enabled)
            {
                row.Cursor = Cursors.Hand;
                Popup? sub = null;
                row.MouseEnter += (_, _) =>
                {
                    row.Background = AccentTint(0.85);
                    foreach (var t in line.Children.OfType<TextBlock>()) t.Foreground = Theme.OnAccent;
                    if (item.Submenu != null)
                    {
                        foreach (var open in subs.Where(p => p.IsOpen && p.PlacementTarget is FrameworkElement t && t.Parent == row.Parent)) open.IsOpen = false;
                        sub = new Popup { PlacementTarget = row, Placement = PlacementMode.Right, StaysOpen = true, AllowsTransparency = true };
                        var s2 = sub;
                        sub.Child = MenuPanel(item.Submenu, () => { s2.IsOpen = false; close(); }, subs);
                        subs.Add(sub);
                        sub.IsOpen = true;
                    }
                };
                row.MouseLeave += (_, e) =>
                {
                    row.Background = Brushes.Transparent;
                    foreach (var t in line.Children.OfType<TextBlock>()) t.Foreground = Theme.TextPrimary;

                };
                if (item.Action != null) row.MouseLeftButtonUp += (_, e) => { e.Handled = true; close(); item.Action(); };
            }
            stack.Children.Add(row);
        }
        return new Border
        {
            Child = stack, Background = Raised, BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1), Padding = new Thickness(5),
            CornerRadius = new CornerRadius(Theme.Radius(9)), Margin = new Thickness(0, 0, 10, 10),
            Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 4, Opacity = 0.45, Color = Colors.Black },
        };
    }

    // MARK: Themed dialogs

    static Window Dialog(Window owner, UIElement content)
    {
        var w = new Window
        {
            Owner = owner, WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent, ResizeMode = ResizeMode.NoResize,
            SizeToContent = SizeToContent.WidthAndHeight, WindowStartupLocation = WindowStartupLocation.CenterOwner, ShowInTaskbar = false,
            FontFamily = Theme.Font,
        };
        w.Content = new Border
        {
            Background = Surface, BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(Theme.Radius(12)),
            Padding = new Thickness(24, 20, 24, 18), Child = content, Margin = new Thickness(16),
            Effect = new DropShadowEffect { BlurRadius = 24, ShadowDepth = 6, Opacity = 0.5, Color = Colors.Black },
        };
        w.MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) try { w.DragMove(); } catch (InvalidOperationException) { } };
        return w;
    }

    static FrameworkElement Buttons(params UIElement[] buttons)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 18, 0, 0) };
        foreach (var b in buttons) row.Children.Add(b);
        return row;
    }

    /// <summary>Asks for a line of text (rename, new name). Null when cancelled.</summary>
    public static string? Ask(Window owner, string title, string initial, string? detail = null)
    {
        string? result = null;
        var box = TextBox(initial);
        box.Width = 360;
        box.Margin = new Thickness(0, 14, 0, 0);
        var panel = new StackPanel();
        panel.Children.Add(Text(title, 16, weight: FontWeights.Bold));
        if (detail != null) { var d = Caption(detail); d.MaxWidth = 360; panel.Children.Add(d); }
        panel.Children.Add(box);
        Window? w = null;
        panel.Children.Add(Buttons(Button(Loc.T("Abbrechen", "Cancel"), () => w!.Close()), Primary("OK", () => { result = box.Text.Trim(); w!.Close(); })));
        w = Dialog(owner, panel);
        box.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter) { result = box.Text.Trim(); w.Close(); }
            if (e.Key == Key.Escape) w.Close();
        };
        w.Loaded += (_, _) => { box.Focus(); box.SelectAll(); };
        w.ShowDialog();
        return result;
    }

    public static bool Confirm(Window owner, string title, string text, string ok)
    {
        var result = false;
        var panel = new StackPanel { MaxWidth = 420 };
        panel.Children.Add(Text(title, 16, weight: FontWeights.Bold, wrap: true));
        var t = Text(text, 13.5, Theme.TextSecondary, wrap: true);
        t.Margin = new Thickness(0, 8, 0, 0);
        panel.Children.Add(t);
        Window? w = null;
        panel.Children.Add(Buttons(Button(Loc.T("Abbrechen", "Cancel"), () => w!.Close()), Primary(ok, () => { result = true; w!.Close(); })));
        w = Dialog(owner, panel);
        w.KeyDown += (_, e) => { if (e.Key == Key.Escape) w.Close(); if (e.Key == Key.Enter) { result = true; w.Close(); } };
        w.ShowDialog();
        return result;
    }

    public static void Tell(Window owner, string title, string text)
    {
        var panel = new StackPanel { MaxWidth = 420 };
        panel.Children.Add(Text(title, 16, weight: FontWeights.Bold, wrap: true));
        var t = Text(text, 13.5, Theme.TextSecondary, wrap: true);
        t.Margin = new Thickness(0, 8, 0, 0);
        panel.Children.Add(t);
        Window? w = null;
        panel.Children.Add(Buttons(Primary("OK", () => w!.Close())));
        w = Dialog(owner, panel);
        w.ShowDialog();
    }

    /// <summary>The glow of selected sidebar items and categories: accent outline with a soft halo.</summary>
    public static void Glow(Border b)
    {
        b.BorderBrush = Theme.Accent;
        b.BorderThickness = new Thickness(1.5);
        b.Effect = new DropShadowEffect { Color = AccentColor, BlurRadius = 16, ShadowDepth = 0, Opacity = 0.45 };
    }
}
