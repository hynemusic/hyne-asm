import Foundation

/// Where a folder's side list opens, horizontally. It sits right beside the folder pad, on the side facing the
/// panel's nearer edge: a folder in the left column opens to the left, one in the right column to the right.
/// So the list never covers the neighbouring pads (often other folders) while moving between them.
/// A centred pad (list layout, one column) opens to the right. No room on that side: the other side.
public enum FlyoutPlacement {
    public static func x(padMinX: Double, padMaxX: Double, panelMinX: Double, panelMaxX: Double,
                         width: Double, screenMinX: Double, screenMaxX: Double, gap: Double = 2) -> Double {
        let left = padMinX - gap - width
        let right = padMaxX + gap
        let fitsLeft = left >= screenMinX
        let fitsRight = right + width <= screenMaxX
        let preferLeft = (padMinX + padMaxX) / 2 < (panelMinX + panelMaxX) / 2 - 1
        if preferLeft { return fitsLeft || !fitsRight ? max(left, screenMinX) : right }
        return fitsRight || !fitsLeft ? min(right, screenMaxX - width) : left
    }
}
