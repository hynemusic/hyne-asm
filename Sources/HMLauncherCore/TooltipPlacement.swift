import CoreGraphics

/// Where a tooltip goes: centered 6 pt below the control, above it when there's no room below, always inside the
/// visible screen area (4 pt margin). Screen coordinates, y up.
public enum TooltipPlacement {
    public static func frame(size: CGSize, below rect: CGRect, visible: CGRect) -> CGRect {
        var x = rect.midX - size.width / 2
        var y = rect.minY - 6 - size.height
        if y < visible.minY + 4 { y = rect.maxY + 6 }
        x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)
        y = min(max(y, visible.minY + 4), visible.maxY - size.height - 4)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
