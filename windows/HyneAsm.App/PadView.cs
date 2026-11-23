using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>What a pad shows (a panel row or a menu entry in the settings preview).</summary>
readonly record struct PadData(string Title, string IconID, string? ColorID, bool IsFolder, int ChildCount, bool IsNew, bool IsAvailable, int? Number)
{
    public static PadData Of(PanelRow row, int? number) =>
        new(row.Title, row.IconID, row.ColorID, row.FolderID != null, row.ChildCount, row.IsNew, row.IsAvailable, number);
}

/// <summary>One entry drawn like a lit hardware pad (Theme.swift LauncherPad / LauncherListRow): a dark top-lit plate,
/// key number, icon in the label colour, name, badges, a glowing stripe; filled and glowing when active.
/// Shared by the panel and the settings preview, so both look the same.</summary>
static class PadView
{
    public static Border Build(PadData d, bool grid, bool active, bool selected = false)
    {
        // Folders stand out in the accent unless they have their own colour label.
        var label = Theme.LabelColor(d.ColorID);
        var color = label ?? (d.IsFolder ? Theme.Current.Accent : (Color?)null);
        var lit = color ?? Theme.Current.Accent;
        var onLit = Theme.Current.OnLitPad;
        Brush A(byte alpha) => Theme.B(Color.FromArgb(alpha, onLit.R, onLit.G, onLit.B));
        var iconBrush = active ? A(190) : color is { } ic ? Theme.B(ic) : Theme.TextTertiary;
        var titleBrush = active ? Theme.B(onLit) : d.IsAvailable ? Theme.TextPrimary : Theme.TextTertiary;
        var numberBrush = active ? A(166) : Theme.TextTertiary;
        var content = new Grid();
        if (grid)
        {
            var center = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 8, 6, 12) };
            var icon = Theme.Icon(d.IconID, 17, iconBrush);
            icon.Height = 20;
            center.Children.Add(icon);
            center.Children.Add(new TextBlock
            {
                Text = d.Title, FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = titleBrush, TextWrapping = TextWrapping.Wrap,
                TextAlignment = TextAlignment.Center, MaxHeight = 32, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 6, 0, 0),
            });
            content.Children.Add(center);
            if (d.Number is { } n && n < 9)
                content.Children.Add(new TextBlock { Text = (n + 1).ToString(), FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = numberBrush, Margin = new Thickness(7, 5, 0, 0), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top });
            var badges = Badges(d);
            badges.HorizontalAlignment = HorizontalAlignment.Right;
            badges.VerticalAlignment = VerticalAlignment.Top;
            badges.Margin = new Thickness(5);
            content.Children.Add(badges);
            var stripe = (FrameworkElement)Theme.Stripe(active, color, 72, 3.5);
            stripe.VerticalAlignment = VerticalAlignment.Bottom;
            stripe.Margin = new Thickness(0, 0, 0, 6);
            content.Children.Add(stripe);
        }
        else
        {
            var line = new DockPanel { LastChildFill = true, Margin = new Thickness(10, 0, 10, 2) };
            var number = new TextBlock { Text = d.Number is { } n && n < 9 ? (n + 1).ToString() : "", Width = 12, FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = numberBrush, VerticalAlignment = VerticalAlignment.Center };
            DockPanel.SetDock(number, Dock.Left);
            line.Children.Add(number);
            var icon = Theme.Icon(d.IconID, 15, iconBrush);
            icon.Width = 20;
            icon.Margin = new Thickness(9, 0, 9, 0);
            DockPanel.SetDock(icon, Dock.Left);
            line.Children.Add(icon);
            var badges = Badges(d);
            badges.VerticalAlignment = VerticalAlignment.Center;
            DockPanel.SetDock(badges, Dock.Right);
            line.Children.Add(badges);
            line.Children.Add(new TextBlock { Text = d.Title, FontSize = 12.5, FontWeight = FontWeights.SemiBold, Foreground = titleBrush, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center });
            content.Children.Add(line);
            var stripe = (FrameworkElement)Theme.Stripe(active, color, 64, 3);
            stripe.VerticalAlignment = VerticalAlignment.Bottom;
            stripe.Margin = new Thickness(0, 0, 0, 4);
            content.Children.Add(stripe);
        }
        var plate = Theme.Plate(content, active, lit);
        if (selected && !active)
        {
            plate.BorderBrush = Theme.Accent;
            plate.BorderThickness = new Thickness(1.5);
        }
        plate.Opacity = d.IsAvailable ? 1 : 0.5;
        return plate;
    }

    static StackPanel Badges(PadData d)
    {
        var badges = new StackPanel { Orientation = Orientation.Horizontal };
        if (d.IsNew) badges.Children.Add(Theme.NewBadge());
        if (d.IsFolder)
            badges.Children.Add(new Border
            {
                Background = Theme.Ink(0.09), CornerRadius = new CornerRadius(8), Padding = new Thickness(5, 1, 5, 1), Margin = new Thickness(3, 0, 0, 0),
                Child = new TextBlock { Text = d.ChildCount.ToString(), FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = Theme.TextSecondary },
            });
        return badges;
    }
}
