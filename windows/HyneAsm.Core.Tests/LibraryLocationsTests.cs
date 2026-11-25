namespace HyneAsm.Core.Tests;

/// <summary>Same cases as Tests/HMLauncherCoreTests/LibraryLocationsTests.swift.</summary>
public class LibraryLocationsTests
{
    const string Config = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton>
        	<ContentLibrary>
        		<UserLibrary>
        			<LibraryProject Id="0">
        				<ProjectLocation />
        				<ProjectName Value="User Library" />
        				<ProjectPath Value="D:\Audio\Ableton" />
        			</LibraryProject>
        		</UserLibrary>
        		<UserFolderInfoList>
        			<UserFolderInfo Id="1" Path="D:\Audio\Racks" DisplayName="My Racks" IconName="" />
        			<UserFolderInfo Id="2" Path="/Users/me/Presets &amp; More" DisplayName="" IconName="" />
        		</UserFolderInfoList>
        	</ContentLibrary>
        </Ableton>
        """;

    [Fact]
    public void Reads_user_library_and_places()
    {
        var locations = LibraryLocations.Parse(Config);
        Assert.Equal(3, locations.Count);
        Assert.Equal(LibraryLocationKind.UserLibrary, locations[0].Kind);
        Assert.Equal(Path.Combine(@"D:\Audio\Ableton", "User Library"), locations[0].Path);
        Assert.Equal(new LibraryLocation(LibraryLocationKind.Place, "My Racks", @"D:\Audio\Racks"), locations[1]);
        Assert.Equal(new LibraryLocation(LibraryLocationKind.Place, "Presets & More", "/Users/me/Presets & More"), locations[2]);
    }

    [Fact]
    public void Falls_back_to_default_user_library()
    {
        var expected = new[] { new LibraryLocation(LibraryLocationKind.UserLibrary, "User Library", PresetImport.UserLibraryPath) };
        Assert.Equal(expected, LibraryLocations.Parse("<Ableton/>"));
        Assert.Equal(expected, LibraryLocations.Parse("not xml"));
    }

    [Fact]
    public void Picks_running_version_then_newest_config()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        try
        {
            foreach (var (folder, age) in new[] { ("Live 12.3", 100), ("Live 12.4.7", 50), ("Live 12.4.8", 10) })
            {
                var dir = Path.Combine(root, folder, "Preferences");
                Directory.CreateDirectory(dir);
                var file = Path.Combine(dir, "Library.cfg");
                File.WriteAllText(file, "");
                File.SetLastWriteTimeUtc(file, DateTime.UtcNow.AddSeconds(-age));
            }
            string? Folder(string? version) => LibraryLocations.LibraryConfig(version, root, "Preferences") is { } p
                ? Path.GetFileName(Path.GetDirectoryName(Path.GetDirectoryName(p))) : null;
            Assert.Equal("Live 12.4.7", Folder("12.4.7"));
            Assert.Equal("Live 12.4.8", Folder("13.0"));
            Assert.Equal("Live 12.4.8", Folder(null));
            Assert.Null(LibraryLocations.LibraryConfig(null, Path.Combine(root, "missing"), "Preferences"));
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public void Lists_vst3_and_vst2_folders()
    {
        var paths = LibraryLocations.PluginFolders("PF", "CF", "LA").Select(l => l.Path).ToList();
        Assert.Contains(Path.Combine("CF", "VST3"), paths);
        Assert.Contains(Path.Combine("LA", "Programs", "Common", "VST3"), paths);
        Assert.Contains(Path.Combine("PF", "VSTPlugins"), paths);
    }
}
