/// Digit keys by position, so ⇧1 still means "row 1" (the shifted character is "!" or similar).
public enum DigitKeys {
    private static let map: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 0,          // number row
        82: 0, 83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9,          // keypad
    ]

    public static func digit(forKeyCode code: UInt16) -> Int? { map[code] }
}
