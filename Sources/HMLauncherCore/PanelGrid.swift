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

/// How big the panel's entries are: dragged with the panel's resize grip, kept in the config.
public struct PanelSize: Codable, Equatable, Sendable {
    public static let widthRange: ClosedRange<Double> = 240...560
    public static let heightRange: ClosedRange<Double> = 34...64
    public static let `default` = PanelSize(columnWidth: 316, itemHeight: 42)

    public var columnWidth: Double
    public var itemHeight: Double

    /// Values outside the ranges are pulled back in.
    public init(columnWidth: Double, itemHeight: Double) {
        self.columnWidth = min(max(columnWidth, Self.widthRange.lowerBound), Self.widthRange.upperBound)
        self.itemHeight = min(max(itemHeight, Self.heightRange.lowerBound), Self.heightRange.upperBound)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(columnWidth: try c.decode(Double.self, forKey: .columnWidth),
                  itemHeight: try c.decode(Double.self, forKey: .itemHeight))
    }
}

public extension PanelGrid {
    /// The slot under a point of the grid (dragging to reorder), clamped to the existing entries.
    static func index(atX x: Double, y: Double, columns: Int, columnStride: Double, rowStride: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let columns = max(columns, 1)
        let blockHeight = rowStride * Double(rowsPerColumn)
        let block = max(Int(y / blockHeight), 0)
        let row = min(max(Int((y - Double(block) * blockHeight) / rowStride), 0), rowsPerColumn - 1)
        let column = min(max(Int(x / columnStride), 0), columns - 1)
        let index = (block * columns + column) * rowsPerColumn + row
        return min(max(index, 0), count - 1)
    }

    /// Indices in display order while entry `from` is dragged to slot `to`.
    static func order(count: Int, moving from: Int, to: Int) -> [Int] {
        var order = Array(0..<count)
        guard order.indices.contains(from), order.indices.contains(to) else { return order }
        order.insert(order.remove(at: from), at: to)
        return order
    }
}

/// Pads: each column of 9 is drawn as a 3×3 block of pads, row by row, so entries 1–9 sit like the keys 1–9.
/// Blocks keep the column order of `blocks`: side by side up to the column setting, then the next block row below.
public extension PanelGrid {
    static let padsPerRow = 3

    /// Pad rows one block of `count` entries needs (1–3).
    static func padRows(inBlock count: Int) -> Int {
        (min(max(count, 0), rowsPerColumn) + padsPerRow - 1) / padsPerRow
    }

    /// Visual pad rows of `count` entries: full block rows take 3, the last block row as many as its fullest block.
    static func padRows(_ count: Int, columns: Int = columns) -> Int {
        let blockSize = max(columns, 1) * rowsPerColumn
        let full = count / blockSize
        return full * (rowsPerColumn / padsPerRow) + padRows(inBlock: count % blockSize)
    }

    /// Block rows of `count` entries (a block row is up to `columns` blocks side by side).
    static func blockRows(_ count: Int, columns: Int = columns) -> Int {
        let blockSize = max(columns, 1) * rowsPerColumn
        return (count + blockSize - 1) / blockSize
    }

    /// The slot under a point of a pad grid (dragging to reorder), clamped to the existing entries.
    /// Strides include the spacing after a pad / block.
    static func padIndex(atX x: Double, y: Double, columns: Int, blockStride: Double, padStride: Double,
                         blockRowStride: Double, padRowStride: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let columns = max(columns, 1)
        let blockRow = max(Int(y / blockRowStride), 0)
        let blockColumn = min(max(Int(x / blockStride), 0), columns - 1)
        let inY = y - Double(blockRow) * blockRowStride
        let inX = x - Double(blockColumn) * blockStride
        let row = min(max(Int(inY / padRowStride), 0), rowsPerColumn / padsPerRow - 1)
        let col = min(max(Int(inX / padStride), 0), padsPerRow - 1)
        let index = (blockRow * columns + blockColumn) * rowsPerColumn + row * padsPerRow + col
        return min(max(index, 0), count - 1)
    }

    /// Block column (0-based, left to right) and position inside the block of entry `index`.
    static func padPosition(of index: Int, columns: Int) -> (blockColumn: Int, row: Int, column: Int) {
        let inBlockRow = index % (max(columns, 1) * rowsPerColumn)
        let inBlock = inBlockRow % rowsPerColumn
        return (inBlockRow / rowsPerColumn, inBlock / padsPerRow, inBlock % padsPerRow)
    }
}

/// How many pads one page of the panel shows: columns × rows (each 2–8, default 3 × 3).
public struct PanelGridSize: Codable, Equatable, Sendable {
    public static let range = 2...8
    public static let `default` = PanelGridSize(columns: 3, rows: 3)

    public var columns: Int { didSet { columns = Self.clamp(columns) } }
    public var rows: Int { didSet { rows = Self.clamp(rows) } }
    public var pageSize: Int { columns * rows }

    public init(columns: Int, rows: Int) {
        self.columns = Self.clamp(columns)
        self.rows = Self.clamp(rows)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(columns: try c.decode(Int.self, forKey: .columns), rows: try c.decode(Int.self, forKey: .rows))
    }

    private static func clamp(_ v: Int) -> Int { min(max(v, range.lowerBound), range.upperBound) }
}

/// Where the panel lists the categories: a tab bar on top, or a column on the left.
public enum CategoryPlacement: String, Codable, CaseIterable, Sendable {
    case top, left
}
