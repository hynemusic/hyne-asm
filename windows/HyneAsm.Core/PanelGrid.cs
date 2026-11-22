using System.Text.Json.Serialization;

namespace HyneAsm.Core;

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
