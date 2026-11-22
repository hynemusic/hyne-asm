using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>One plugin/device/preset on the Stats page.</summary>
public sealed record UsageStat(string Key, string Name, UsageKind Kind, int Count, double Share, string IconID, string? ColorID, bool IsAvailable)
{
    public string Id => Key;
}

public enum UsageKind
{
    Plugins, Live, MaxForLive, Presets,
    /// <summary>Chains and Live actions.</summary>
    Custom,
}

public static class UsageKindExtensions
{
    public static UsageKind FromSource(ItemSource source) => source switch
    {
        ItemSource.Plugins => UsageKind.Plugins,
        ItemSource.Instruments or ItemSource.AudioEffects or ItemSource.MidiEffects => UsageKind.Live,
        ItemSource.MaxForLive => UsageKind.MaxForLive,
        _ => UsageKind.Presets,
    };

    /// <summary>For keys of items Live doesn't list any more: the key starts with the source ("plugins|serum 2").</summary>
    internal static UsageKind FromKey(string key)
    {
        var source = Text.Split(key, '|', maxSplits: 1).FirstOrDefault() ?? "";
        if (Text.Equal(source, "preset")) return UsageKind.Presets;
        if (Text.Equal(source, "chain") || Text.Equal(source, "action")) return UsageKind.Custom;
        foreach (var s in Enum.GetValues<ItemSource>())
            if (Text.Equal(SwiftJson.RawValue(s), source)) return FromSource(s);
        return UsageKind.Plugins;
    }

    public static string Title(this UsageKind kind) => kind switch
    {
        UsageKind.Plugins => "Plugins",
        UsageKind.Live => Loc.T("Live-Devices", "Live Devices"),
        UsageKind.MaxForLive => "Max for Live",
        UsageKind.Presets => Loc.T("Eigene Presets", "Your Presets"),
        _ => Loc.T("Ketten & Aktionen", "Chains & Actions"),
    };
}

public sealed record UsageSummary(IReadOnlyList<UsageStat> Stats, int Total, IReadOnlyList<(UsageKind Kind, int Count)> ByKind)
{
    /// <summary>Share of all inserts that went to the <paramref name="n"/> most used.</summary>
    public double TopShare(int n) => Total == 0 ? 0 : (double)Stats.Take(n).Sum(s => s.Count) / Total;

    /// <summary>As in Swift: stats, total and the per-kind counts.</summary>
    public bool Equals(UsageSummary? o) => o is not null && Stats.SequenceEqual(o.Stats) && Total == o.Total &&
        ByKind.Select(k => k.Count).SequenceEqual(o.ByKind.Select(k => k.Count));

    public override int GetHashCode() => HashCode.Combine(Stats.Count, Total);
}

public static class UsageStats
{
    /// <summary>Turns the raw counts into named, sorted rows. Names, icons and colors come from Live's list and the menu;
    /// keys Live no longer lists keep a readable name taken from the key itself.</summary>
    public static UsageSummary Summarize(IReadOnlyDictionary<string, int> counts, IReadOnlyList<PluginItem> items, LauncherConfig config)
    {
        var keys = new PluginVariants.Keys(items);
        var byKey = new Dictionary<string, PluginItem>(Text.Canonical);
        foreach (var group in PluginVariants.Collapse(items)) byKey.TryAdd(keys.Key(group.Preferred), group.Preferred);
        var entries = config.AllPluginEntries;
        var total = counts.Values.Where(v => v > 0).Sum();

        var stats = counts.Where(p => p.Value > 0).Select(p =>
        {
            var (key, count) = (p.Key, p.Value);
            var item = byKey.GetValueOrDefault(key)
                ?? (Text.HasPrefix(key, "preset|") ? items.FirstOrDefault(i => Text.Equal("preset|" + i.Uri, key)) : null);
            var entry = item == null ? null : entries.FirstOrDefault(e => Text.Equal(e.Name, item.Name) && e.Source == item.Source);
            return new UsageStat(
                key,
                entry?.Title ?? item?.Name ?? ReadableName(key),
                item != null ? UsageKindExtensions.FromSource(item.Source) : UsageKindExtensions.FromKey(key),
                count,
                total == 0 ? 0 : (double)count / total,
                entry?.IconID ?? (item != null ? IconGuesser.Guess(item) : IconCatalog.DefaultID),
                item != null ? config.ColorID(item) : null,
                item != null);
        })
        .OrderByDescending(s => s.Count).ThenBy(s => s.Name, Comparer<string>.Create(Text.LocalizedCaseInsensitiveCompare)).ToList();

        var perKind = new Dictionary<UsageKind, int>();
        foreach (var s in stats) perKind[s.Kind] = perKind.GetValueOrDefault(s.Kind) + s.Count;
        var byKind = Enum.GetValues<UsageKind>().Where(perKind.ContainsKey).Select(k => (Kind: k, Count: perKind[k]))
            .OrderByDescending(k => k.Count).ToList();
        return new UsageSummary(stats, total, byKind);
    }

    /// <summary>"plugins|serum 2" → "Serum 2".</summary>
    public static string ReadableName(string key)
    {
        var name = Text.Split(key, '|', maxSplits: 1).LastOrDefault() ?? key;
        return string.Join(" ", Text.Split(name, ' ').Select(w =>
        {
            var first = Text.Characters(w).First();
            return Text.UpperCharacter(first) + w[first.Length..];
        }));
    }
}
