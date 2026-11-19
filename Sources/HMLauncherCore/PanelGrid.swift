/// Helpers for laying out the panel's entries (see `PanelPage` for where each entry sits on a page).
public enum PanelGrid {
    /// Indices in display order while entry `from` is dragged to slot `to`.
    public static func order(count: Int, moving from: Int, to: Int) -> [Int] {
        var order = Array(0..<count)
        guard order.indices.contains(from), order.indices.contains(to) else { return order }
        order.insert(order.remove(at: from), at: to)
        return order
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

/// How the panel shows a page: square pads in a grid, or rows of a list.
public enum PanelStyle: String, Codable, CaseIterable, Sendable {
    case grid, list
}

/// Size of a list page: columns side by side (1–4), each up to 9 rows (keys 1–9 run down the first column).
public struct PanelListSize: Codable, Equatable, Sendable {
    public static let columnRange = 1...4
    public static let rowRange = 2...9
    public static let `default` = PanelListSize(columns: 2, rows: 9)

    public var columns: Int { didSet { columns = Self.clamp(columns, Self.columnRange) } }
    public var rows: Int { didSet { rows = Self.clamp(rows, Self.rowRange) } }
    public var pageSize: Int { columns * rows }

    public init(columns: Int, rows: Int) {
        self.columns = Self.clamp(columns, Self.columnRange)
        self.rows = Self.clamp(rows, Self.rowRange)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(columns: try c.decode(Int.self, forKey: .columns), rows: try c.decode(Int.self, forKey: .rows))
    }

    private static func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(max(v, r.lowerBound), r.upperBound) }
}

/// One page of the panel: how many entries it holds and where each sits. A grid fills row by row
/// (like the keys 1–9 on a keypad); a list fills its left column first, then the next.
public struct PanelPage: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let columnMajor: Bool
    public var size: Int { columns * rows }

    public init(columns: Int, rows: Int, columnMajor: Bool) {
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
        self.columnMajor = columnMajor
    }

    public init(style: PanelStyle, grid: PanelGridSize, list: PanelListSize) {
        switch style {
        case .grid: self.init(columns: grid.columns, rows: grid.rows, columnMajor: false)
        case .list: self.init(columns: list.columns, rows: list.rows, columnMajor: true)
        }
    }

    /// Slot (0-based, within the page) at a row and column.
    public func slot(row: Int, column: Int) -> Int {
        columnMajor ? column * rows + row : row * columns + column
    }

    /// Row and column of a slot within the page.
    public func position(of slot: Int) -> (row: Int, column: Int) {
        let s = slot % size
        return columnMajor ? (s % rows, s / rows) : (s / columns, s % columns)
    }
}
