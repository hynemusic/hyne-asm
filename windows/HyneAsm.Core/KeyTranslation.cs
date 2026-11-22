namespace HyneAsm.Core;

/// <summary>Windows modifier keys (Ctrl, Alt, Shift, Win).</summary>
[Flags]
public enum WinModifiers : byte { None = 0, Ctrl = 1, Alt = 2, Shift = 4, Win = 8 }

/// <summary>Shortcuts are stored in macOS form (<see cref="KeyCombo"/>); this maps them to and from Windows virtual keys.
/// Keys map by physical position on a US-ANSI keyboard (<c>kVK_ANSI_*</c> ↔ <c>VK_*</c>), modifiers as
/// Cmd↔Ctrl, Alt↔Alt, Shift↔Shift, Ctrl↔Win. Keys with no counterpart give null.</summary>
public static class KeyTranslation
{
    /// <summary>The one table both directions read: (macOS key code, Windows virtual key).</summary>
    static readonly (ushort Mac, ushort Vk)[] Table =
    {
        // Letters
        (0, 0x41), (11, 0x42), (8, 0x43), (2, 0x44), (14, 0x45), (3, 0x46), (5, 0x47), (4, 0x48), (34, 0x49), (38, 0x4A),
        (40, 0x4B), (37, 0x4C), (46, 0x4D), (45, 0x4E), (31, 0x4F), (35, 0x50), (12, 0x51), (15, 0x52), (1, 0x53), (17, 0x54),
        (32, 0x55), (9, 0x56), (13, 0x57), (7, 0x58), (16, 0x59), (6, 0x5A),
        // Number row 0-9
        (29, 0x30), (18, 0x31), (19, 0x32), (20, 0x33), (21, 0x34), (23, 0x35), (22, 0x36), (26, 0x37), (28, 0x38), (25, 0x39),
        // Punctuation: = - ] [ ' ; \ , / . `
        (24, 0xBB), (27, 0xBD), (30, 0xDD), (33, 0xDB), (39, 0xDE), (41, 0xBA), (42, 0xDC), (43, 0xBC), (44, 0xBF), (47, 0xBE), (50, 0xC0),
        // Return, Tab, Space, Backspace (kVK_Delete), Esc, Forward Delete
        (36, 0x0D), (48, 0x09), (49, 0x20), (51, 0x08), (53, 0x1B), (117, 0x2E),
        // Help (the Insert position), Home, End, Page Up, Page Down
        (114, 0x2D), (115, 0x24), (119, 0x23), (116, 0x21), (121, 0x22),
        // Arrows: left, up, right, down
        (123, 0x25), (126, 0x26), (124, 0x27), (125, 0x28),
        // F1-F12
        (122, 0x70), (120, 0x71), (99, 0x72), (118, 0x73), (96, 0x74), (97, 0x75), (98, 0x76), (100, 0x77), (101, 0x78),
        (109, 0x79), (103, 0x7A), (111, 0x7B),
        // F13-F20
        (105, 0x7C), (107, 0x7D), (113, 0x7E), (106, 0x7F), (64, 0x80), (79, 0x81), (80, 0x82), (90, 0x83),
        // Keypad 0-9, * + - . /
        (82, 0x60), (83, 0x61), (84, 0x62), (85, 0x63), (86, 0x64), (87, 0x65), (88, 0x66), (89, 0x67), (91, 0x68), (92, 0x69),
        (67, 0x6A), (69, 0x6B), (78, 0x6D), (65, 0x6E), (75, 0x6F),
    };

    static readonly Dictionary<ushort, ushort> MacToVk = Table.ToDictionary(r => r.Mac, r => r.Vk);
    static readonly Dictionary<ushort, ushort> VkToMac = Table.ToDictionary(r => r.Vk, r => r.Mac);

    /// <summary>Every (macOS key code, Windows virtual key) pair the table knows.</summary>
    public static IReadOnlyList<(ushort Mac, ushort Vk)> Rows => Table;

    const ModifierSet AllMac = ModifierSet.Cmd | ModifierSet.Alt | ModifierSet.Shift | ModifierSet.Ctrl;
    const WinModifiers AllWin = WinModifiers.Ctrl | WinModifiers.Alt | WinModifiers.Shift | WinModifiers.Win;

    public static (ushort vk, WinModifiers mods)? ToWindows(KeyCombo combo)
    {
        if (!MacToVk.TryGetValue(combo.KeyCode, out var vk) || (combo.Modifiers & ~AllMac) != 0) return null;
        var m = combo.Modifiers;
        var mods = (m.HasFlag(ModifierSet.Cmd) ? WinModifiers.Ctrl : 0) | (m.HasFlag(ModifierSet.Alt) ? WinModifiers.Alt : 0) |
                   (m.HasFlag(ModifierSet.Shift) ? WinModifiers.Shift : 0) | (m.HasFlag(ModifierSet.Ctrl) ? WinModifiers.Win : 0);
        return (vk, mods);
    }

    public static KeyCombo? FromWindows(ushort vk, WinModifiers mods)
    {
        if (!VkToMac.TryGetValue(vk, out var mac) || (mods & ~AllWin) != 0) return null;
        var m = (mods.HasFlag(WinModifiers.Ctrl) ? ModifierSet.Cmd : 0) | (mods.HasFlag(WinModifiers.Alt) ? ModifierSet.Alt : 0) |
                (mods.HasFlag(WinModifiers.Shift) ? ModifierSet.Shift : 0) | (mods.HasFlag(WinModifiers.Win) ? ModifierSet.Ctrl : 0);
        return new KeyCombo(mac, m);
    }
}
