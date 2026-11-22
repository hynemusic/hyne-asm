using HyneAsm.Core.Json;

namespace HyneAsm.Core.Tests;

/// <summary>Mirrors Tests/HMLauncherCoreTests/ConfigStoreTests.swift.</summary>
public class ConfigStoreTests : IDisposable
{
    readonly string dir = Path.Combine(Path.GetTempPath(), "hyneasm-tests-" + Guid.NewGuid().ToString("N"));

    public ConfigStoreTests() => Directory.CreateDirectory(dir);

    public void Dispose()
    {
        try { Directory.Delete(dir, recursive: true); } catch (IOException) { }
    }

    string ConfigPath => Path.Combine(dir, "config.json");

    string[] Backups() => Directory.GetFiles(dir).Select(Path.GetFileName)
        .Where(n => n!.StartsWith("config.corrupt-", StringComparison.Ordinal) && n.EndsWith(".json", StringComparison.Ordinal))
        .Select(n => n!).ToArray();

    static Entry Item(string name) => new()
    {
        Id = Guid.NewGuid(), Uri = "query:Plugins#" + name, Name = name, Source = ItemSource.Plugins,
        Path = new() { "VST3" }, IconID = "limiter",
    };

    [Fact]
    public void Save_then_Load_is_identity()
    {
        var c = LauncherConfig.MakeDefault();
        c.Categories[0].Entries.Add(Item("Pro-L 2"));
        new ConfigStore(ConfigPath).Save(c);
        var loaded = new ConfigStore(ConfigPath).Load();
        Assert.Equal(c.Categories.Select(x => x.Id), loaded.Categories.Select(x => x.Id));
        Assert.Equal(c.Categories[0].Entries, loaded.Categories[0].Entries);
        Assert.Equal(SwiftJson.Serialize(c, pretty: true), SwiftJson.Serialize(loaded, pretty: true));
    }

    [Fact]
    public void Missing_file_returns_default_without_backup()
    {
        var loaded = new ConfigStore(ConfigPath).Load();
        Assert.Equal(new[] { "Favorites", "Instruments", "Effects" }, loaded.Categories.Select(c => c.Name));
        Assert.Empty(Directory.GetFiles(dir));
    }

    [Fact]
    public void Empty_file_is_backed_up_and_default_returned()
    {
        File.WriteAllText(ConfigPath, "");
        var loaded = new ConfigStore(ConfigPath).Load();
        Assert.Equal(3, loaded.Categories.Count);
        var backups = Backups();
        Assert.Single(backups);
        Assert.Equal("", File.ReadAllText(Path.Combine(dir, backups[0])));
        Assert.False(File.Exists(ConfigPath));
    }

    [Theory]
    [InlineData("{not json")]
    [InlineData("truncated")]
    [InlineData("{\"version\": 4, \"categories\": []}")]
    public void Truncated_json_is_backed_up_and_default_returned(string content)
    {
        if (content == "truncated")
        {
            var full = SwiftJson.Serialize(LauncherConfig.MakeDefault(), pretty: true);
            content = full[..(full.Length / 2)];
        }
        File.WriteAllText(ConfigPath, content);
        var loaded = new ConfigStore(ConfigPath).Load();
        Assert.Equal(3, loaded.Categories.Count);
        var backups = Backups();
        Assert.Single(backups);
        Assert.Equal(content, File.ReadAllText(Path.Combine(dir, backups[0])));
    }

    [Fact]
    public void Bom_prefixed_config_loads()
    {
        var c = LauncherConfig.MakeDefault();
        c.Categories[0].Entries.Add(Item("Pro-L 2"));
        var text = SwiftJson.Serialize(c, pretty: true);
        File.WriteAllBytes(ConfigPath, new byte[] { 0xEF, 0xBB, 0xBF }.Concat(System.Text.Encoding.UTF8.GetBytes(text)).ToArray());
        var loaded = new ConfigStore(ConfigPath).Load();
        Assert.Equal(c.Categories.Select(x => x.Id), loaded.Categories.Select(x => x.Id));
        Assert.Equal(c.Categories[0].Entries, loaded.Categories[0].Entries);
        Assert.Empty(Backups());
    }

    void AssertBackedUpAndDefault(string content)
    {
        File.WriteAllText(ConfigPath, content);
        var loaded = new ConfigStore(ConfigPath).Load();
        Assert.Equal(new[] { "Favorites", "Instruments", "Effects" }, loaded.Categories.Select(x => x.Name));
        var backups = Backups();
        Assert.Single(backups);
        Assert.Equal(content, File.ReadAllText(Path.Combine(dir, backups[0])));
    }

    const string FavoritesJson =
        "{\"id\": \"00000000-0000-0000-0000-000000000001\", \"name\": \"Favorites\", \"isFavorites\": true, \"entries\": [] }";

    [Theory]
    [InlineData("{\"version\": 4, \"categories\": [null]}")]
    [InlineData("{\"version\": 4, \"categories\": [" + FavoritesJson + ", null]}")]
    public void Null_category_element_is_backed_up_and_default_returned(string content) => AssertBackedUpAndDefault(content);

    [Fact]
    public void Null_entries_is_backed_up_and_default_returned() => AssertBackedUpAndDefault(
        "{\"version\": 4, \"categories\": [{\"id\": \"00000000-0000-0000-0000-000000000001\", \"name\": \"Favorites\", " +
        "\"isFavorites\": true, \"entries\": null}]}");

