using System.Text;
using System.Text.Json.Nodes;
using HyneAsm.Core.Json;

namespace HyneAsm.Core.Tests;

/// <summary>Mirrors MenuVersionStoreTests, UsageStatsTests and PluginCatalogTests (Swift), plus the Windows-only file rules.</summary>
public class FilesTests : IDisposable
{
    readonly string dir = Path.Combine(Path.GetTempPath(), "hyneasm-files-" + Guid.NewGuid().ToString("N"));

    public FilesTests() => Directory.CreateDirectory(dir);

    public void Dispose()
    {
        try { Directory.Delete(dir, recursive: true); } catch (IOException) { }
    }

    static PluginItem Item(string name, ItemSource source = ItemSource.Plugins) => new("u:" + name, name, source, Array.Empty<string>());

    static LauncherConfig SampleConfig()
    {
        var c = LauncherConfig.MakeDefault();
        c.AddEntry(Item("Utility", ItemSource.AudioEffects), c.FavoritesID);
        c.AddEntry(Item("Serum"), c.Categories[1].Id);
        return c;
    }

    [Fact]
    public void MenuVersionStore_prunes_automatic_to_30_keeps_manual()
    {
        var store = new MenuVersionStore(Path.Combine(dir, "Versions"));
        var manual = store.Save("Mine", new List<Category>(), isAutomatic: false, DateTime.UnixEpoch.AddSeconds(1));
        for (var i = 0; i < 35; i++) store.Save($"auto {i}", new List<Category>(), isAutomatic: true, DateTime.UnixEpoch.AddSeconds(10 + i));
        var list = store.List();
        Assert.Equal(Enumerable.Range(5, 30).Reverse().Select(i => $"auto {i}"), list.Where(v => v.IsAutomatic).Select(v => v.Name));
        Assert.Contains(list, v => v.Id == manual.Id);
        Assert.Equal(31, Directory.GetFiles(store.Directory).Length);
    }

    [Fact]
    public void MenuVersionStore_save_list_load_delete()
    {
        var store = new MenuVersionStore(Path.Combine(dir, "Versions"));
        var v = store.Save("Vor LES-Import", SampleConfig().Categories, isAutomatic: true);
        Assert.Equal(("Vor LES-Import", 2, 3, true), (v.Name, v.EntryCount, v.CategoryCount, v.IsAutomatic));
        Assert.Equal(new[] { v.Id }, store.List().Select(x => x.Id));
        Assert.Equal(new[] { "Utility", "Serum" }, store.Load(v.Id).Categories.SelectMany(c => c.Entries).Select(e => e.Name));
        store.Delete(v.Id);
        Assert.Empty(store.List());
        Assert.Throws<FileNotFoundException>(() => store.Delete(v.Id));
    }

    [Fact]
    public void MenuDocument_round_trip_and_rejects_other_files()
    {
        var path = Path.Combine(dir, "Mein Menü.hmlmenu");
        new MenuDocument("Mein Menü", SampleConfig().Categories).Write(path);
        var doc = MenuDocument.Read(path);
        Assert.Equal("Mein Menü", doc.Name);
        Assert.Equal(new[] { "Utility", "Serum" }, doc.Categories.SelectMany(c => c.Entries).Select(e => e.Name));

        var other = Path.Combine(dir, "x.hmlmenu");
        File.WriteAllText(other, "{\"hello\": 1}");
        Assert.ThrowsAny<Exception>(() => MenuDocument.Read(other));
    }

    [Fact]
    public void MenuDocument_and_RestoreMenu_copy_the_categories()
    {
        var c = SampleConfig();
        var doc = new MenuDocument("Copy", c.Categories);
        c.Categories[0].Entries[0].Name = "Changed";
        Assert.Equal("Utility", doc.Categories[0].Entries[0].Name);

        var restored = new List<Category> { new("Only") };
        c.RestoreMenu(restored);
        c.Categories[1].Name = "Renamed";
        Assert.Equal("Only", restored[0].Name);
        Assert.Equal(new[] { "Favorites", "Renamed" }, c.Categories.Select(x => x.Name));
    }

    [Fact]
    public void UsageExport_rejects_non_usage_file()
    {
        Assert.Equal(9, UsageExport.Read(Encoding.UTF8.GetBytes("{\"plugins|serum 2\":9}"))["plugins|serum 2"]);
        Assert.Throws<UsageExport.NotUsageFile>(() => UsageExport.Read(Encoding.UTF8.GetBytes("{\"name\":\"x\"}")));
        Assert.Throws<UsageExport.NotUsageFile>(() => UsageExport.Read(Encoding.UTF8.GetBytes("nope")));
        Assert.Throws<UsageExport.NotUsageFile>(() => UsageExport.Read(new byte[] { 0x7B, 0x22, 0xFF, 0x7C, 0x22, 0x3A, 0x31, 0x7D }));
    }

