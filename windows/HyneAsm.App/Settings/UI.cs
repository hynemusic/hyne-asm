using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Settings surfaces per theme (the Mac's canvas / sidebar / surface / raised / hover values).</summary>
sealed record SettingsColors(Color Canvas, Color Sidebar, Color Surface, Color Raised, Color Hover)
{
    static Color H(uint v) => Color.FromRgb((byte)(v >> 16), (byte)(v >> 8), (byte)v);

    public static SettingsColors For(AppTheme t) => t switch
    {
        AppTheme.Ableton => new(H(0x1E1E1E), H(0x262626), H(0x2C2C2C), H(0x3A3A3A), H(0x464646)),
        AppTheme.Hyne => new(H(0x171717), H(0x222222), H(0x2A2A2A), H(0x3A3A3A), H(0x424242)),
        AppTheme.Light => new(H(0xF5F5F7), H(0xEBEBEE), Colors.White, H(0xF0F0F3), H(0xE4E4E9)),
        AppTheme.Retro => new(H(0xBFBFC1), H(0xA9A9AC), H(0xCBCBCD), H(0xD6D6D8), H(0xDFDFE1)),
        _ => new(H(0x0C0B0A), H(0x141311), H(0x121110), H(0x1D1C1A), H(0x262421)),
    };

    public static SettingsColors Current => For(Theme.Id);
}

/// <summary>Small building blocks for the settings window, drawn in the theme (no Windows default chrome).</summary>
static class UI
{
    static SettingsColors C => SettingsColors.Current;
    public static Brush Canvas => Theme.B(C.Canvas);
    public static Brush Sidebar => Theme.B(C.Sidebar);
    public static Brush Surface => Theme.B(C.Surface);
    public static Brush Raised => Theme.B(C.Raised);
    public static Brush Hover => Theme.B(C.Hover);

    public static TextBlock Text(string text, double size = 13, Brush? brush = null, FontWeight? weight = null, bool wrap = false) => new()
    {
        Text = text, FontSize = size, Foreground = brush ?? Theme.TextPrimary, FontWeight = weight ?? FontWeights.Normal,
        TextWrapping = wrap ? TextWrapping.Wrap : TextWrapping.NoWrap, TextTrimming = wrap ? TextTrimming.None : TextTrimming.CharacterEllipsis,
        VerticalAlignment = VerticalAlignment.Center,
    };

    public static TextBlock Title(string text) => Text(text, 22, weight: FontWeights.SemiBold);
    public static TextBlock Caption(string text) => Text(text, 12, Theme.TextTertiary, wrap: true);

    /// <summary>Small uppercase label that opens a group of rows ("YOUR PRESETS", "PLUGIN WINDOWS").</summary>
    public static TextBlock Section(string text)
    {
        var t = Text(text.ToUpperInvariant(), 11, Theme.TextTertiary, FontWeights.SemiBold);
        t.Margin = new Thickness(2, 18, 0, 6);
        return t;
    }

    public static Border Card(UIElement child, Thickness? padding = null) => new()
    {
        Background = Raised, CornerRadius = new CornerRadius(Theme.Radius(10)), BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1),
        Padding = padding ?? new Thickness(14, 10, 14, 10), Child = child,
    };

    public static Border Button(string title, Action onClick, bool primary = false, string? icon = null, string? tip = null)
    {
        var content = new StackPanel { Orientation = Orientation.Horizontal };
        var fg = primary ? Theme.OnAccent : Theme.TextPrimary;
        if (icon != null) content.Children.Add(new TextBlock { Text = icon, FontFamily = Theme.Icons, FontSize = 12, Foreground = fg, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, title.Length > 0 ? 6 : 0, 0) });
        if (title.Length > 0) content.Children.Add(Text(title, 12.5, fg, FontWeights.SemiBold));
        var normal = primary ? Theme.Accent : Hover;
        var b = new Border
        {
            Child = content, Background = normal, CornerRadius = new CornerRadius(Theme.Radius(7)), Padding = new Thickness(11, 5, 11, 5),
            Cursor = Cursors.Hand, Margin = new Thickness(0, 0, 6, 0), ToolTip = tip, VerticalAlignment = VerticalAlignment.Center,
            BorderBrush = Theme.Stroke, BorderThickness = new Thickness(primary ? 0 : 1),
        };
        b.MouseEnter += (_, _) => b.Opacity = 0.85;
        b.MouseLeave += (_, _) => b.Opacity = 1;
        b.MouseLeftButtonUp += (_, e) => { e.Handled = true; onClick(); };
        return b;
    }

    public static Border IconButton(string glyph, Action onClick, string tip) => Button("", onClick, icon: glyph, tip: tip);

    /// <summary>An on/off switch.</summary>
    public static FrameworkElement Toggle(bool on, Action<bool> changed)
    {
        var knob = new Border { Width = 16, Height = 16, CornerRadius = new CornerRadius(8), Background = Brushes.White, HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left, Margin = new Thickness(2) };
        var track = new Border { Width = 38, Height = 20, CornerRadius = new CornerRadius(10), Background = on ? Theme.Accent : Theme.Ink(0.18), Child = knob, Cursor = Cursors.Hand, VerticalAlignment = VerticalAlignment.Center };
        track.MouseLeftButtonUp += (_, e) => { e.Handled = true; changed(!on); };
        return track;
    }

    /// <summary>A row of choices, one selected.</summary>
    public static FrameworkElement Segmented<T>(IEnumerable<(string Title, T Value)> options, T selected, Action<T> pick)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        var wrap = new Border { Background = Theme.Ink(0.06), CornerRadius = new CornerRadius(Theme.Radius(8)), Padding = new Thickness(2), Child = row, VerticalAlignment = VerticalAlignment.Center };
        foreach (var (title, value) in options)
        {
            var isOn = EqualityComparer<T>.Default.Equals(value, selected);
            var v = value;
            var seg = new Border
            {
                Child = Text(title, 12.5, isOn ? Theme.OnAccent : Theme.TextSecondary, FontWeights.SemiBold), Padding = new Thickness(12, 4, 12, 4),
                CornerRadius = new CornerRadius(Theme.Radius(6)), Background = isOn ? Theme.Accent : Brushes.Transparent, Cursor = Cursors.Hand,
            };
            seg.MouseLeftButtonUp += (_, e) => { e.Handled = true; if (!isOn) pick(v); };
            row.Children.Add(seg);
        }
        return wrap;
    }

    /// <summary>− value + within a range.</summary>
    public static FrameworkElement Stepper(int value, int min, int max, Action<int> changed)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        row.Children.Add(IconButton("", () => { if (value > min) changed(value - 1); }, "−"));
        var t = Text(value.ToString(), 13, weight: FontWeights.SemiBold);
        t.MinWidth = 22; t.TextAlignment = TextAlignment.Center; t.Margin = new Thickness(0, 0, 6, 0);
        row.Children.Add(t);
        row.Children.Add(IconButton("", () => { if (value < max) changed(value + 1); }, "+"));
        return row;
    }

    public static TextBox TextBox(string text, string placeholder = "")
    {
        var box = new TextBox
        {
            Text = text, FontSize = 13, Padding = new Thickness(8, 5, 8, 5), Background = Theme.Ink(0.06), Foreground = Theme.TextPrimary,
            CaretBrush = Theme.Accent, BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1), SelectionBrush = Theme.Accent,
            VerticalContentAlignment = VerticalAlignment.Center, Tag = placeholder,
        };
        if (placeholder.Length > 0) box.ToolTip = placeholder;
        return box;
    }

    /// <summary>Title and explanation on the left, a control on the right.</summary>
    public static FrameworkElement Row(string title, string? detail, UIElement? trailing)
    {
        var grid = new Grid { Margin = new Thickness(0, 6, 0, 6) };
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 16, 0) };
        text.Children.Add(Text(title, 13, weight: FontWeights.SemiBold));
        if (detail != null) text.Children.Add(Caption(detail));
        grid.Children.Add(text);
        if (trailing != null) { Grid.SetColumn(trailing, 1); grid.Children.Add(trailing); }
        return grid;
    }

    public static Border Divider() => new() { Height = 1, Background = Theme.Stroke, Margin = new Thickness(0, 4, 0, 4) };

    /// <summary>A popup menu at an element (themed by Windows; the content is short lists).</summary>
    public static void Menu(FrameworkElement at, IEnumerable<(string Title, Action? Action)> items)
    {
        var menu = new ContextMenu { PlacementTarget = at, Placement = PlacementMode.Bottom };
        foreach (var (title, action) in items)
        {
            if (title == "-") { menu.Items.Add(new Separator()); continue; }
            var item = new MenuItem { Header = title, IsEnabled = action != null };
            if (action != null) item.Click += (_, _) => action();
            menu.Items.Add(item);
        }
        menu.IsOpen = true;
    }

    /// <summary>Asks for a line of text (rename, new name). Null when cancelled.</summary>
    public static string? Ask(Window owner, string title, string initial)
    {
        var box = TextBox(initial);
        box.Width = 320;
        var dialog = new Window
        {
            Owner = owner, Title = "HYNE ASM", SizeToContent = SizeToContent.WidthAndHeight, ResizeMode = ResizeMode.NoResize,
            WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = Surface, ShowInTaskbar = false, FontFamily = Theme.Font,
        };
        string? result = null;
        var panel = new StackPanel { Margin = new Thickness(20) };
        panel.Children.Add(Text(title, 14, weight: FontWeights.SemiBold));
        box.Margin = new Thickness(0, 10, 0, 14);
        panel.Children.Add(box);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(Button(Loc.T("Abbrechen", "Cancel"), () => dialog.Close()));
        buttons.Children.Add(Button("OK", () => { result = box.Text.Trim(); dialog.Close(); }, primary: true));
        panel.Children.Add(buttons);
        dialog.Content = panel;
        box.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter) { result = box.Text.Trim(); dialog.Close(); }
            if (e.Key == Key.Escape) dialog.Close();
        };
        dialog.Loaded += (_, _) => { box.Focus(); box.SelectAll(); };
        dialog.ShowDialog();
        return string.IsNullOrEmpty(result) ? null : result;
    }

    public static bool Confirm(Window owner, string title, string text) =>
        MessageBox.Show(owner, text, title, MessageBoxButton.OKCancel, MessageBoxImage.Question) == MessageBoxResult.OK;

    public static ScrollViewer Scroll(UIElement content) => new()
    {
        Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
    };

    /// <summary>A colour dot (none = outline).</summary>
    public static Border Dot(Color? c, double size = 12) => new()
    {
        Width = size, Height = size, CornerRadius = new CornerRadius(size / 2), VerticalAlignment = VerticalAlignment.Center,
        Background = c is { } col ? Theme.B(col) : Brushes.Transparent, BorderBrush = Theme.TextTertiary, BorderThickness = new Thickness(c == null ? 1 : 0),
    };
}

