using System.Text.Json.Serialization;

namespace HyneAsm.Core;

/// <summary>Helpers for laying out the panel's entries (see <see cref="PanelPage"/> for where each entry sits on a page).</summary>
public static class PanelGrid
{
    /// <summary>Indices in display order while entry <paramref name="from"/> is dragged to slot <paramref name="to"/>.</summary>
    public static List<int> Order(int count, int from, int to)
    {
        var order = Enumerable.Range(0, Math.Max(count, 0)).ToList();
        if (from < 0 || from >= order.Count || to < 0 || to >= order.Count) return order;
        var moved = order[from];
        order.RemoveAt(from);
        order.Insert(to, moved);
        return order;
    }
}

/// <summary>How big the panel's entries are: dragged with the panel's resize grip, kept in the config.</summary>
public sealed record PanelSize
{
    public static readonly (double Lower, double Upper) WidthRange = (240, 560);
    public static readonly (double Lower, double Upper) HeightRange = (34, 64);
    /// <summary>A fresh copy of the default on every call.</summary>
    public static PanelSize Default => new(316, 42);

    [JsonRequired] public double ColumnWidth { get; set; }
    [JsonRequired] public double ItemHeight { get; set; }

    /// <summary>Values outside the ranges are pulled back in (also when read from JSON).</summary>
    [JsonConstructor]
    public PanelSize(double columnWidth, double itemHeight)
    {
        ColumnWidth = Math.Min(Math.Max(columnWidth, WidthRange.Lower), WidthRange.Upper);
        ItemHeight = Math.Min(Math.Max(itemHeight, HeightRange.Lower), HeightRange.Upper);
    }
}

/// <summary>How many pads one page of the panel shows: columns × rows (each 2–8, default 3 × 3).</summary>
public sealed record PanelGridSize
{
    public static readonly (int Lower, int Upper) Range = (2, 8);
    /// <summary>A fresh copy of the default on every call.</summary>
    public static PanelGridSize Default => new(3, 3);

    int columns, rows;

    [JsonRequired] public int Columns { get => columns; set => columns = Clamp(value); }
    [JsonRequired] public int Rows { get => rows; set => rows = Clamp(value); }
    [JsonIgnore] public int PageSize => Columns * Rows;

    [JsonConstructor]
    public PanelGridSize(int columns, int rows) { Columns = columns; Rows = rows; }

    static int Clamp(int v) => Math.Min(Math.Max(v, Range.Lower), Range.Upper);
}

/// <summary>Where the panel lists the categories: a tab bar on top, or a column on the left.</summary>
public enum CategoryPlacement { Top, Left }

/// <summary>How the panel shows a page: square pads in a grid, or rows of a list.</summary>
public enum PanelStyle { Grid, List }

/// <summary>Size of a list page: columns side by side (1–4), each up to 9 rows (keys 1–9 run down the first column).</summary>
public sealed record PanelListSize
{
    public static readonly (int Lower, int Upper) ColumnRange = (1, 4);
    public static readonly (int Lower, int Upper) RowRange = (2, 9);
    /// <summary>A fresh copy of the default on every call.</summary>
    public static PanelListSize Default => new(2, 9);

    int columns, rows;

    [JsonRequired] public int Columns { get => columns; set => columns = Clamp(value, ColumnRange); }
    [JsonRequired] public int Rows { get => rows; set => rows = Clamp(value, RowRange); }
    [JsonIgnore] public int PageSize => Columns * Rows;

    [JsonConstructor]
    public PanelListSize(int columns, int rows) { Columns = columns; Rows = rows; }

    static int Clamp(int v, (int Lower, int Upper) r) => Math.Min(Math.Max(v, r.Lower), r.Upper);
}

/// <summary>One page of the panel: how many entries it holds and where each sits. A grid fills row by row
/// (like the keys 1–9 on a keypad); a list fills its left column first, then the next.</summary>
public readonly record struct PanelPage
{
    public int Columns { get; }
    public int Rows { get; }
    public bool ColumnMajor { get; }
    public int Size => Columns * Rows;

    public PanelPage(int columns, int rows, bool columnMajor)
    {
        Columns = Math.Max(columns, 1);
        Rows = Math.Max(rows, 1);
        ColumnMajor = columnMajor;
    }

    public PanelPage(PanelStyle style, PanelGridSize grid, PanelListSize list)
        : this(style == PanelStyle.Grid ? grid.Columns : list.Columns, style == PanelStyle.Grid ? grid.Rows : list.Rows,
               style != PanelStyle.Grid) { }

    /// <summary>Slot (0-based, within the page) at a row and column.</summary>
    public int Slot(int row, int column) => ColumnMajor ? column * Rows + row : row * Columns + column;

    /// <summary>Row and column of a slot within the page.</summary>
    public (int Row, int Column) Position(int slot)
    {
        var s = slot % Size;
        return ColumnMajor ? (s % Rows, s / Rows) : (s / Columns, s % Columns);
    }
}
