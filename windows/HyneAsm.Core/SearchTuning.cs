using System.Text.Json.Serialization;
using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>The user's own shaping of search results for a search term: results pinned to the top (in this order)
/// and results hidden. A rule for "ser" also applies to "seru", "serum" … — the longest matching rule wins.</summary>
public sealed record SearchRule : IJsonOnDeserialized
{
    [JsonRequired] public Guid Id { get; set; } = Guid.NewGuid();
    /// <summary>Normalized: lowercase, single spaces.</summary>
    [JsonRequired] public string Query { get; set; } = "";
    /// <summary>Usage keys (<c>PluginVariants.Keys.key</c>) shown first, in this order. A pinned plugin is shown even if
    /// its name doesn't contain the search term ("verb" → Valhalla).</summary>
    [JsonRequired] public List<string> Pinned { get; set; } = new();
    /// <summary>Usage keys never shown for this search.</summary>
    [JsonRequired] public List<string> Hidden { get; set; } = new();

    /// <summary>For the JSON reader.</summary>
    public SearchRule() { }

    public SearchRule(string query, List<string>? pinned = null, List<string>? hidden = null)
    {
        Query = SearchTuning.Normalize(query);
        Pinned = pinned ?? new();
        Hidden = hidden ?? new();
    }

    void IJsonOnDeserialized.OnDeserialized()
    {
        SwiftJson.RejectNull(nameof(SearchRule), Query, Pinned, Hidden);
        SwiftJson.RejectNullElements(nameof(SearchRule), Pinned, Hidden);
    }

    internal bool IsEmpty => Pinned.Count == 0 && Hidden.Count == 0;

    public bool Equals(SearchRule? o) => o is not null && Id == o.Id && Query == o.Query &&
        ValueEquality.Lists(Pinned, o.Pinned) && ValueEquality.Lists(Hidden, o.Hidden);

    public override int GetHashCode() => HashCode.Combine(Id, Query, ValueEquality.Hash(Pinned), ValueEquality.Hash(Hidden));
}

public static class SearchTuning
{
    /// <summary>Lowercase, single spaces.</summary>
    public static string Normalize(string query) => Text.CollapseWhitespace(Text.Lower(query));

    /// <summary>The rule for a typed search: the longest rule query the search starts with.</summary>
    public static SearchRule? Rule(string query, IReadOnlyList<SearchRule> rules)
    {
        var q = Normalize(query);
        if (q.Length == 0) return null;
        SearchRule? best = null;
        var bestCount = 0;
        foreach (var r in rules)
        {
            if (r.Query.Length == 0 || !Text.HasPrefix(q, r.Query)) continue;
            var count = Text.Count(r.Query);
            if (best == null || count > bestCount) { best = r; bestCount = count; }   // Swift's max(by:) keeps the first
        }
        return best;
    }

    /// <summary>Hidden results removed, pinned ones moved to the front in pin order. Pinned keys missing from
    /// <paramref name="results"/> are added through <paramref name="inject"/> (return null to skip them).</summary>
    public static List<T> Apply<T>(IReadOnlyList<T> results, Func<T, string> key, SearchRule? rule, Func<string, T?>? inject = null)
        where T : class
    {
        if (rule == null) return results.ToList();
        var hidden = new HashSet<string>(rule.Hidden, Text.Canonical);
        var visible = results.Where(r => !hidden.Contains(key(r))).ToList();
        var byKey = new Dictionary<string, T>(Text.Canonical);
        foreach (var r in visible) byKey.TryAdd(key(r), r);
        var front = new List<T>();
        var used = new HashSet<string>(Text.Canonical);
        foreach (var k in rule.Pinned)
        {
            if (hidden.Contains(k) || used.Contains(k)) continue;
            var r = byKey.TryGetValue(k, out var hit) ? hit : inject?.Invoke(k);
            if (r != null) { front.Add(r); used.Add(k); }
        }
        return front.Concat(visible.Where(r => !used.Contains(key(r)))).ToList();
    }
}

public sealed partial record LauncherConfig
{
    public SearchRule? SearchRuleExactly(string query)
    {
        var q = SearchTuning.Normalize(query);
        return SearchRules.FirstOrDefault(r => Text.Equal(r.Query, q));
    }

    public void PinSearchResult(string key, string query) => EditRule(query, rule =>
    {
        rule.Hidden.RemoveAll(k => Text.Equal(k, key));
        if (!rule.Pinned.Any(k => Text.Equal(k, key))) rule.Pinned.Add(key);
    });

    public void UnpinSearchResult(string key, string query) => EditRule(query, rule => rule.Pinned.RemoveAll(k => Text.Equal(k, key)));

    public void HideSearchResult(string key, string query) => EditRule(query, rule =>
    {
        rule.Pinned.RemoveAll(k => Text.Equal(k, key));
        if (!rule.Hidden.Any(k => Text.Equal(k, key))) rule.Hidden.Add(key);
    });

    public void UnhideSearchResult(string key, string query) => EditRule(query, rule => rule.Hidden.RemoveAll(k => Text.Equal(k, key)));

    /// <summary>Moves a pinned result up (-1) or down (+1).</summary>
    public void MovePinnedSearchResult(string key, int offset, string query) => EditRule(query, rule =>
    {
        var i = rule.Pinned.FindIndex(k => Text.Equal(k, key));
        if (i < 0) return;
        var j = Math.Min(Math.Max(i + offset, 0), rule.Pinned.Count - 1);
        rule.Pinned.RemoveAt(i);
        rule.Pinned.Insert(j, key);
    });

    public void RemoveSearchRule(Guid id) => SearchRules.RemoveAll(r => r.Id == id);

    /// <summary>Creates the rule on first use and drops it again once it is empty. A new rule for "serum" starts as a
    /// copy of the "ser" rule that applied so far, so shaping a longer search doesn't lose the shorter one's choices.</summary>
    void EditRule(string query, Action<SearchRule> change)
    {
        var q = SearchTuning.Normalize(query);
        if (q.Length == 0) return;
        var inherited = SearchTuning.Rule(q, SearchRules);
        var existing = SearchRules.FirstOrDefault(r => Text.Equal(r.Query, q));
        // Swift's rule is a value: work on a copy, as the existing one is replaced below anyway.
        var rule = existing != null
            ? new SearchRule { Id = existing.Id, Query = existing.Query, Pinned = existing.Pinned.ToList(), Hidden = existing.Hidden.ToList() }
            : new SearchRule(q, inherited?.Pinned.ToList(), inherited?.Hidden.ToList());
        change(rule);
        SearchRules.RemoveAll(r => Text.Equal(r.Query, q));
        if (!rule.IsEmpty) SearchRules.Add(rule);
        SearchRules = SearchRules.OrderBy(r => r.Query, Comparer<string>.Create(Text.CompareScalars)).ToList();
    }
}
