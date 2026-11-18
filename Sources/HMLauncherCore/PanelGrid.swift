/// The panel shows its rows in columns of 9: items fill the left column first, then the next one;
/// beyond `columns × 9` the same pattern continues below. How many columns sit side by side is a setting
/// (`LauncherConfig.panelColumns`, 1–9, default 2).
public enum PanelGrid {
    public static let columns = 2
    public static let maxColumns = 9
    public static let rowsPerColumn = 9

    /// Blocks → columns → row indices, for the given index range.
    public static func blocks(_ indices: Range<Int>, columns: Int = columns) -> [[[Int]]] {
        let all = Array(indices)
        let columns = max(columns, 1)
        let blockSize = columns * rowsPerColumn
        return stride(from: 0, to: max(all.count, 1), by: blockSize).map { start in
            let block = Array(all[start..<min(start + blockSize, all.count)])
            return (0..<columns).map { c in
                let from = c * rowsPerColumn
                return from < block.count ? Array(block[from..<min(from + rowsPerColumn, block.count)]) : []
            }
        }
    }

    /// Columns the panel needs: as many as the fullest section fills, at most `max`.
    public static func columnsNeeded(local: Int, global: Int, max limit: Int = columns) -> Int {
        let needed = (Swift.max(local, global) + rowsPerColumn - 1) / rowsPerColumn
        return Swift.min(Swift.max(needed, 1), Swift.max(limit, 1))
    }

    /// Visual row count of `count` items laid out this way.
    public static func rows(_ count: Int, columns: Int = columns) -> Int {
        let blockSize = max(columns, 1) * rowsPerColumn
        let full = count / blockSize
        return full * rowsPerColumn + min(count % blockSize, rowsPerColumn)
    }
}
