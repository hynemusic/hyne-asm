using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>Live's item list, cached in catalog-cache.json so the panel has items before Live answers.
/// The list comes from the bridge (<see cref="BridgeClient.ListItems"/>), or from any list function (tests).
/// <para>Threading: Swift's catalog is <c>@MainActor</c>; this one is not. <see cref="Refresh"/> continues on a thread-pool
/// thread (<c>ConfigureAwait(false)</c>), so <see cref="Items"/>/<see cref="Index"/> are replaced and
/// <see cref="ItemsChanged"/> is raised there, not on the UI thread. Each property is swapped as a whole (readers never see
/// a half-built list); the UI (Plan 2) marshals the event to its dispatcher before redrawing.</para></summary>
public sealed class PluginCatalog
{
    public IReadOnlyList<PluginItem> Items { get; private set; } = Array.Empty<PluginItem>();
    /// <summary>Built once per plugin list; use it to resolve entries while drawing.</summary>
    public EntryResolver.Index Index { get; private set; } = new(Array.Empty<PluginItem>());
    /// <summary>Raised when <see cref="Items"/> changed (Swift's <c>@Published</c>), on whichever thread made the change:
    /// the caller's for <see cref="LoadCache"/>, a thread-pool thread for <see cref="Refresh"/>.</summary>
    public event EventHandler? ItemsChanged;

    readonly string cachePath;
    readonly Func<bool, Task<List<PluginItem>>> listItems;

    /// <summary>The list from Live, through the bridge client (as in Swift).</summary>
    public PluginCatalog(string cachePath, BridgeClient client) : this(cachePath, rescan => client.ListItems(rescan)) { }

    /// <summary><paramref name="listItems"/>(rescan) returns the current list or throws.</summary>
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
