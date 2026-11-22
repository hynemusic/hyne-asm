namespace HyneAsm.Core;

public sealed record QuickResult(PanelRow Row, string? Place);

/// <summary>The quick search: every category (and folder) first, then all installed plugins, ranked by match quality
/// and insert count. With nothing typed it offers the most used plugins (or Favorites when nothing is used yet).</summary>
public sealed class QuickSearch
{
    public const int MaxResults = 30;
    public const int MaxSuggestions = 8;

    sealed record Local(PanelRow Row, string Place, SearchMatcher.Prepared Prepared, int Order);

    readonly List<Local> local = new();
    readonly SearchIndex index;
    readonly List<QuickResult> favorites;
    readonly IReadOnlyDictionary<string, int> usage;
    readonly List<SearchRule> rules;

    /// <summary>Builds the index on the spot (tests, one-off use).</summary>
    public QuickSearch(LauncherConfig config, IReadOnlyList<PluginItem> items, IReadOnlyDictionary<string, int> usage)
        : this(config, new SearchIndex(items, config), usage) { }

    public QuickSearch(LauncherConfig config, SearchIndex index, IReadOnlyDictionary<string, int> usage)
    {
        // Swift's dictionary finds canonically equal keys.
        this.usage = new Dictionary<string, int>(usage.GroupBy(p => p.Key, Text.Canonical).Select(g => g.Last()), Text.Canonical);
        this.index = index;
        rules = config.SearchRules.ToList();

        PanelRow Row(Entry e)
        {
            if (PanelRow.Special(e, index, config.ColorID(e)) is { } special) return special;
            var resolved = index.Resolver.Resolve(e);
            var uri = resolved?.Uri ?? e.Uri;
            return new PanelRow
            {
                Uri = uri, Name = e.Name, Source = e.Source, Path = resolved?.Path ?? e.Path, IconID = e.IconID,
                Title = e.Title, IsAvailable = resolved != null,
                UsageKey = index.UsageKey.TryGetValue(uri, out var k) ? k : uri, ColorID = config.ColorID(e),
            };
        }

        var seen = new HashSet<string>(Text.Canonical);
        foreach (var category in config.Categories)
        {
            foreach (var e in category.Entries)
            {
                IEnumerable<(Entry Entry, string Place)> filed = e.IsFolder
                    ? (e.Children ?? new()).Select(c => (c, $"{category.Name} / {e.Title}"))
                    : new[] { (e, category.Name) };
                foreach (var (entry, place) in filed)
                {
                    var r = Row(entry);
                    if (!seen.Add(r.UsageKey)) continue;
                    local.Add(new Local(r, place, new SearchMatcher.Prepared(r.Title), local.Count));
                }
            }
        }
        var favoritesCategory = config.Categories.FirstOrDefault(c => c.IsFavorites);
        favorites = (favoritesCategory?.Entries ?? new()).Where(e => !e.IsFolder).Take(MaxSuggestions)
            .Select(e => new QuickResult(Row(e), favoritesCategory?.Name)).ToList();
    }

    int Uses(PanelRow r) => usage.TryGetValue(r.UsageKey, out var n) ? n : 0;

