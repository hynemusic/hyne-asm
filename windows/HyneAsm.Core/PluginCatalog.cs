using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>Live's item list, cached in catalog-cache.json so the panel has items before Live answers.
/// The list comes from <c>listItems(rescan)</c> (the bridge client's list call; BridgeClient is ported in Task 8).</summary>
public sealed class PluginCatalog
{
    public IReadOnlyList<PluginItem> Items { get; private set; } = Array.Empty<PluginItem>();
    /// <summary>Built once per plugin list; use it to resolve entries while drawing.</summary>
    public EntryResolver.Index Index { get; private set; } = new(Array.Empty<PluginItem>());
    /// <summary>Raised when <see cref="Items"/> changed (Swift's <c>@Published</c>).</summary>
    public event EventHandler? ItemsChanged;

    readonly string cachePath;
    readonly Func<bool, Task<List<PluginItem>>> listItems;

    public PluginCatalog(string cachePath, Func<bool, Task<List<PluginItem>>> listItems)
    {
        this.cachePath = cachePath;
        this.listItems = listItems;
    }

    public static string DefaultCachePath => Path.Combine(Path.GetDirectoryName(ConfigStore.DefaultPath)!, "catalog-cache.json");

    /// <summary>A missing or unreadable cache leaves the items as they are.</summary>
    public void LoadCache()
    {
        List<PluginItem> cached;
        try { cached = SwiftJson.Deserialize<List<PluginItem>>(SwiftJson.DecodeUtf8(File.ReadAllBytes(cachePath))); }
        catch (Exception e) when (e is not OutOfMemoryException) { return; }
        SetItems(cached);
    }

    /// <summary>On failure the current items are kept (the error is passed on). <paramref name="rescan"/>: Live walks its
    /// browser again (new plugins, new presets). An unchanged list causes no change event and no cache write.</summary>
    public async Task Refresh(bool rescan = false)
    {
        var fresh = await listItems(rescan).ConfigureAwait(false);
        if (fresh.SequenceEqual(Items)) return;
        SetItems(fresh);
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(cachePath))!);
            AtomicFile.WriteText(cachePath, SwiftJson.Serialize(Items));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    void SetItems(List<PluginItem> items)
    {
        Items = items.ToList();
        Index = new EntryResolver.Index(Items);
        ItemsChanged?.Invoke(this, EventArgs.Empty);
    }
}
