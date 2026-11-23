using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>A folder's entries as a side list right beside its pad (over whatever is there), like the Mac's, in the
/// panel's own style: pads in a grid, or rows of a list. Opens on hover, closes shortly after the pointer leaves
/// both; a click inserts.</summary>
sealed class FolderFlyout : Overlay
{
    readonly PanelWindow panel;
    IReadOnlyList<PanelRow> rows = Array.Empty<PanelRow>();
    bool grid;
    double itemWidth, itemHeight;
    int? hovered;

    public FolderFlyout(PanelWindow panel) { this.panel = panel; }

    public void Show(IReadOnlyList<PanelRow> rows, Native.POINT topLeft, bool grid, double itemWidth, double itemHeight)
    {
        this.rows = rows;
        this.grid = grid;
        this.itemWidth = itemWidth;
        this.itemHeight = itemHeight;
        hovered = null;
        Render();
        ShowAt(topLeft);
    }

    void Render()
    {
        FontFamily = Theme.Display;
        Panel items;
        if (grid)
        {
            // Pads like the panel's, three to a row (fewer when the folder is small).
            items = new WrapPanel { Width = Math.Min(3, Math.Max(1, rows.Count)) * (itemWidth + 6), Margin = new Thickness(5) };
        }
        else items = new StackPanel { Margin = new Thickness(8) };
        for (var i = 0; i < rows.Count; i++)
        {
            var index = i;
            var row = rows[i];
            var holder = new Border
            {
                Width = grid ? itemWidth : Math.Max(220, Math.Min(itemWidth, 320)), Height = grid ? itemHeight : Math.Max(38, itemHeight),
                Margin = grid ? new Thickness(3) : new Thickness(0, 0, 0, 4), Cursor = Cursors.Hand, Background = Brushes.Transparent,
            };
            holder.Child = PadView.Build(PadData.Of(row, i), grid, active: false);
            holder.MouseEnter += (_, _) => { hovered = index; holder.Child = PadView.Build(PadData.Of(row, index), grid, true); };
            holder.MouseLeave += (_, _) => { if (hovered == index) hovered = null; holder.Child = PadView.Build(PadData.Of(row, index), grid, false); };
            holder.MouseLeftButtonUp += (_, _) => { if (row.IsAvailable) { Hide(); panel.InsertFromFlyout(row); } };
            items.Children.Add(holder);
        }
        if (rows.Count == 0)
            items.Children.Add(new TextBlock { Text = Loc.T("Leerer Ordner", "Empty folder"), Foreground = Theme.TextTertiary, FontSize = 12, Margin = new Thickness(10) });
        Content = Theme.Chrome(new ScrollViewer { Content = items, MaxHeight = 640, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }, 10);
    }
}
