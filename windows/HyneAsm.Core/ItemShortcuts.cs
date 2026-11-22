using System.Text.Json.Serialization;
using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>A key combination that inserts one plugin, rack or preset straight away (while Live is in front).</summary>
public sealed record ItemShortcut : IJsonOnDeserialized
{
    [JsonRequired] public Guid Id { get; set; } = Guid.NewGuid();
    [JsonRequired] public KeyCombo Combo { get; set; } = new();
    [JsonRequired] public string Uri { get; set; } = "";
    [JsonRequired] public string Name { get; set; } = "";
    [JsonRequired] public ItemSource Source { get; set; }
    [JsonRequired] public List<string> Path { get; set; } = new();

    public ItemShortcut() { }

    public ItemShortcut(KeyCombo combo, PluginItem item)
    {
        Combo = combo;
        Uri = item.Uri; Name = item.Name; Source = item.Source; Path = item.Path.ToList();
    }

    void IJsonOnDeserialized.OnDeserialized()
    {
        SwiftJson.RejectNull(nameof(ItemShortcut), Combo, Uri, Name, Path);
        SwiftJson.RejectNullElements(nameof(ItemShortcut), Path);
    }

    [JsonIgnore] public PluginItem Item => new(Uri, Name, Source, Path);

    public bool Equals(ItemShortcut? o) => o is not null && Id == o.Id && Combo == o.Combo && Uri == o.Uri &&
        Name == o.Name && Source == o.Source && ValueEquality.Lists(Path, o.Path);

    public override int GetHashCode() => HashCode.Combine(Id, Combo, Uri, Name, Source, ValueEquality.Hash(Path));
}

public sealed partial record LauncherConfig
{
    /// <summary>Assigns (or moves) a shortcut to an item; one shortcut per item. Null removes it.</summary>
    public void SetItemShortcut(KeyCombo? combo, PluginItem item)
    {
        ItemShortcuts.RemoveAll(s => s.Uri == item.Uri || (s.Name == item.Name && s.Source == item.Source));
        if (combo != null) ItemShortcuts.Add(new ItemShortcut(combo, item));
    }

    /// <summary>Swift <c>itemShortcut(for:)</c> (renamed: a member named like the type would hide it here).</summary>
    public ItemShortcut? ItemShortcutFor(PluginItem item) =>
        ItemShortcuts.FirstOrDefault(s => s.Uri == item.Uri) ??
        ItemShortcuts.FirstOrDefault(s => s.Name == item.Name && s.Source == item.Source);

    /// <summary>Who else uses this combo ("Close all plugin windows", "Serum 2"); null when it is free.</summary>
    public string? ShortcutOwner(KeyCombo combo, Guid? ignoring = null)
    {
        if (Shortcuts.CloseFocused == combo) return Loc.T("Fokussiertes Plugin-Fenster schließen", "Close focused plugin window");
        if (Shortcuts.CloseAll.Contains(combo)) return Loc.T("Alle Plugin-Fenster schließen", "Close all plugin windows");
        if (Shortcuts.QuickSearch.Contains(combo)) return Loc.T("Schnellsuche öffnen", "Open quick search");
        if (Shortcuts.NextProfile.Contains(combo)) return Loc.T("Nächstes Profil", "Next profile");
        return ItemShortcuts.FirstOrDefault(s => s.Combo == combo && s.Id != ignoring)?.Name;
    }
}

public sealed partial class ShortcutMatcher
{
    /// <summary>Item shortcuts come after the built-in ones, so those always win. (Swift extension in ItemShortcuts.swift;
    /// named like the config accessor <c>ItemShortcutFor</c>.)</summary>
    public static ItemShortcut? ItemShortcutFor(ushort keyCode, ModifierSet modifiers, IEnumerable<ItemShortcut> shortcuts)
    {
        var combo = new KeyCombo(keyCode, modifiers);
        return shortcuts.FirstOrDefault(s => s.Combo == combo);
    }
}