    [Theory]
    [InlineData("\"name\": null")]
    [InlineData("\"entries\": [null]")]
    [InlineData("\"shortcuts\": {\"closeAll\": [null]}")]
    [InlineData("\"panelKeys\": {\"bindings\": {\"up\": null}}")]
    [InlineData("\"colorRules\": {\"x\": null}")]
    [InlineData("\"profiles\": [null]")]
    [InlineData("\"searchRules\": [{\"id\": \"00000000-0000-0000-0000-000000000002\", \"query\": \"a\", \"pinned\": [null], \"hidden\": []}]")]
    public void Other_nulls_Swift_rejects_are_backed_up_and_default_returned(string member)
    {
        // `name`/`entries` replace the Favorites category's own; the rest are top-level members.
        var category = member.StartsWith("\"name\"") || member.StartsWith("\"entries\"")
            ? "{\"id\": \"00000000-0000-0000-0000-000000000001\", \"isFavorites\": true, " +
              (member.StartsWith("\"name\"") ? member + ", \"entries\": []}" : "\"name\": \"Favorites\", " + member + "}")
            : FavoritesJson;
        var top = category == FavoritesJson ? ", " + member : "";
        AssertBackedUpAndDefault("{\"version\": 4, \"categories\": [" + category + "]" + top + "}");
    }

    [Fact]
    public void Legacy_HM_Launcher_folder_is_migrated()
    {
        var old = Path.Combine(dir, "HM Launcher");
        Directory.CreateDirectory(old);
        File.WriteAllText(Path.Combine(old, "config.json"), "{}");
        ConfigStore.MoveLegacyFolder(dir);
        Assert.False(Directory.Exists(old));
        Assert.Equal("{}", File.ReadAllText(Path.Combine(dir, "HYNE ASM", "config.json")));

        // Once the new folder exists, a legacy folder is left alone.
        Directory.CreateDirectory(old);
        ConfigStore.MoveLegacyFolder(dir);
        Assert.True(Directory.Exists(old));
        Assert.True(File.Exists(Path.Combine(dir, "HYNE ASM", "config.json")));
    }

    [Fact]
    public void Version1_config_migrates_closeAll_to_cmd_ctrl_W()
    {
        var old = LauncherConfig.MakeDefault();
        old.Version = 1;
        old.Shortcuts.CloseAll = new() { new KeyCombo(13, ModifierSet.Cmd | ModifierSet.Alt), new KeyCombo(53, ModifierSet.Cmd) };
        new ConfigStore(ConfigPath).Save(old);
        var loaded = new ConfigStore(ConfigPath).Load();
        Assert.Equal(LauncherConfig.CurrentVersion, loaded.Version);
        Assert.Equal(new[] { new KeyCombo(13, ModifierSet.Cmd | ModifierSet.Ctrl), new KeyCombo(53, ModifierSet.Cmd) },
            loaded.Shortcuts.CloseAll);
    }

    [Fact]
    public void Version2_config_keeps_user_shortcuts()
    {
        var c = LauncherConfig.MakeDefault();
        c.Shortcuts.CloseAll = new() { new KeyCombo(13, ModifierSet.Cmd | ModifierSet.Alt) };
        new ConfigStore(ConfigPath).Save(c);
        Assert.Equal(new[] { new KeyCombo(13, ModifierSet.Cmd | ModifierSet.Alt) },
            new ConfigStore(ConfigPath).Load().Shortcuts.CloseAll);
    }

    [Fact]
    public void Save_creates_missing_directory()
    {
        var path = Path.Combine(dir, "sub", "config.json");
        new ConfigStore(path).Save(LauncherConfig.MakeDefault());
        Assert.True(File.Exists(path));
    }

    [Fact]
    public void Support_directory_is_AppData_on_Windows_and_the_Mac_folder_elsewhere()
    {
        // DefaultPath itself is not called: it would move a real "HM Launcher" folder on this machine.
        var expected = OperatingSystem.IsWindows()
            ? Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Library", "Application Support");
        Assert.Equal(expected, ConfigStore.SupportDirectory);
    }

    // A locked file (antivirus, OneDrive, an editor) is not a missing file: Load must not hand out a default that a
    // later Save would write over the user's real menu.
    [Fact]
    public void Load_of_a_locked_file_throws_and_leaves_it_alone()
    {
        var c = LauncherConfig.MakeDefault();
        c.Categories[0].Entries.Add(Item("Pro-L 2"));
        new ConfigStore(ConfigPath).Save(c);
        var before = File.ReadAllBytes(ConfigPath);
        using (new FileStream(ConfigPath, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            var e = Assert.Throws<ConfigUnreadableException>(() => new ConfigStore(ConfigPath).Load());
            Assert.IsAssignableFrom<IOException>(e);
            Assert.Contains("config.json", e.Message);
        }
        Assert.Equal(before, File.ReadAllBytes(ConfigPath));
        Assert.Empty(Backups());
    }

    [Fact]
    public void Load_where_a_folder_stands_in_for_the_file_throws()
    {
        Directory.CreateDirectory(ConfigPath);
        Assert.Throws<ConfigUnreadableException>(() => new ConfigStore(ConfigPath).Load());
        Assert.True(Directory.Exists(ConfigPath));
        Assert.Empty(Backups());
    }

    [Fact]
    public void Load_of_a_missing_file_or_folder_is_the_default()
    {
        Assert.Contains(new ConfigStore(ConfigPath).Load().Categories, x => x.IsFavorites);
        Assert.Contains(new ConfigStore(Path.Combine(dir, "nope", "config.json")).Load().Categories, x => x.IsFavorites);
    }
}
