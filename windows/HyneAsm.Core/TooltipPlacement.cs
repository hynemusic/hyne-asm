namespace HyneAsm.Core;

/// <summary>CoreGraphics' <c>CGSize</c>.</summary>
public readonly record struct Size(double Width, double Height);

/// <summary>CoreGraphics' <c>CGRect</c>: origin and size as given; the edges (<see cref="MinX"/> …) are standardized,
/// so a negative width or height counts from the other edge, and <c>==</c> compares the standardized rectangles.</summary>
public readonly record struct Rect(double X, double Y, double Width, double Height)
{
    public double MinX => Math.Min(X, X + Width);
    public double MaxX => Math.Max(X, X + Width);
    public double MidX => X + Width / 2;
    public double MinY => Math.Min(Y, Y + Height);
    public double MaxY => Math.Max(Y, Y + Height);
    public double MidY => Y + Height / 2;
    /// <summary><c>CGRect.width</c> / <c>.height</c> (standardized, never negative).</summary>
    public double StandardWidth => Math.Abs(Width);
    public double StandardHeight => Math.Abs(Height);

    public bool Equals(Rect o) => MinX == o.MinX && MinY == o.MinY && StandardWidth == o.StandardWidth && StandardHeight == o.StandardHeight;

    public override int GetHashCode() => HashCode.Combine(MinX, MinY, StandardWidth, StandardHeight);
}

/// <summary>Where a tooltip goes: centered 6 pt below the control, above it when there's no room below, always inside the
/// visible screen area (4 pt margin). Screen coordinates, y up (Plan 2 converts from Windows' y-down coordinates).</summary>
public static class TooltipPlacement
{
    public static Rect Frame(Size size, Rect below, Rect visible)
    {
        var rect = below;
        var x = rect.MidX - size.Width / 2;
        var y = rect.MinY - 6 - size.Height;
        if (y < visible.MinY + 4) y = rect.MaxY + 6;
        x = Min(Max(x, visible.MinX + 4), visible.MaxX - size.Width - 4);
        y = Min(Max(y, visible.MinY + 4), visible.MaxY - size.Height - 4);
        return new Rect(x, y, size.Width, size.Height);
    }

    // Swift's min/max (not Math.Min/Max: they differ for NaN).
    static double Max(double x, double y) => y >= x ? y : x;
    static double Min(double x, double y) => y < x ? y : x;
}