    public List<QuickResult> Results(string query)
    {
        if (Text.TrimWhitespaces(query).Length == 0) return Suggestions();
        var q = new SearchMatcher.Prepared(query);
        var tags = SearchVocabulary.Icons(query);
        // Ranking: match quality (name > typo > kind), then the user's insert count, then how well known it is.
        var localHits = local
            .Select(l => (L: l, Score: SearchMatcher.Score(l.Prepared, q, l.Row.IconID, tags)))
            .Where(x => x.Score != null)
            .OrderByDescending(x => x.Score!.Value)
            .ThenByDescending(x => Uses(x.L.Row))
            .ThenByDescending(x => Popularity.Score(x.L.Row.Title))
            .ThenBy(x => x.L.Order)
            .Select(x => new QuickResult(x.L.Row, x.L.Place))
            .ToList();
        var shown = new HashSet<string>(localHits.Select(h => h.Row.UsageKey), Text.Canonical);
        var global = new List<(PanelRow Row, int Score, int Popularity)>();
        for (var i = 0; i < index.GlobalRows.Count; i++)
        {
            var r = index.GlobalRows[i];
            if (shown.Contains(r.UsageKey)) continue;
            if (SearchMatcher.Score(index.GlobalPrepared[i], q, r.IconID, tags) is { } score)
                global.Add((r, score, index.GlobalPopularity[i]));
        }
        // Stable: alphabetical after that.
        var globalHits = global
            .OrderByDescending(g => g.Score).ThenByDescending(g => Uses(g.Row)).ThenByDescending(g => g.Popularity)
            .Select(g => new QuickResult(g.Row, null));
        // The user's search rules: hidden results go, pinned ones lead (even if their name doesn't match).
        var shaped = SearchTuning.Apply(localHits.Concat(globalHits).ToList(), r => r.Row.UsageKey, SearchTuning.Rule(query, rules), key =>
        {
            var l = local.FirstOrDefault(x => Text.Equal(x.Row.UsageKey, key));
            if (l != null) return new QuickResult(l.Row, l.Place);
            return index.GlobalRow(key) is { } row ? new QuickResult(row, null) : null;
        });
        return shaped.Take(MaxResults).ToList();
    }

    /// <summary>Most used plugins first; without any history, the Favorites.</summary>
    List<QuickResult> Suggestions()
    {
        var byUse = local.Select(l => (Row: l.Row, Place: (string?)l.Place))
            .Concat(index.GlobalRows.Select(r => (Row: r, Place: (string?)null)))
            .Where(x => Uses(x.Row) > 0);
        var seen = new HashSet<string>(Text.Canonical);
        var ranked = byUse.OrderByDescending(x => Uses(x.Row))
            .Where(x => seen.Add(x.Row.UsageKey))
            .Take(MaxSuggestions)
            .Select(x => new QuickResult(x.Row, x.Place))
            .ToList();
        return ranked.Count == 0 ? favorites : ranked;
    }
}

/// <summary>Typing and keys of the quick search window.</summary>
public sealed class QuickSearchState
{
    readonly QuickSearch search;
    readonly TextInput input = new();
    public string Query => input.Text;
    /// <summary>Select-all selected the whole query (drawn highlighted; the next key replaces it).</summary>
    public bool IsQuerySelected => input.IsAllSelected;
    public int Highlighted { get; private set; }
    public List<QuickResult> Results { get; private set; }

    public QuickSearchState(QuickSearch search)
    {
        this.search = search;
        Results = search.Results("");
    }

    public PanelAction Handle(PanelKey key)
    {
        switch (key.Kind)
        {
            case PanelKeyKind.Down:
                input.Deselect();
                Highlighted = Math.Min(Highlighted + 1, Math.Max(Results.Count - 1, 0));
                break;
            case PanelKeyKind.Up:
                input.Deselect();
                Highlighted = Math.Max(Highlighted - 1, 0);
                break;
            case PanelKeyKind.ReturnKey:
                if (Highlighted < 0 || Highlighted >= Results.Count || !Results[Highlighted].Row.IsAvailable) return PanelAction.None;
                return PanelAction.Insert(Results[Highlighted].Row);
            case PanelKeyKind.Escape: return PanelAction.Close;
            case PanelKeyKind.Left: case PanelKeyKind.Right: case PanelKeyKind.Tab: break;
            default:
                var before = Query;
                if (input.Apply(key) && !Text.Equal(Query, before))
                {
                    Results = search.Results(Query);
                    Highlighted = 0;
                }
                break;
        }
        return PanelAction.None;
    }

    public void Highlight(int index)
    {
        if (index >= 0 && index < Results.Count) Highlighted = index;
    }
}
