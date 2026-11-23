using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>A folder's entries as a side list right beside its pad (over whatever is there), like the Mac's.
/// Opens on hover, closes shortly after the pointer leaves both; a click inserts.</summary>
sealed class FolderFlyout : Overlay
{
    readonly PanelWindow panel;
    IReadOnlyList<PanelRow> rows = Array.Empty<PanelRow>();
    PanelSize size = PanelSize.Default;
    int? hovered;

    public FolderFlyout(PanelWindow panel) { this.panel = panel; }

    public void Show(IReadOnlyList<PanelRow> rows, Native.POINT topLeft, PanelSize size)
    {
        this.rows = rows;
        this.size = size;
        hovered = null;
        Render();
        ShowAt(topLeft);
    }

    void Render()
    {
        FontFamily = Theme.Display;
        var stack = new StackPanel { Margin = new Thickness(8) };
        var width = Math.Max(220, Math.Min(size.ColumnWidth, 320));
        var height = Math.Max(38, size.ItemHeight);
        for (var i = 0; i < rows.Count; i++)
        {
            var index = i;
            var row = rows[i];
            var holder = new Border { Width = width, Height = height, Margin = new Thickness(0, 0, 0, 4), Cursor = Cursors.Hand, Background = Brushes.Transparent };
            holder.Child = PadView.Build(PadData.Of(row, i), grid: false, active: false);
            holder.MouseEnter += (_, _) => { hovered = index; holder.Child = PadView.Build(PadData.Of(row, index), false, true); };
            holder.MouseLeave += (_, _) => { if (hovered == index) hovered = null; holder.Child = PadView.Build(PadData.Of(row, index), false, false); };
            holder.MouseLeftButtonUp += (_, _) => { if (row.IsAvailable) { Hide(); panel.InsertFromFlyout(row); } };
            stack.Children.Add(holder);
        }
        if (rows.Count == 0)
            stack.Children.Add(new TextBlock { Text = Loc.T("Leerer Ordner", "Empty folder"), Foreground = Theme.TextTertiary, FontSize = 12, Margin = new Thickness(10) });
        Content = Theme.Chrome(new ScrollViewer { Content = stack, MaxHeight = 640, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }, 10);
    }
}
