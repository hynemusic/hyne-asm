using System.Text.Json;
using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>When the app first saw each item in Live's list (<c>seen.json</c>), to mark newly installed plugins and presets.
/// The file is compact JSON with ISO-8601 dates, as Swift's plain <c>JSONEncoder</c> with <c>.iso8601</c> writes it.</summary>
public sealed class SeenStore
{
    /// <summary>Swift's <c>Date.distantPast</c>, written as "0001-01-01T00:00:00Z" on both platforms.</summary>
    public static readonly DateTime DistantPast = DateTime.SpecifyKind(DateTime.MinValue, DateTimeKind.Utc);

    public string Path { get; }
    readonly Dictionary<string, DateTime> firstSeen;
    readonly object gate = new();

    /// <summary>A missing or damaged file starts empty. A file that exists but can't be read (locked, no permission;
    /// retried briefly) also starts empty, but the store is then <see cref="IsReadOnly"/>.</summary>
    public SeenStore(string path)
    {
        Path = path;
        byte[]? data = null;
        try { data = StoreFile.Read(path); }
        catch (IOException) { IsReadOnly = true; }
        try { firstSeen = data == null ? new(Text.Canonical) : Read(SwiftJson.DecodeUtf8(data)); }
        catch (Exception e) when (e is not OutOfMemoryException) { firstSeen = new(Text.Canonical); }
    }

    /// <summary>seen.json existed but couldn't be read when the store was opened. Dates are still recorded in memory,
    /// but the file is never written, so the real first-seen dates survive. Differs from Swift, which would overwrite them.</summary>
    public bool IsReadOnly { get; }

    static Dictionary<string, DateTime> Read(string text)
    {
        using var doc = JsonDocument.Parse(text.StartsWith('﻿') ? text[1..] : text);
        if (doc.RootElement.ValueKind != JsonValueKind.Object) throw new JsonException("seen.json must be an object");
        var result = new Dictionary<string, DateTime>(Text.Canonical);
        foreach (var p in doc.RootElement.EnumerateObject())
        {
            if (p.Value.ValueKind != JsonValueKind.String || !SwiftJson.TryParseIso8601(p.Value.GetString()!, out var d))
                throw new JsonException("not a date");
            result[p.Name] = d;
        }
        return result;
    }

    public static string DefaultPath => System.IO.Path.Combine(System.IO.Path.GetDirectoryName(ConfigStore.DefaultPath)!, "seen.json");

    /// <summary>Records items not seen before. On the very first run everything counts as known (no flood of NEW badges).</summary>
    public void Update(IEnumerable<PluginItem> items, DateTime? now = null)
    {
        lock (gate)
        {
            var when = now ?? DateTime.UtcNow;
            var firstRun = firstSeen.Count == 0;
            var changed = false;
            foreach (var item in items)
            {
                if (firstSeen.ContainsKey(item.Uri)) continue;
                firstSeen[item.Uri] = firstRun ? DistantPast : when;
                changed = true;
            }
            if (!changed || IsReadOnly) return;
            try
            {
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(Path))!);
                var text = SwiftJson.Serialize(firstSeen.ToDictionary(p => p.Key, p => SwiftJson.FormatIso8601(p.Value)));
                AtomicFile.WriteText(Path, text);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
    }

    internal DateTime? Date(string uri)
    {
        lock (gate) return firstSeen.TryGetValue(uri, out var d) ? d : null;
    }
}

public static class NewItems
{
    /// <summary>How long a newly installed item stays marked as new.</summary>
    public static readonly TimeSpan Window = TimeSpan.FromDays(14);

    /// <summary>Items first seen within the window that are neither filed in a category nor ever inserted.</summary>
    public static HashSet<string> Uris(IReadOnlyList<PluginItem> items, SeenStore seen, LauncherConfig config,
        IReadOnlyDictionary<string, int> usage, DateTime? now = null)
    {
        var when = now ?? DateTime.UtcNow;
        var keys = new PluginVariants.Keys(items);
        var filed = config.AllPluginEntries;
        var filedURIs = new HashSet<string>(filed.Select(e => e.Uri), Text.Canonical);
        var filedNames = new HashSet<string>(filed.Select(e => SwiftJson.RawValue(e.Source) + "|" + e.Name), Text.Canonical);
        var result = new HashSet<string>(Text.Canonical);
        foreach (var item in items)
        {
            if (seen.Date(item.Uri) is not { } date || when - date >= Window || date == SeenStore.DistantPast) continue;
            if (filedURIs.Contains(item.Uri) || filedNames.Contains(SwiftJson.RawValue(item.Source) + "|" + item.Name)) continue;
            if (usage.GetValueOrDefault(keys.Key(item)) > 0) continue;
            result.Add(item.Uri);
        }
        return result;
    }
}

/// <summary>Panel entries that are hardly ever used — candidates to remove (Stats page). <see cref="Entry"/> is a copy.</summary>
public sealed record RareEntry(Entry Entry, Guid CategoryID, string Place, int Count)
{
    public Guid Id => Entry.Id;
}

public static class RarelyUsed
{
    /// <summary>Entries (plugins, chains, actions — also inside folders) inserted at most <paramref name="threshold"/> times,
    /// fewest first. Entries the user chose to keep are left out.</summary>
    public static List<RareEntry> Entries(LauncherConfig config, SearchIndex index, IReadOnlyDictionary<string, int> usage, int threshold = 1)
    {
        var kept = config.KeptEntries.ToHashSet();
        var result = new List<RareEntry>();
        foreach (var category in config.Categories)
            foreach (var e in category.Entries)
            {
                var filed = e.IsFolder
                    ? (e.Children ?? new()).Select(c => (Entry: c, Place: $"{category.Name} / {e.Title}"))
                    : new[] { (Entry: e, Place: category.Name) };
                foreach (var (entry, place) in filed)
                {
                    if (kept.Contains(entry.Id)) continue;
                    var count = usage.GetValueOrDefault(UsageKey(entry, index));
                    if (count <= threshold) result.Add(new RareEntry(SwiftJson.Clone(entry), category.Id, place, count));
                }
            }
        return result.OrderBy(r => r.Count).ThenBy(r => r.Entry.Title, Comparer<string>.Create(Text.LocalizedCaseInsensitiveCompare)).ToList();
    }

    internal static string UsageKey(Entry e, SearchIndex index)
    {
        if (e.Action != null) return "action|" + Text.Lower(e.Title);
        if (e.Chain != null) return "chain|" + Text.Lower(e.Title);
        var uri = index.Resolver.Resolve(e)?.Uri ?? e.Uri;
        return index.UsageKey.TryGetValue(uri, out var key) ? key : uri;
    }
}

public sealed partial record LauncherConfig
{
    /// <summary>"Keep": stop listing this entry as rarely used.</summary>
    public void KeepEntry(Guid id)
    {
        if (!KeptEntries.Contains(id)) KeptEntries.Add(id);
    }
}
