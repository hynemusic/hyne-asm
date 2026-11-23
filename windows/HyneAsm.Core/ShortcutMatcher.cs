namespace HyneAsm.Core;

public enum CloseShortcutAction { CloseFocused, CloseAll, QuickSearch, NextProfile }

/// <summary>Exact match on key code and modifiers (Cmd+Alt+W is not Cmd+W).</summary>
public sealed partial class ShortcutMatcher
{
    public ShortcutSettings Settings { get; }

    public ShortcutMatcher(ShortcutSettings settings) { Settings = settings; }

    public CloseShortcutAction? Match(ushort keyCode, ModifierSet modifiers)
    {
        var combo = new KeyCombo(keyCode, modifiers);
        if (Settings.CloseFocused == combo) return CloseShortcutAction.CloseFocused;
        if (Settings.CloseAll.Contains(combo)) return CloseShortcutAction.CloseAll;
        if (Settings.QuickSearch.Contains(combo)) return CloseShortcutAction.QuickSearch;
        if (Settings.NextProfile.Contains(combo)) return CloseShortcutAction.NextProfile;
        return null;
    }
}
