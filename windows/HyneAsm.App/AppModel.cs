using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Threading;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>Shared app state. Every config change is saved immediately.</summary>
sealed class AppModel
{
    readonly Dispatcher ui;
    readonly ConfigStore store;
    SearchIndex? cachedIndex;
    DispatcherTimer? rebuild;

    public LauncherConfig Config { get; private set; }
    public bool ConfigExistedAtLaunch { get; }
    public BridgeClient Client { get; } = new();
    public PluginCatalog Catalog { get; }
    public UsageStore Usage { get; } = new(UsageStore.DefaultPath);
    public SeenStore Seen { get; } = new(SeenStore.DefaultPath);
    public MenuVersionStore Versions { get; } = new(MenuVersionStore.DefaultDirectory);
    public HashSet<string> NewUris { get; private set; } = new();

    public bool IsConnected { get; private set; }
    public HelloResult? Hello { get; private set; }
    public bool PanelOpened { get; set; }

    /// <summary>Raised on the UI thread after any config, connection or plugin-list change.</summary>
    public event Action? Changed;
    public Hud Hud { get; } = new();
    public StreamDeckServer StreamDeck { get; } = new();

    public AppModel(Dispatcher ui, LauncherConfig loaded, ConfigStore store, bool existed)
    {
        this.ui = ui;
        this.store = store;
        ConfigExistedAtLaunch = existed;
        Config = loaded;
        WindowsDefaults.Apply(Config, existed);
        Loc.Language = LanguageExtensions.Resolve(Config.Language);
        Theme.Apply(Config.Theme);
        Catalog = new PluginCatalog(PluginCatalog.DefaultCachePath, Client);
        Catalog.ItemsChanged += (_, _) => ui.BeginInvoke(() => { InvalidateSearchIndex(); Changed?.Invoke(); });
        Save();   // persists migrations right away
    }

    public void Start()
    {
        Catalog.LoadCache();
        InvalidateSearchIndex();
        Client.SetConnectionHandler(c => ui.BeginInvoke(() => ConnectionChanged(c)));
        Client.Start();
    }

    /// <summary>Call after changing <see cref="Config"/> in place.</summary>
    public void ConfigChanged()
    {
        Loc.Language = LanguageExtensions.Resolve(Config.Language);
        Theme.Apply(Config.Theme);
        InvalidateSearchIndex();
        Save();
        Changed?.Invoke();
    }

    void Save()
    {
        try { store.Save(Config); }
        catch (Exception e) { Hud.Show(Loc.T("Speichern fehlgeschlagen: ", "Saving failed: ") + e.Message); }
    }

    // MARK: Search data, rebuilt only when the plugin list or the menu changed

    public SearchIndex SearchIndex => cachedIndex ??= new SearchIndex(Catalog.Items, Config, NewUris);

    /// <summary>Drops the index and builds the new one shortly after (changes come in bursts), off the UI thread,
    /// so the next double right-click finds it ready.</summary>
    void InvalidateSearchIndex()
    {
        cachedIndex = null;
        rebuild ??= new DispatcherTimer(TimeSpan.FromMilliseconds(400), DispatcherPriority.Background, async (_, _) =>
        {
            rebuild!.Stop();
            var items = Catalog.Items;
            var config = SwiftJsonClone(Config);
            var counts = new Dictionary<string, int>(Usage.Counts);
            var (index, fresh) = await Task.Run(() =>
            {
                Seen.Update(items);
                var f = NewItems.Uris(items, Seen, config, counts);
                return (new SearchIndex(items, config, f), f);
            });
            NewUris = fresh;
            cachedIndex ??= index;
        }, ui);
        rebuild.Stop();
        rebuild.Start();
    }

    static LauncherConfig SwiftJsonClone(LauncherConfig c) => HyneAsm.Core.Json.SwiftJson.Clone(c);

    // MARK: Inserting

    /// <summary>The one way anything gets inserted (panel, quick search, shortcuts, Stream Deck).</summary>
    public void Insert(PanelRow row)
    {
        if (row.Action is { } action) Run(action, row.UsageKey);
        else InsertUris(row.Chain ?? new[] { row.Uri }, row.UsageKey);
    }

    public async void Run(LiveAction action, string usageKey)
    {
        try
        {
            await Client.Run(action);
            Usage.Record(usageKey);
        }
        catch (BridgeError e) when (e.Kind == BridgeErrorKind.NotConnected) { Hud.Show(Loc.T("Nicht mit Live verbunden", "Not connected to Live")); }
        catch (BridgeError e) when (e.Kind == BridgeErrorKind.Remote && e.Message.Contains("unknown_cmd"))
        {
            Hud.Show(Loc.T("Live-Script aktualisieren (Tray-Menü → Live-Script installieren)", "Update the Live script (tray menu → Install Live Script)"));
        }
        catch (Exception) { Hud.Show(Loc.T("Aktion fehlgeschlagen", "Action failed")); }
    }

