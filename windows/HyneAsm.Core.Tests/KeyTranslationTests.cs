namespace HyneAsm.Core.Tests;

public class KeyTranslationTests
{
    public static IEnumerable<object[]> Rows() => KeyTranslation.Rows.Select(r => new object[] { r.Mac, r.Vk });

    [Theory, MemberData(nameof(Rows))]
    public void Every_table_row_round_trips_with_every_modifier_combination(ushort mac, ushort vk)
    {
        for (byte m = 0; m < 16; m++)
        {
            var combo = new KeyCombo(mac, (ModifierSet)m);
            var win = KeyTranslation.ToWindows(combo);
            Assert.NotNull(win);
            Assert.Equal(vk, win!.Value.vk);
            Assert.Equal(combo, KeyTranslation.FromWindows(win.Value.vk, win.Value.mods));
        }
    }

    [Fact]
    public void Table_has_no_duplicate_keys_on_either_side()
    {
        Assert.Equal(KeyTranslation.Rows.Count, KeyTranslation.Rows.Select(r => r.Mac).Distinct().Count());
        Assert.Equal(KeyTranslation.Rows.Count, KeyTranslation.Rows.Select(r => r.Vk).Distinct().Count());
    }

    [Fact]
    public void Every_default_shortcut_and_panel_key_has_a_windows_counterpart()
    {
        var shortcuts = ShortcutSettings.Default;
        var combos = new[] { shortcuts.CloseFocused! }.Concat(shortcuts.CloseAll).Concat(shortcuts.QuickSearch)
            .Concat(Enum.GetValues<PanelKeyAction>().SelectMany(a => PanelKeyBindings.Default[a]));
        foreach (var combo in combos)
        {
            var win = KeyTranslation.ToWindows(combo);
            // The keypad Return key has no Windows virtual key of its own (it is VK_RETURN with the extended flag).
            if (combo.KeyCode == 76) { Assert.Null(win); continue; }
            Assert.NotNull(win);
            Assert.Equal(combo, KeyTranslation.FromWindows(win!.Value.vk, win.Value.mods));
        }
    }
}
