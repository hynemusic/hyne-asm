namespace HyneAsm.Core;

/// <summary>Color rules that apply to a whole group of plugins — also to ones added later and to search hits.
/// (Only what search needs is here so far: the palette ids, the rules and the lookup; editing comes with the panel.)</summary>
public static class ColorPalette
{
    /// <summary>Stored on an entry to mean "no color, even if a rule would give one".</summary>
    public const string NoneID = "none";

    public static readonly IReadOnlyList<string> AllIDs = new[] { "red", "orange", "yellow", "green", "teal", "blue", "purple", "pink", "gray" };
}

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

    public void SetColorRule(string? colorID, ColorRule rule)
    {
        var existing = ColorRules.Keys.FirstOrDefault(k => Text.Equal(k, rule.Key));
        if (existing != null) ColorRules.Remove(existing);
        if (colorID != null) ColorRules[rule.Key] = colorID;
    }

    /// <summary>Swift dictionaries treat canonically equal keys as one (a vendor folder may come decomposed).</summary>
    string? LookupColorRule(string key)
    {
        if (ColorRules.TryGetValue(key, out var id)) return id;
        foreach (var (k, v) in ColorRules) if (Text.Equal(k, key)) return v;
        return null;
    }
}
