namespace HyneAsm.Core;

public sealed record PluginGroup(string Title, IReadOnlyList<PluginItem> Items)
{
    public string Id => Title;

    public bool Equals(PluginGroup? o) => o is not null && Text.Equal(Title, o.Title) && Items.SequenceEqual(o.Items);

    public override int GetHashCode() => Text.Canonical.GetHashCode(Title);
}

/// <summary>Settings browser: Live devices first, then one folder per manufacturer (VST3 → AU → VST2 inside),
/// then VST2 plugins whose manufacturer cannot be inferred.</summary>
public static class PluginGrouping
{
    public static string OtherVST2 => Loc.T("Weitere VST2", "Other VST2");

    static readonly (ItemSource Source, string Title)[] LiveGroups =
    {
        (ItemSource.AudioEffects, "Live · Audio Effects"), (ItemSource.Instruments, "Live · Instruments"),
        (ItemSource.MidiEffects, "Live · MIDI Effects"), (ItemSource.MaxForLive, "Live · Max for Live"),
    };

    static readonly Comparer<string> Localized = Comparer<string>.Create(Text.LocalizedCaseInsensitiveCompare);
    static readonly Comparer<PluginItem> ByName = Comparer<PluginItem>.Create((a, b) => Text.LocalizedCaseInsensitiveCompare(a.Name, b.Name));

    public static List<PluginGroup> Groups(IReadOnlyList<PluginItem> items, string search)
    {
        var vendors = KnownVendors(items);
        var query = new SearchMatcher.Prepared(search);
        var matches = search.Length == 0 ? items.ToList()
            : items.Where(i => SearchMatcher.Score(new SearchMatcher.Prepared(i.Name), query) != null).ToList();
        var result = new List<PluginGroup>();

        // Own presets first, one group per folder they were saved in.
        var byFolder = GroupBy(matches.Where(i => i.Source.IsPreset()), PresetFormat.GroupTitle);
        foreach (var title in byFolder.Keys.OrderBy(t => t, Localized))
            result.Add(new PluginGroup(title, byFolder[title].OrderBy(i => i, ByName).ToList()));

        foreach (var (source, title) in LiveGroups)
        {
            var group = matches.Where(i => i.Source == source).OrderBy(i => i, ByName).ToList();
            if (group.Count > 0) result.Add(new PluginGroup(title, group));
        }

        var other = OtherVST2;
        var byVendor = GroupBy(matches.Where(i => i.Source == ItemSource.Plugins), i => Vendor(i, vendors) ?? other);
        var vendorTitles = byVendor.Keys.Where(t => !Text.Equal(t, other)).OrderBy(t => t, Localized).ToList();
        if (byVendor.ContainsKey(other)) vendorTitles.Add(byVendor.Keys.First(k => Text.Equal(k, other)));
        foreach (var title in vendorTitles)
        {
            var sorted = byVendor[title].OrderBy(FormatRank).ThenBy(i => i, ByName).ToList();
            result.Add(new PluginGroup(title, sorted));
        }
        return result;
    }

    /// <summary>Swift's <c>Dictionary(grouping:by:)</c>: canonically equal keys are one group, items keep their order.
    /// (Key order is Swift's hash order there; every caller sorts the keys.)</summary>
    static Dictionary<string, List<PluginItem>> GroupBy(IEnumerable<PluginItem> items, Func<PluginItem, string> key)
    {
        var groups = new Dictionary<string, List<PluginItem>>(Text.Canonical);
        foreach (var item in items)
        {
            var k = key(item);
            if (!groups.TryGetValue(k, out var list)) groups[k] = list = new();
            list.Add(item);
        }
        return groups;
    }

    public static string FormatLabel(PluginItem item)
    {
        if (item.Source.IsPreset()) return PresetFormat.Label(item);
        if (item.Source != ItemSource.Plugins) return "Live";
        return FormatRank(item) switch
        {
            0 => "VST3",
            1 => "AU",
            2 => "VST2",
            _ => item.Path.FirstOrDefault() ?? "",
        };
    }

    static int FormatRank(PluginItem item)
    {
        var format = item.Path.FirstOrDefault() ?? "";
        if (Text.Equal(format, "VST3")) return 0;
        if (Text.HasPrefix(format, "AU")) return 1;
        if (Text.Equal(format, "VST")) return 2;
        return 3;
    }

    /// <summary>Manufacturer folders that VST3/AU plugins live in, longest first.</summary>
    internal static List<string> KnownVendors(IReadOnlyList<PluginItem> items)
    {
        var names = new HashSet<string>(Text.Canonical);
        var ordered = new List<string>();
        foreach (var i in items)
            if (i.Source == ItemSource.Plugins && FormatRank(i) < 2 && i.Path.Count > 1 && names.Add(i.Path[1])) ordered.Add(i.Path[1]);
        return ordered.OrderByDescending(Text.Count).ToList();
    }

    /// <summary>VST3/AU: the folder below the format. VST2 has no manufacturer folder → name prefix ("FabFilter Pro-L 2").</summary>
    static string? Vendor(PluginItem item, List<string> known)
    {
        if (FormatRank(item) < 2 && item.Path.Count > 1) return item.Path[1];
        return known.FirstOrDefault(v => Text.HasPrefix(item.Name, v + " "));
    }
}
