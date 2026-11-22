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
}
