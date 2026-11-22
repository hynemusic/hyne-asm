namespace HyneAsm.Core;

/// <summary>What searching needs from Live's plugin list, worked out once and shared by the panel and the quick search.
/// Building it costs ~50–130 ms for ~3,500 items on the Mac (merging formats, sorting, guessing icons), so it is rebuilt
/// only when the plugin list or the menu changes — not on every double-right-click or quick search.</summary>
public sealed class SearchIndex
{
    public EntryResolver.Index Resolver { get; }
    /// <summary>uri → usage key (all formats of a plugin share one key).</summary>
    public IReadOnlyDictionary<string, string> UsageKey { get; }
    /// <summary>One row per plugin in its best format, alphabetical, icon guessed, colour resolved, marked as a global hit.</summary>
    public IReadOnlyList<PanelRow> GlobalRows { get; }
    public IReadOnlyList<SearchMatcher.Prepared> GlobalPrepared { get; }
    /// <summary><c>Popularity.Score</c> per global row (tie-break after the user's own counts).</summary>
    public IReadOnlyList<int> GlobalPopularity { get; }
    readonly Dictionary<string, int> rowIndexByKey = new(Text.Canonical);
    /// <summary>Other versions of a plugin (formats, Mono/Stereo), for "Insert as …"; only for plugins that have some.</summary>
    readonly Dictionary<string, List<PluginItem>> alternativesByKey = new(Text.Canonical);

    public SearchIndex(IReadOnlyList<PluginItem> items, LauncherConfig config, IReadOnlySet<string>? newURIs = null)
    {
        Resolver = new EntryResolver.Index(items);
        var keys = new PluginVariants.Keys(items);
        var usageKey = new Dictionary<string, string>(Text.Canonical);
        foreach (var item in items) usageKey[item.Uri] = keys.Key(item);
        UsageKey = usageKey;
        var isNew = newURIs == null ? null : new HashSet<string>(newURIs, Text.Canonical);
        var groups = PluginVariants.Collapse(items);
        foreach (var g in groups.Where(g => g.Variants.Count > 1))
            alternativesByKey[keys.Key(g.Preferred)] = g.Variants.Skip(1).ToList();
        // Merged Mono/Stereo versions show the plain name ("REDD17"); a single version keeps its full name.
        var rows = groups
            .Select(g => (Item: g.Preferred, Title: g.Channels.Count == 0 ? g.Preferred.Name : PluginVariants.Channel(g.Preferred.Name).Base))
            .OrderBy(e => e.Title, Comparer<string>.Create(Text.LocalizedCaseInsensitiveCompare))
            .Select(e => new PanelRow
            {
                Uri = e.Item.Uri, Name = e.Item.Name, Source = e.Item.Source, Path = e.Item.Path,
                IconID = IconGuesser.Guess(e.Item), Title = e.Title, IsAvailable = true, IsGlobal = true,
                UsageKey = keys.Key(e.Item), ColorID = config.ColorID(e.Item), IsNew = isNew?.Contains(e.Item.Uri) == true,
            })
            .ToList();
        GlobalRows = rows;
        GlobalPrepared = rows.Select(r => new SearchMatcher.Prepared(r.Title)).ToList();
        GlobalPopularity = rows.Select(r => Popularity.Score(r.Title)).ToList();
        for (var i = 0; i < rows.Count; i++) rowIndexByKey.TryAdd(rows[i].UsageKey, i);
    }

    public IReadOnlyList<PluginItem> Alternatives(string key) =>
        alternativesByKey.TryGetValue(key, out var list) ? list : Array.Empty<PluginItem>();

    public PanelRow? GlobalRow(string key) => rowIndexByKey.TryGetValue(key, out var i) ? GlobalRows[i] : null;
}