    [Fact]
    public void UsageStore_survives_corrupt_file()
    {
        var path = Path.Combine(dir, "usage.json");
        File.WriteAllText(path, "{\"plugins|a\": [1,");
        var store = new UsageStore(path);
        Assert.Empty(store.Counts);
        store.Record("plugins|a");
        Assert.Equal(1, new UsageStore(path).Counts["plugins|a"]);
        Assert.DoesNotContain(Directory.GetFiles(dir), f => f.EndsWith(".tmp", StringComparison.Ordinal));
    }

    [Fact]
    public void UsageStore_replace_merge_reset_and_export_round_trip()
    {
        var path = Path.Combine(dir, "sub", "usage.json");
        var store = new UsageStore(path);
        store.Record("plugins|a");
        store.Merge(new Dictionary<string, int> { ["plugins|a"] = 2, ["plugins|b"] = 1, ["plugins|zero"] = 0 });
        var expected = new Dictionary<string, int> { ["plugins|a"] = 3, ["plugins|b"] = 1 };
        Assert.Equal(expected, store.Counts);
        Assert.Equal(expected, new UsageStore(path).Counts);
        Assert.Equal(expected, UsageExport.Read(new UsageExport(store.Counts).Data()));
        store.Counts["plugins|a"] = 99;   // a copy
        Assert.Equal(3, store.Counts["plugins|a"]);
        store.Reset();
        Assert.Empty(new UsageStore(path).Counts);
    }

    [Fact]
    public void Les_parse_line_ending_and_bom_variants_record_the_same_expected()
    {
        var root = JsonNode.Parse(File.ReadAllText(Path.Combine(Fixtures.FixturesDir(), "les-parse.json")))!;
        var samples = root["cases"]!.AsArray().Where(c => c!["name"]!.GetValue<string>().StartsWith("sample menuconfig.ini", StringComparison.Ordinal))
            .Select(c => c!["expected"]).ToList();
        Assert.Equal(4, samples.Count);
        Assert.All(samples, e => Assert.True(JsonNode.DeepEquals(samples[0], e)));
    }

    [Fact]
    public void LES_file_with_BOM_and_CRLF_parses_like_LF()
    {
        var lf = "/Effects\nUtility\nUtility\n";
        var path = Path.Combine(dir, "menuconfig.ini");
        File.WriteAllBytes(path, new byte[] { 0xEF, 0xBB, 0xBF }.Concat(Encoding.UTF8.GetBytes("/Effects\r\nUtility\r\nUtility\r\n")).ToArray());
        Assert.Equal(LESMenuParser.Parse(lf), LESMenuParser.ParseFile(path));
    }

    [Fact]
    public void Atomic_save_failure_leaves_no_temp_file()
    {
        var target = Path.Combine(dir, "config.json");
        Directory.CreateDirectory(target);   // a folder where the file should go: the move fails
        Assert.ThrowsAny<IOException>(() => new ConfigStore(target).Save(LauncherConfig.MakeDefault()));
        Assert.ThrowsAny<Exception>(() => new MenuDocument("x", new List<Category>()).Write(target));
        Assert.Empty(Directory.GetFiles(dir));
    }

    [Fact]
    public async Task PluginCatalog_refresh_writes_cache_and_load_cache_restores()
    {
        var cache = Path.Combine(dir, "catalog-cache.json");
        var items = new List<PluginItem> { new("u:eq", "EQ Eight", ItemSource.AudioEffects, Array.Empty<string>()) };
        var catalog = new PluginCatalog(cache, _ => Task.FromResult(items));
        var changes = 0;
        catalog.ItemsChanged += (_, _) => changes++;
        await catalog.Refresh();
        await catalog.Refresh();   // unchanged: no event
        Assert.Equal(new[] { "EQ Eight" }, catalog.Items.Select(i => i.Name));
        Assert.Equal(1, changes);
        Assert.Equal("[{\"uri\":\"u:eq\",\"name\":\"EQ Eight\",\"source\":\"audio_effects\",\"path\":[]}]", File.ReadAllText(cache));

        var restored = new PluginCatalog(cache, _ => throw new IOException("offline"));
        restored.LoadCache();
        Assert.Equal(catalog.Items, restored.Items);
        await Assert.ThrowsAsync<IOException>(() => restored.Refresh());
        Assert.Equal(catalog.Items, restored.Items);
    }

    [Fact]
    public void SeenStore_writes_distant_past_on_first_run()
    {
        var path = Path.Combine(dir, "seen.json");
        new SeenStore(path).Update(new[] { Item("Alpha") }, DateTime.UnixEpoch);
        Assert.Equal("{\"u:Alpha\":\"0001-01-01T00:00:00Z\"}", File.ReadAllText(path));
        var seen = new SeenStore(path);
        Assert.Equal(SeenStore.DistantPast, seen.Date("u:Alpha"));
    }
}
