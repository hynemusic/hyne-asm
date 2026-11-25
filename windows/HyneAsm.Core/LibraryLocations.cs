using System.Xml;
using System.Xml.Linq;

namespace HyneAsm.Core;

public enum LibraryLocationKind { PluginFolder, UserLibrary, Place }

/// <summary>A folder Live reads plugins or presets from. The app's list comes from Live's browser, so these
/// are shown for orientation only: they are changed in Live itself (Places, Settings → Plug-Ins).</summary>
public sealed record LibraryLocation(LibraryLocationKind Kind, string Name, string Path);

/// <summary>Same logic as Sources/HMLauncherCore/LibraryLocations.swift; Windows keeps Live's settings in
/// %APPDATA%\Ableton\Live x.y.z\Preferences, the Mac in ~/Library/Preferences/Ableton/Live x.y.z.</summary>
public static class LibraryLocations
{
    /// <summary>The usual Windows plugin folders: Live scans the VST3 ones itself, VST2 only through its custom folder.</summary>
    public static IReadOnlyList<LibraryLocation> PluginFolders(string? programFiles = null, string? commonFiles = null, string? localAppData = null)
    {
        programFiles ??= Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        commonFiles ??= Environment.GetFolderPath(Environment.SpecialFolder.CommonProgramFiles);
        localAppData ??= Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return new[]
        {
            new LibraryLocation(LibraryLocationKind.PluginFolder, "VST3", System.IO.Path.Combine(commonFiles, "VST3")),
            new LibraryLocation(LibraryLocationKind.PluginFolder, "VST3", System.IO.Path.Combine(localAppData, "Programs", "Common", "VST3")),
            new LibraryLocation(LibraryLocationKind.PluginFolder, "VST2", System.IO.Path.Combine(programFiles, "VSTPlugins")),
            new LibraryLocation(LibraryLocationKind.PluginFolder, "VST2", System.IO.Path.Combine(programFiles, "Steinberg", "VSTPlugins")),
            new LibraryLocation(LibraryLocationKind.PluginFolder, "VST2", System.IO.Path.Combine(commonFiles, "VST2")),
        };
    }

    /// <summary>Live's settings folder: %APPDATA%\Ableton on Windows, ~/Library/Preferences/Ableton elsewhere.</summary>
    public static string PreferencesRoot => OperatingSystem.IsWindows()
        ? System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Ableton")
        : System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Library", "Preferences", "Ableton");

    /// <summary>Where Library.cfg sits inside a "Live x.y.z" folder: "Preferences" on Windows, directly in it on the Mac.</summary>
    public static string ConfigSubfolder => OperatingSystem.IsWindows() ? "Preferences" : "";

    /// <summary>The Library.cfg of the running Live version ("12.4.7" → "Live 12.4.7"), else the most recently changed one.</summary>
    public static string? LibraryConfig(string? liveVersion, string? root = null, string? subfolder = null)
    {
        root ??= PreferencesRoot;
        subfolder ??= ConfigSubfolder;
        string ConfigIn(string folder) => System.IO.Path.Combine(folder, subfolder, "Library.cfg");
        if (liveVersion != null)
        {
            var exact = ConfigIn(System.IO.Path.Combine(root, "Live " + liveVersion));
            if (File.Exists(exact)) return exact;
        }
        if (!Directory.Exists(root)) return null;
        return Directory.GetDirectories(root)
            .Where(d => System.IO.Path.GetFileName(d).StartsWith("Live ", StringComparison.Ordinal))
            .Select(ConfigIn)
            .Where(File.Exists)
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .FirstOrDefault();
    }

    /// <summary>User Library and Places from a Library.cfg. Without a User Library entry, Live's default location is used.</summary>
    public static IReadOnlyList<LibraryLocation> Parse(string libraryConfig)
    {
        XDocument doc;
        try { doc = XDocument.Parse(libraryConfig); }
        catch (XmlException) { return new[] { DefaultUserLibrary() }; }
        var project = doc.Descendants("UserLibrary").Descendants("LibraryProject").FirstOrDefault();
        string? Value(string name) => project?.Element(name)?.Attribute("Value")?.Value is { Length: > 0 } v ? v : null;
        var parent = Value("ProjectPath");
        var library = parent == null ? DefaultUserLibrary()
            : new LibraryLocation(LibraryLocationKind.UserLibrary, "User Library", System.IO.Path.Combine(parent, Value("ProjectName") ?? "User Library"));
        var places = doc.Descendants("UserFolderInfo")
            .Select(e => (Path: e.Attribute("Path")?.Value, Display: e.Attribute("DisplayName")?.Value))
            .Where(p => !string.IsNullOrEmpty(p.Path))
            .Select(p => new LibraryLocation(LibraryLocationKind.Place,
                string.IsNullOrEmpty(p.Display) ? System.IO.Path.GetFileName(p.Path!.TrimEnd('/', '\\')) : p.Display, p.Path!));
        return new[] { library }.Concat(places).ToList();
    }

    /// <summary>Everything to show: plugin folders, then User Library and Places of the given Live version.</summary>
    public static IReadOnlyList<LibraryLocation> All(string? liveVersion)
    {
        IReadOnlyList<LibraryLocation> presets;
        try { presets = LibraryConfig(liveVersion) is { } cfg ? Parse(File.ReadAllText(cfg)) : new[] { DefaultUserLibrary() }; }
        catch (IOException) { presets = new[] { DefaultUserLibrary() }; }
        catch (UnauthorizedAccessException) { presets = new[] { DefaultUserLibrary() }; }
        return PluginFolders().Concat(presets).ToList();
    }

    static LibraryLocation DefaultUserLibrary() => new(LibraryLocationKind.UserLibrary, "User Library", PresetImport.UserLibraryPath);
}
