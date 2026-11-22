using System.Text.Json.Serialization;

namespace HyneAsm.Core;

/// <summary>The user's own shaping of search results for a search term: results pinned to the top (in this order)
/// and results hidden. A rule for "ser" also applies to "seru", "serum" … — the longest matching rule wins.</summary>
public sealed record SearchRule
{
    [JsonRequired] public Guid Id { get; set; } = Guid.NewGuid();
    /// <summary>Normalized: lowercase, single spaces.</summary>
    [JsonRequired] public string Query { get; set; } = "";
    /// <summary>Usage keys (<c>PluginVariants.Keys.key</c>) shown first, in this order. A pinned plugin is shown even if
    /// its name doesn't contain the search term ("verb" → Valhalla).</summary>
    [JsonRequired] public List<string> Pinned { get; set; } = new();
    /// <summary>Usage keys never shown for this search.</summary>
    [JsonRequired] public List<string> Hidden { get; set; } = new();

    internal bool IsEmpty => Pinned.Count == 0 && Hidden.Count == 0;

    public bool Equals(SearchRule? o) => o is not null && Id == o.Id && Query == o.Query &&
        ValueEquality.Lists(Pinned, o.Pinned) && ValueEquality.Lists(Hidden, o.Hidden);

    public override int GetHashCode() => HashCode.Combine(Id, Query, ValueEquality.Hash(Pinned), ValueEquality.Hash(Hidden));
}