    /// <summary>One plugin or a chain, where the Behavior settings say.</summary>
    public async void InsertUris(IReadOnlyList<string> uris, string usageKey)
    {
        var options = Config.Insert;
        var oldScript = (int.TryParse(Hello?.ScriptVersion, out var v) ? v : 4) < 4;
        try
        {
            if (oldScript && uris.Count > 1) foreach (var uri in uris) await Client.Load(new[] { uri }, options);
            else await Client.Load(uris, options);
            Usage.Record(usageKey);
        }
        catch (BridgeError e) when (e.Kind == BridgeErrorKind.NotConnected) { Hud.Show(Loc.T("Nicht mit Live verbunden", "Not connected to Live")); }
        catch (BridgeError e) when (e.Kind == BridgeErrorKind.Remote && e.Message.StartsWith("not_found")) { Hud.Show(Loc.T("Plugin nicht gefunden", "Plugin not found")); }
        catch (Exception) { Hud.Show(Loc.T("Laden fehlgeschlagen", "Loading failed")); }
    }

    /// <summary>A plugin shortcut: insert straight into the selected track (best format, like the panel).</summary>
    public void Insert(ItemShortcut shortcut)
    {
        var items = Catalog.Items;
        var target = items.FirstOrDefault(i => i.Uri == shortcut.Uri)
            ?? PluginVariants.Collapse(items.Where(i => i.Name == shortcut.Name && i.Source == shortcut.Source).ToList()).FirstOrDefault()?.Preferred;
        if (target == null) { Hud.Show(Loc.T($"„{shortcut.Name}“ nicht gefunden", $"“{shortcut.Name}” not found")); return; }
        InsertUris(new[] { target.Uri }, SearchIndex.UsageKey.TryGetValue(target.Uri, out var k) ? k : target.Uri);
    }

    public async void RefreshCatalog()
    {
        try { await Catalog.Refresh(rescan: true); Hud.Show(Loc.T("Plugin-Liste neu geladen", "Plugin list reloaded")); }
        catch (Exception) { Hud.Show(Loc.T("Nicht mit Live verbunden", "Not connected to Live")); }
    }

    async void ConnectionChanged(bool connected)
    {
        IsConnected = connected;
        if (!connected) { Hello = null; Changed?.Invoke(); return; }
        Changed?.Invoke();
        try
        {
            Hello = await Client.Hello();
            Changed?.Invoke();
            await Catalog.Refresh();
        }
        catch (Exception) { /* the next reconnect tries again */ }
    }

    // MARK: Menus: versions, import, export

    void Backup(string reason) => Versions.Save(reason, Config.Categories, isAutomatic: true);

    public void ImportMenuFile(string path)
    {
        var doc = MenuDocument.Read(path);
        Backup(Loc.T($"Vor Import von „{doc.Name}“", $"Before importing “{doc.Name}”"));
        Config.RestoreMenu(doc.Categories);
        ConfigChanged();
    }

    public void RestoreVersion(MenuVersion version)
    {
        var doc = Versions.Load(version.Id);
        Backup(Loc.T($"Vor Wiederherstellen von „{version.Name}“", $"Before restoring “{version.Name}”"));
        Config.RestoreMenu(doc.Categories);
        ConfigChanged();
    }

    public void ExportMenu(string path) =>
        new MenuDocument(Path.GetFileNameWithoutExtension(path), Config.Categories).Write(path);

    public ImportDraft LESDraft(string path) => ImportDraft.Make(File.ReadAllText(path), Catalog.Items);

    public void ApplyLES(ImportDraft draft, ImportMode mode)
    {
        Backup(Loc.T("Vor LES-Import", "Before LES import"));
        Config.Apply(draft, mode);
        ConfigChanged();
    }

    public void ToggleFavorite(PanelRow row)
    {
        var fav = Config.FavoritesID;
        if (Config.FavoriteEntry(row, Catalog.Items) is { } entry) Config.RemoveEntry(entry.Id, fav);
        else Config.AddEntry(new PluginItem(row.Uri, row.Name, row.Source, row.Path), fav);
        ConfigChanged();
    }

    public bool IsFavorite(PanelRow row) => Config.FavoriteEntry(row, Catalog.Items) != null;

    public void AddToCategory(PanelRow row, Guid category)
    {
        Config.AddEntry(new PluginItem(row.Uri, row.Name, row.Source, row.Path), category);
        ConfigChanged();
    }
}
