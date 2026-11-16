/// The panel shows its rows in two columns of 10: items fill the left column first, then the right one;
/// beyond 20 the same pattern continues below (blocks of 2 × 10).
public enum PanelGrid {
    public static let columns = 2
    public static let rowsPerColumn = 10

    /// Blocks → columns → row indices, for the given index range.
    public static func blocks(_ indices: Range<Int>) -> [[[Int]]] {
        let all = Array(indices)
        let blockSize = columns * rowsPerColumn
        return stride(from: 0, to: max(all.count, 1), by: blockSize).map { start in
            let block = Array(all[start..<min(start + blockSize, all.count)])
            return (0..<columns).map { c in
                let from = c * rowsPerColumn
                return from < block.count ? Array(block[from..<min(from + rowsPerColumn, block.count)]) : []
            }
        }
    }

    /// Visual row count of `count` items laid out this way.
    public static func rows(_ count: Int) -> Int {
        let blockSize = columns * rowsPerColumn
        let full = count / blockSize
        return full * rowsPerColumn + min(count % blockSize, rowsPerColumn)
    }
}