/// <summary>Shortcut text and recording (Windows keys, stored in the Mac format).</summary>
static class Keys
{
    public static string Describe(KeyCombo? combo)
    {
        if (combo == null) return Loc.T("Aus", "Off");
        if (KeyTranslation.ToWindows(combo) is not { } w) return "?";
        var parts = new List<string>();
        if (w.mods.HasFlag(WinModifiers.Ctrl)) parts.Add(Loc.T("Strg", "Ctrl"));
        if (w.mods.HasFlag(WinModifiers.Alt)) parts.Add("Alt");
        if (w.mods.HasFlag(WinModifiers.Shift)) parts.Add(Loc.T("Umschalt", "Shift"));
        if (w.mods.HasFlag(WinModifiers.Win)) parts.Add("Win");
        parts.Add(KeyName(w.vk));
        return string.Join("+", parts);
    }

    public static string KeyName(ushort vk) => vk switch
    {
        0x20 => Loc.T("Leertaste", "Space"), 0x0D => Loc.T("Eingabe", "Enter"), 0x1B => "Esc", 0x09 => "Tab", 0x08 => Loc.T("Rücktaste", "Backspace"),
        0x2E => Loc.T("Entf", "Del"), 0x25 => "←", 0x26 => "↑", 0x27 => "→", 0x28 => "↓",
        >= 0x30 and <= 0x39 or >= 0x41 and <= 0x5A => ((char)vk).ToString(),
        >= 0x70 and <= 0x87 => "F" + (vk - 0x6F),
        _ => KeyInterop.KeyFromVirtualKey(vk).ToString(),
    };

