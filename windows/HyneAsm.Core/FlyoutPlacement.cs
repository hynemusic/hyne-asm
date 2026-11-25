namespace HyneAsm.Core;

/// <summary>Where a folder's side list opens, horizontally. It sits right beside the folder pad, on the side facing the
/// panel's nearer edge: a folder in the left column opens to the left, one in the right column to the right.
/// So the list never covers the neighbouring pads (often other folders) while moving between them.
/// A centred pad (list layout, one column) opens to the right. No room on that side: the other side.
/// Same as Sources/HMLauncherCore/FlyoutPlacement.swift.</summary>
public static class FlyoutPlacement
{
    public static double X(double padMinX, double padMaxX, double panelMinX, double panelMaxX,
                           double width, double screenMinX, double screenMaxX, double gap = 2)
    {
        var left = padMinX - gap - width;
        var right = padMaxX + gap;
        var fitsLeft = left >= screenMinX;
        var fitsRight = right + width <= screenMaxX;
        var preferLeft = (padMinX + padMaxX) / 2 < (panelMinX + panelMaxX) / 2 - 1;
        if (preferLeft) return fitsLeft || !fitsRight ? Math.Max(left, screenMinX) : right;
        return fitsRight || !fitsLeft ? Math.Min(right, screenMaxX - width) : left;
    }
}
