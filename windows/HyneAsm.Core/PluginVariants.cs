using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>One plugin with all its installed formats, best first (VST3 → AU → VST2).</summary>
public sealed record PluginVariantGroup(IReadOnlyList<PluginItem> Variants)
{
    public PluginItem Preferred => Variants[0];

    /// <summary>Formats it is installed in, best first, each once.</summary>
    public List<string> Formats => Unique(Variants.Select(PluginGrouping.FormatLabel));

    /// <summary>Channel versions ("Stereo", "Mono", "Mono/Stereo", "m-&gt;s" …), preferred first; empty when there is
    /// only one kind.</summary>
    public List<string> Channels
    {
        get
        {
            var labels = Unique(Variants.Select(v => PluginVariants.Channel(v.Name).Label ?? ""));
            return labels.Count > 1 ? labels.Where(l => l.Length > 0).ToList() : new();
        }
    }

    static List<string> Unique(IEnumerable<string> values)
    {
        var seen = new HashSet<string>(Text.Canonical);
        return values.Where(seen.Add).ToList();
    }

    public bool Equals(PluginVariantGroup? o) => o is not null && Variants.SequenceEqual(o.Variants);

    public override int GetHashCode() => Variants.Count == 0 ? 0 : Variants[0].GetHashCode();
}

/// <summary>Merges the VST3/AU/VST2 copies of a plugin. Live names them differently per format, so the key normalises:
/// case and spaces, Waves' "(s)"/"(m)" = "Stereo"/"Mono", and VST2's "&lt;Vendor&gt; " prefix ("FabFilter Pro-L 2").
/// Live's own devices are never merged with plugins.</summary>
public static class PluginVariants
{
    public sealed class Keys
    {
        /// <summary>Lowercased vendor names with the space that must follow them, longest first.</summary>
        readonly List<(string Prefix, int Count)> vendors;

        public Keys(IReadOnlyList<PluginItem> items)
        {
            vendors = PluginGrouping.KnownVendors(items).Select(v => Text.Lower(v) + " ").Select(p => (p, Text.Count(p))).ToList();
        }

        public string Key(PluginItem item)
        {
            // Presets with the same name in different folders are different files.
            if (item.Source.IsPreset()) return "preset|" + item.Uri;
            if (item.Source != ItemSource.Plugins) return SwiftJson.RawValue(item.Source) + "|" + LESMatcher.Normalize(item.Name);
            var name = LESMatcher.Normalize(Channel(item.Name).Base);
            if (PluginGrouping.FormatLabel(item) == "VST2")
            {
                foreach (var (prefix, count) in vendors)
                {
                    if (!Text.HasPrefix(name, prefix)) continue;
                    name = Text.DropFirst(name, count);
                    break;
                }
            }
            return "plugins|" + name;
        }
    }

    /// <summary>Groups in first-seen order; within a group one item per format, best format first.</summary>
    public static List<PluginVariantGroup> Collapse(IReadOnlyList<PluginItem> items)
    {
        var keys = new Keys(items);
        var order = new List<string>();
        var byKey = new Dictionary<string, List<PluginItem>>(Text.Canonical);
        foreach (var item in items)
        {
            var k = keys.Key(item);
            if (!byKey.TryGetValue(k, out var list)) { order.Add(k); byKey[k] = list = new(); }
            list.Add(item);
        }
        return order.Select(k =>
        {
            // Stereo before mono, then VST3 → AU → VST2; one item per format and channel version.
            var seen = new HashSet<string>(Text.Canonical);
            var variants = byKey[k].OrderBy(ChannelRank).ThenBy(Rank)
                .Where(v => seen.Add(PluginGrouping.FormatLabel(v) + "|" + (Channel(v.Name).Label ?? "")))
                .ToList();
            return new PluginVariantGroup(variants);
        }).ToList();
    }

    static readonly (string Suffix, string Label)[] Suffixes =
    {
        (" mono/stereo", "Mono/Stereo"), (" stereo", "Stereo"), (" mono", "Mono"), (" (s)", "Stereo"), (" (m)", "Mono"),
        (" (m->s)", "m->s"), (" (s->s)", "Stereo"), (" (m->m)", "Mono"),
    };

    /// <summary>Channel versions are one plugin: "REDD17 Mono" / "REDD17 Stereo", "CLA-76 (m)" / "(s)", "Reel ADT (m-&gt;s)",
    /// "Abbey Road Studio 3 (6-&gt;2)". Returns the name without that suffix and the version's label.
    /// ("Reel ADT Live" keeps "Live": that is a different plugin, not a channel version.)</summary>
    public static (string Base, string? Label) Channel(string name)
    {
        var trimmed = Text.TrimWhitespaces(name);
        var lower = Text.Normalize(trimmed);
        foreach (var (suffix, label) in Suffixes)   // ASCII suffixes: ordinal on the NFC form, then a Character boundary
            if (lower.EndsWith(suffix, StringComparison.Ordinal) && Text.IsBoundary(lower, lower.Length - suffix.Length))
                return (trimmed[..^suffix.Length], label);
        // Surround layouts: "(6->2)", "(5->6)", "(8->2)"
        var open = trimmed.LastIndexOf('(');
        if (open >= 0 && Text.HasSuffix(trimmed, ")"))
        {
            var inside = trimmed[(open + 1)..^1];
            if (inside.Contains("->", StringComparison.Ordinal)
                && Text.Characters(inside).All(ch => Text.IsNumber(ch) || ch is "-" or ">" or "."))
                return (Text.TrimWhitespaces(trimmed[..open]), inside);
        }
        return (trimmed, null);
    }

    /// <summary>"VST3 · Mono" — names one version in menus.</summary>
    public static string Label(PluginItem item) =>
        Channel(item.Name).Label is { } channel ? PluginGrouping.FormatLabel(item) + " · " + channel : PluginGrouping.FormatLabel(item);

    /// <summary>Stereo first (what most tracks need), then mono/stereo and plain names, then m-&gt;s, mono, surround.</summary>
    internal static int ChannelRank(PluginItem item) => Channel(item.Name).Label switch
    {
        "Stereo" => 0,
        "Mono/Stereo" or null => 1,
        "m->s" => 2,
        "Mono" => 3,
        _ => 4,
    };

    internal static int Rank(PluginItem item) => PluginGrouping.FormatLabel(item) switch
    {
        "VST3" => 0,
        "AU" => 1,
        "VST2" => 2,
        _ => 3,
    };
}