    /// <summary>The combo a WPF key event means, or null for lone modifiers.</summary>
    public static KeyCombo? From(KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin) return null;
        var m = WinModifiers.None;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) m |= WinModifiers.Ctrl;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Alt)) m |= WinModifiers.Alt;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) m |= WinModifiers.Shift;
        if (Keyboard.IsKeyDown(Key.LWin) || Keyboard.IsKeyDown(Key.RWin)) m |= WinModifiers.Win;
        return KeyTranslation.FromWindows((ushort)KeyInterop.VirtualKeyFromKey(key), m);
    }

    /// <summary>A button showing the combo; click, then press the new one (Esc cancels, Backspace clears).</summary>
    public static FrameworkElement Recorder(KeyCombo? combo, Action<KeyCombo?> changed, bool allowClear = true, string? emptyText = null)
    {
        string Shown() => combo == null && emptyText != null ? emptyText : Describe(combo);
        var label = UI.Text(Shown(), 12.5, combo == null ? Theme.TextTertiary : Theme.TextPrimary, FontWeights.SemiBold);
        var box = new Border
        {
            Child = label, Padding = new Thickness(12, 5, 12, 5), MinWidth = 120, CornerRadius = new CornerRadius(Theme.Radius(7)),
            Background = Theme.Ink(0.06), BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1), Cursor = Cursors.Hand,
            Focusable = true, FocusVisualStyle = null, VerticalAlignment = VerticalAlignment.Center,
            ToolTip = Loc.T("Klicken, dann die neue Kombination drücken. Esc bricht ab, Rücktaste löscht.", "Click, then press the new combination. Esc cancels, Backspace clears."),
        };
        var recording = false;
        void Stop() { recording = false; box.BorderBrush = Theme.Stroke; label.Text = Shown(); }
        box.MouseLeftButtonUp += (_, _) =>
        {
            recording = !recording;
            if (!recording) { Stop(); return; }
            box.BorderBrush = Theme.Accent;
            label.Text = Loc.T("Tasten drücken …", "Press keys …");
            box.Focus();
            Keyboard.Focus(box);
        };
        box.LostKeyboardFocus += (_, _) => { if (recording) Stop(); };
        box.PreviewKeyDown += (_, e) =>
        {
            if (!recording) return;
            e.Handled = true;
            var key = e.Key == Key.System ? e.SystemKey : e.Key;
            if (key == Key.Escape && Keyboard.Modifiers == ModifierKeys.None) { Stop(); return; }
            if (key == Key.Back && Keyboard.Modifiers == ModifierKeys.None && allowClear) { recording = false; changed(null); return; }
            if (From(e) is { } c) { recording = false; changed(c); }
        };
        return box;
    }

    /// <summary>Live and Windows shortcuts the combo would take away (shown under a recorder).</summary>
    public static string? ConflictText(KeyCombo combo)
    {
        var hits = KnownShortcuts.Conflicts(combo);
        if (hits.Count == 0) return null;
        return Loc.T("Belegt: ", "Already used: ") + string.Join(", ", hits.Take(3).Select(h => $"{h.Title} ({h.App})"));
    }
}
