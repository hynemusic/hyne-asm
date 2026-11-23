namespace HyneAsm.Core;

/// <summary>Digit keys by position (macOS key codes), so Shift+1 still means "row 1" (the shifted character is "!" or similar).</summary>
public static class DigitKeys
{
    static readonly Dictionary<ushort, int> Map = new()
    {
        [18] = 1, [19] = 2, [20] = 3, [21] = 4, [23] = 5, [22] = 6, [26] = 7, [28] = 8, [25] = 9, [29] = 0,   // number row
        [82] = 0, [83] = 1, [84] = 2, [85] = 3, [86] = 4, [87] = 5, [88] = 6, [89] = 7, [91] = 8, [92] = 9,   // keypad
    };

    public static int? Digit(ushort keyCode) => Map.TryGetValue(keyCode, out var d) ? d : null;
}
