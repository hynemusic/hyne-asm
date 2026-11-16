import Foundation

public enum ClickVerdict: Equatable, Sendable { case passThrough, openPanel }

/// Decides on right-mouse-down: the second press within `interval` opens the panel; the press after that starts over.
public struct DoubleRightClickDetector {
    public let interval: TimeInterval
    private var firstDownAt: TimeInterval?

    public init(interval: TimeInterval) { self.interval = interval }

    public mutating func rightMouseDown(at time: TimeInterval) -> ClickVerdict {
        if let first = firstDownAt, time - first <= interval {
            firstDownAt = nil
            return .openPanel
        }
        firstDownAt = time
        return .passThrough
    }
}
