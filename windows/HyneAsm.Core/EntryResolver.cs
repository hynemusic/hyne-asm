namespace HyneAsm.Core;

public static class EntryResolver
{
    /// <summary>1. same uri; 2. same name + source, preferring the same browser path; 3. null.</summary>
    public static PluginItem? Resolve(Entry entry, IReadOnlyList<PluginItem> items)
    {
        var exact = items.FirstOrDefault(i => Text.Equal(i.Uri, entry.Uri));
        if (exact != null) return exact;
        var candidates = items.Where(i => Text.Equal(i.Name, entry.Name) && i.Source == entry.Source).ToList();
        return candidates.FirstOrDefault(i => Text.Equal(i.Path, entry.Path)) ?? candidates.FirstOrDefault();
    }

    /// <summary>Same rules as <see cref="Resolve(Entry, IReadOnlyList{PluginItem})"/>, with dictionary lookups — build
    /// once per plugin list, then resolve entries in O(1).</summary>
    public sealed class Index
    {
        readonly Dictionary<string, PluginItem> byURI = new(Text.Canonical);
        readonly Dictionary<(string Name, ItemSource Source), List<PluginItem>> byName = new(new KeyComparer());

        public Index(IReadOnlyList<PluginItem> items)
        {
            foreach (var item in items)
            {
                byURI.TryAdd(item.Uri, item);
                var key = (item.Name, item.Source);
                if (!byName.TryGetValue(key, out var list)) byName[key] = list = new();
                list.Add(item);
            }
        }

        public PluginItem? Resolve(Entry entry)
        {
            if (byURI.TryGetValue(entry.Uri, out var exact)) return exact;
            if (!byName.TryGetValue((entry.Name, entry.Source), out var candidates)) return null;
            return candidates.FirstOrDefault(i => Text.Equal(i.Path, entry.Path)) ?? candidates.FirstOrDefault();
        }

        sealed class KeyComparer : IEqualityComparer<(string Name, ItemSource Source)>
        {
            public bool Equals((string Name, ItemSource Source) a, (string Name, ItemSource Source) b) =>
                a.Source == b.Source && Text.Equal(a.Name, b.Name);

            public int GetHashCode((string Name, ItemSource Source) k) => HashCode.Combine(Text.Canonical.GetHashCode(k.Name), k.Source);
        }
    }
}
