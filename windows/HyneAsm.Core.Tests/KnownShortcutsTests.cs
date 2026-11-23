using Xunit.Abstractions;

namespace HyneAsm.Core.Tests;

public class KnownShortcutsTests
{
    readonly ITestOutputHelper output;
    public KnownShortcutsTests(ITestOutputHelper output) => this.output = output;

    // Stored form of a Windows combo: Ctrl -> Cmd, Win -> Ctrl (see KeyTranslation).
    static KeyCombo Stored(ushort vk, WinModifiers mods) => KeyTranslation.FromWindows(vk, mods)!;

    [Fact]
    public void Conflicts_finds_live_windows_shortcut()
    {
        var hits = KnownShortcuts.Conflicts(Stored(0x54, WinModifiers.Ctrl)); // Ctrl+T
        Assert.Contains(hits, k => k.App == KnownShortcut.AppKind.Live && k.Pressed.Char == 't' && k.Modifiers == WinModifiers.Ctrl);
        Assert.DoesNotContain(hits, k => k.App == KnownShortcut.AppKind.Windows);
    }

    [Fact]
    public void Conflicts_finds_input_switch()
    {
        var ctrlSpace = KnownShortcuts.Conflicts(Stored(0x20, WinModifiers.Ctrl));
        var winSpace = KnownShortcuts.Conflicts(Stored(0x20, WinModifiers.Win));
        Assert.Contains(ctrlSpace, k => k.App == KnownShortcut.AppKind.Windows && k.Pressed.Code == 0x20);
        Assert.Contains(winSpace, k => k.App == KnownShortcut.AppKind.Windows && k.Pressed.Code == 0x20);
    }

    [Fact]
    public void Default_shortcuts_conflict_report()
    {
        var d = ShortcutSettings.Default;
        var combos = new List<(string Name, KeyCombo Combo)> { ("Close focused plugin window", d.CloseFocused!) };
        combos.AddRange(d.CloseAll.Select(c => ("Close all plugin windows", c)));
        combos.AddRange(d.QuickSearch.Select(c => ("Quick search", c)));

        foreach (var (name, combo) in combos)
        {
            var win = KeyTranslation.ToWindows(combo);
            Assert.NotNull(win);
            var hits = KnownShortcuts.Conflicts(combo);
            output.WriteLine($"{name}: vk 0x{win!.Value.vk:X2} + {win.Value.mods} -> " +
                (hits.Count == 0 ? "no conflict" : string.Join("; ", hits.Select(h => $"{h.App}: {h.Title}"))));
            if (name == "Quick search") Assert.NotEmpty(hits); // default Mac Ctrl+Space becomes Win+Space
        }
    }

    [Fact]
    public void Hyne_lists_own_shortcuts_as_windows_keys()
    {
        var config = LauncherConfig.MakeDefault();
        var own = KnownShortcuts.Hyne(config);
        Assert.Contains(own, k => k.Pressed.Code == 0x20 && k.Modifiers == WinModifiers.Win && k.Pressed.Code == 0x20);
        Assert.All(own, k => Assert.Equal(KnownShortcut.AppKind.Hyne, k.App));
    }
}
