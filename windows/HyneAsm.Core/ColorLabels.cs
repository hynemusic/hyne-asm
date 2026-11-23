namespace HyneAsm.Core;

public sealed record ColorDef(string Id, string De, string En, double Red, double Green, double Blue)
{
    public string Label => Loc.T(De, En);
}

public static class ColorPalette
{
    /// <summary>Stored on an entry to mean "no color, even if a rule would give one".</summary>
    public const string NoneID = "none";

    public static readonly IReadOnlyList<ColorDef> All = new ColorDef[]
    {
        new("red", "Rot", "Red", 0.93, 0.33, 0.31),
        new("orange", "Orange", "Orange", 0.98, 0.58, 0.20),
        new("yellow", "Gelb", "Yellow", 0.97, 0.83, 0.25),
        new("green", "Grün", "Green", 0.40, 0.80, 0.38),
        new("teal", "Türkis", "Teal", 0.25, 0.78, 0.75),
        new("blue", "Blau", "Blue", 0.33, 0.58, 0.96),
        new("purple", "Lila", "Purple", 0.67, 0.47, 0.93),
        new("pink", "Pink", "Pink", 0.95, 0.45, 0.70),
        new("gray", "Grau", "Gray", 0.62, 0.62, 0.62),
    };

    public static ColorDef? Color(string? id) => All.FirstOrDefault(c => Text.Equal(c.Id, id));
}

/// <summary>Colors that apply to a whole group of plugins — also to ones added later and to search hits.</summary>
public abstract record ColorRule
{
    public sealed record LiveDevices : ColorRule;
    public sealed record Vendor(string Name) : ColorRule;

    internal string Key => this switch
    {
        LiveDevices => "live",
        Vendor v => "vendor:" + v.Name,
        _ => throw new InvalidOperationException(),
    };

    /// <summary>Rules that can apply to a plugin: Live's own devices, or the manufacturer folder of a VST3/AU.</summary>
    public static IReadOnlyList<ColorRule> ForItem(PluginItem item) => item.Source switch
    {
        ItemSource.Instruments or ItemSource.AudioEffects or ItemSource.MidiEffects => new ColorRule[] { new LiveDevices() },
        ItemSource.Plugins when PluginGrouping.FormatLabel(item) != "VST2" && item.Path.Count > 1 => new ColorRule[] { new Vendor(item.Path[1]) },
        _ => Array.Empty<ColorRule>(),
    };
}

public sealed partial record LauncherConfig
{
    /// <summary>The entry's own color, else a matching rule. <see cref="ColorPalette.NoneID"/> on the entry means no color.</summary>
    public string? ColorID(Entry entry)
    {
        if (entry.ColorID != null) return entry.ColorID == ColorPalette.NoneID ? null : entry.ColorID;
        if (entry.IsFolder) return null;
        return ColorID(new PluginItem(entry.Uri, entry.Name, entry.Source, entry.Path));
    }

    public string? ColorID(PluginItem item)
    {
        foreach (var rule in ColorRule.ForItem(item))
            if (LookupColorRule(rule.Key) is { } id) return id;
        return null;
    }

    public string? GetColorRule(ColorRule rule) => LookupColorRule(rule.Key);

    /// <summary>Swift dictionaries treat canonically equal keys as one: an existing key keeps its spelling.</summary>
    public void SetColorRule(string? colorID, ColorRule rule)
    {
        var existing = ColorRules.Keys.FirstOrDefault(k => Text.Equal(k, rule.Key));
        if (colorID == null) { if (existing != null) ColorRules.Remove(existing); }
        else ColorRules[existing ?? rule.Key] = colorID;
    }

    /// <summary>Like icons, a color belongs to the plugin: every entry of it (all categories, all formats) changes.
    /// null falls back to the rules; a folder's color only changes that folder.</summary>
    public void SetColor(string? colorID, Guid entry, Guid categoryID)
    {
        if (FindEntry(entry, categoryID) is not { } target) return;
        foreach (var category in Categories)
            foreach (var e in category.Entries)
            {
                if (e.Id == target.Id || (!target.IsFolder && !e.IsFolder && SamePlugin(e, target))) e.ColorID = colorID;
                if (target.IsFolder) continue;
                foreach (var child in e.Children ?? new())
                    if (SamePlugin(child, target)) child.ColorID = colorID;
            }
    }

    /// <summary>Swift dictionaries treat canonically equal keys as one (a vendor folder may come decomposed).</summary>
    string? LookupColorRule(string key)
    {
        if (ColorRules.TryGetValue(key, out var id)) return id;
        foreach (var (k, v) in ColorRules) if (Text.Equal(k, key)) return v;
        return null;
    }
}
