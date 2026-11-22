namespace HyneAsm.Core;

/// <summary>The user's own preset files (racks, device presets, plugin presets) as listed by the bridge.
/// (<c>PresetImport</c>, the rest of Presets.swift, is ported with the imports.)</summary>
public static class PresetFormat
{
    /// <summary>Extensions Live can load from the browser, without the dot.</summary>
    public static readonly IReadOnlySet<string> Extensions =
        new HashSet<string>(StringComparer.Ordinal) { "adg", "adv", "vstpreset", "aupreset", "fxp", "fxb", "amxd" };

    public const string GroupPrefix = "Presets · ";

    /// <summary>Short badge shown next to the preset in the settings browser.</summary>
    public static string Label(PluginItem item) => item.Format == null ? "Preset" : Text.Normalize(item.Format) switch
    {
        "adg" => "Rack",
        "adv" => "Preset",
        "vstpreset" => "VST3",
        "aupreset" => "AU",
        "fxp" or "fxb" => "VST2",
        "amxd" => "M4L",
        _ => "Preset",
    };

    /// <summary>Settings browser group: "Presets · &lt;folder&gt;". User Library presets drop Live's own "Presets" level,
    /// so "Presets/Audio Effects/…" becomes "Presets · Audio Effects". Places folders use their own name.</summary>
    public static string GroupTitle(PluginItem item)
    {
        IEnumerable<string> path = item.Path;
        if (item.Source == ItemSource.UserLibrary && item.Path.Count > 0 && Text.Equal(item.Path[0], "Presets")) path = path.Skip(1);
        var first = path.FirstOrDefault();
        return first != null ? GroupPrefix + first : GroupPrefix + "User Library";
    }

    /// <summary>Icon when the name gives no hint: drum racks get drums, instrument racks a synth, other racks the rack icon.</summary>
    internal static string FallbackIcon(PluginItem item)
    {
        var path = Text.Normalize(string.Join("/", item.Path));
        if (Text.Contains(path, "drum")) return "drums";
        if (Text.Contains(path, "instrument")) return "synth";
        if (Text.Contains(path, "midi")) return "midi";
        return item.Format != null && Text.Normalize(item.Format) == "adg" ? "rack" : IconCatalog.DefaultID;
    }
}
