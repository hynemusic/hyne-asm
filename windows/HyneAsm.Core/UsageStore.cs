using System.Text.Json;
using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>How often each plugin was inserted (key: <c>PluginVariants.Keys.Key</c>, so all formats count together).
/// From SearchMatcher.swift. usage.json is written compact, as Swift's plain <c>JSONEncoder</c> does.</summary>
public sealed class UsageStore
{
    readonly Dictionary<string, int> counts;
    readonly string path;

    /// <summary>A copy (Swift returns the dictionary by value).</summary>
    public Dictionary<string, int> Counts => new(counts, Text.Canonical);

    /// <summary>A missing or unreadable file starts empty (no backup, as on the Mac).</summary>
    public UsageStore(string path)
    {
        this.path = path;
        try { counts = SwiftJson.ReadCounts(SwiftJson.DecodeUtf8(File.ReadAllBytes(path))); }
        catch (Exception e) when (e is not OutOfMemoryException) { counts = new(Text.Canonical); }
    }

    public static string DefaultPath => Path.Combine(Path.GetDirectoryName(ConfigStore.DefaultPath)!, "usage.json");

    /// <summary>Raised after every change, so an open Stats page can refresh (Swift's <c>didChange</c> notification).</summary>
    public static event EventHandler? DidChange;

    public void Record(string key)
    {
        counts[key] = counts.GetValueOrDefault(key) + 1;
        Save();
    }

    /// <summary>Replaces everything (import "replace", reset with an empty dictionary).</summary>
    public void ReplaceAll(IReadOnlyDictionary<string, int> newCounts)
    {
        counts.Clear();
        foreach (var (k, v) in newCounts) if (v > 0) counts[k] = v;
        Save();
    }

    /// <summary>Adds imported counts to the existing ones.</summary>
    public void Merge(IReadOnlyDictionary<string, int> other)
    {
        foreach (var (k, v) in other) if (v > 0) counts[k] = counts.GetValueOrDefault(k) + v;
        Save();
    }

    public void Reset() => ReplaceAll(new Dictionary<string, int>());

    /// <summary>Forgets one plugin's count (Stats page), so it no longer ranks higher in search.</summary>
    public void Remove(string key)
    {
        counts.Remove(key);
        Save();
    }

    /// <summary>Like Swift's <c>try?</c>: a failed write is ignored.</summary>
    void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
            AtomicFile.WriteText(path, SwiftJson.Serialize(counts));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        DidChange?.Invoke(this, EventArgs.Empty);
    }
}

/// <summary>The file the Stats page exports and imports (<c>.hmlusage</c>): the insert counts that rank search results.</summary>
public sealed class UsageExport
{
    public const string FormatID = "hyne-asm-usage";
    public const string FileExtension = "hmlusage";

    public string Format { get; set; } = FormatID;
    public int Version { get; set; } = 1;
    [System.Text.Json.Serialization.JsonConverter(typeof(SwiftJson.Iso8601Converter))]
    public DateTime Exported { get; set; }
    public Dictionary<string, int> Counts { get; set; }

    public UsageExport(IReadOnlyDictionary<string, int> counts, DateTime? exported = null)
    {
        Counts = new Dictionary<string, int>(counts, Text.Canonical);
        Exported = exported ?? DateTime.UtcNow;
    }

    /// <summary>Pretty-printed, sorted keys, ISO-8601 date.</summary>
    public byte[] Data() => SwiftJson.EncodeUtf8(SwiftJson.Serialize(this, pretty: true));

    public sealed class NotUsageFile : Exception
    {
        public NotUsageFile() : base("not a usage file") { }
    }

    /// <summary>Reads an export, or a raw usage.json copied out of the app's folder (every key holds a "|").</summary>
    public static Dictionary<string, int> Read(byte[] data)
    {
        JsonDocument doc;
        try
        {
            var text = SwiftJson.DecodeUtf8(data);
            doc = JsonDocument.Parse(text.StartsWith('﻿') ? text[1..] : text);
        }
        catch (Exception e) when (e is JsonException or System.Text.DecoderFallbackException) { throw new NotUsageFile(); }
        using (doc)
        {
            if (TryExport(doc.RootElement) is { } exported) return exported;
            try
            {
                var raw = SwiftJson.ReadCounts(doc.RootElement);
                if (raw.Keys.All(k => Text.Contains(k, "|"))) return raw;
            }
            catch (JsonException) { }
            throw new NotUsageFile();
        }
    }

    /// <summary>The counts of a decodable export (all four fields present and valid) with our format id, else null.</summary>
    static Dictionary<string, int>? TryExport(JsonElement root)
    {
        try
        {
            if (root.ValueKind != JsonValueKind.Object) return null;
            if (!root.TryGetProperty("format", out var format) || format.ValueKind != JsonValueKind.String) return null;
            if (!root.TryGetProperty("version", out var version)) return null;
            SwiftJson.ReadInt(version);
            if (!root.TryGetProperty("exported", out var exported) || exported.ValueKind != JsonValueKind.String
                || !SwiftJson.TryParseIso8601(exported.GetString()!, out _)) return null;
            if (!root.TryGetProperty("counts", out var counts)) return null;
            var result = SwiftJson.ReadCounts(counts);
            return Text.Equal(format.GetString(), FormatID) ? result : null;
        }
        catch (JsonException) { return null; }
    }
}
