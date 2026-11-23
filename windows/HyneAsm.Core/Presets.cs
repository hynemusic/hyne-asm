namespace HyneAsm.Core;

/// <summary>The user's own preset files (racks, device presets, plugin presets) as listed by the bridge.</summary>
public static class PresetFormat
{
    /// <summary>Extensions Live can load from the browser, without the dot.</summary>
    public static readonly IReadOnlySet<string> Extensions =
        new HashSet<string>(StringComparer.Ordinal) { "adg", "adv", "vstpreset", "aupreset", "fxp", "fxb", "amxd" };

    public const string GroupPrefix = "Presets · ";

    public static bool IsPresetFile(string path) => Extensions.Contains(Text.Lower(SwiftPath.Extension(path)));

    /// <summary>Short badge shown next to the preset in the settings browser.</summary>
    public static string Label(PluginItem item) => item.Format == null ? "Preset" : Text.Normalize(item.Format) switch
    {
        "adg" => "Rack",
        "adv" => "Preset",
        "vstpreset" => "VST3",
        "aupreset" => "AU",
        "fxp" or "fxb" => "VST2",
        "amxd" => "M4L",
        _ => "Preset",
    };

    /// <summary>Settings browser group: "Presets · &lt;folder&gt;". User Library presets drop Live's own "Presets" level,
    /// so "Presets/Audio Effects/…" becomes "Presets · Audio Effects". Places folders use their own name.</summary>
    public static string GroupTitle(PluginItem item)
    {
        IEnumerable<string> path = item.Path;
        if (item.Source == ItemSource.UserLibrary && item.Path.Count > 0 && Text.Equal(item.Path[0], "Presets")) path = path.Skip(1);
        var first = path.FirstOrDefault();
        return first != null ? GroupPrefix + first : GroupPrefix + "User Library";
    }

    /// <summary>Icon when the name gives no hint: drum racks get drums, instrument racks a synth, other racks the rack icon.</summary>
    internal static string FallbackIcon(PluginItem item)
    {
        var path = Text.Normalize(string.Join("/", item.Path));
        if (Text.Contains(path, "drum")) return "drums";
        if (Text.Contains(path, "instrument")) return "synth";
        if (Text.Contains(path, "midi")) return "midi";
        return item.Format != null && Text.Normalize(item.Format) == "adg" ? "rack" : IconCatalog.DefaultID;
    }
}

/// <summary>Dropping preset files from Explorer into the settings: find them in Live's list, or copy them into the User Library.</summary>
public static class PresetImport
{
    /// <summary>Live's default User Library: Documents\Ableton\User Library on Windows (to confirm in Plan 2),
    /// ~/Music/Ableton/User Library elsewhere.</summary>
    public static string UserLibraryPath => OperatingSystem.IsWindows()
        ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Ableton", "User Library")
        : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Music", "Ableton", "User Library");

    /// <summary>Where copied presets go, so they stay together and are easy to find in Live's browser.</summary>
    public static readonly IReadOnlyList<string> ImportFolder = new[] { "Presets", "HYNE ASM" };

    /// <summary>The listed preset for this file: same name and type, and its browser path matches the file's folders.
    /// When several match (same name in different folders), the one with the longest matching path wins.
    /// User Library presets must sit at exactly their browser path inside the library; Places presets
    /// (whose path starts with the place's name) must end in their browser path.</summary>
    public static PluginItem? Match(string file, IEnumerable<PluginItem> items, string? library = null)
    {
        library ??= UserLibraryPath;
        var stem = SwiftPath.DeletingExtension(SwiftPath.FileName(file));
        var ext = Text.Lower(SwiftPath.Extension(file));
        var components = SwiftPath.Components(file);
        var folders = components.Take(components.Count - 1).ToList();
        var root = SwiftPath.Components(library);
        var inLibrary = IsInside(file, library) ? folders.Skip(root.Count).ToList() : null;
        return items
            .Where(i => i.Format != null && Text.Equal(Text.Lower(i.Format), ext) && Text.Equal(i.Name, stem))
            .Where(i => i.Source switch
            {
                ItemSource.UserLibrary => inLibrary != null && Text.Equal(inLibrary, i.Path),
                ItemSource.UserFolders => i.Path.Count > 0 && i.Path.Count <= folders.Count && Text.Equal(folders.Skip(folders.Count - i.Path.Count).ToList(), i.Path),
                _ => false,
            })
            .MaxBy(i => i.Path.Count);
    }

    public static bool IsInside(string file, string folder)
    {
        var (f, root) = (SwiftPath.Components(file), SwiftPath.Components(folder));
        return f.Count > root.Count && Text.Equal(f.Take(root.Count).ToList(), root);
    }

    /// <summary>A free file name in the import folder ("Bus.adg", then "Bus 2.adg" …).</summary>
    public static string CopyDestination(string file, string? library = null)
    {
        var folder = ImportFolder.Aggregate(library ?? UserLibraryPath, Path.Combine);
        var name = SwiftPath.FileName(file);
        var (stem, ext) = (SwiftPath.DeletingExtension(name), SwiftPath.Extension(name));
        var candidate = Path.Combine(folder, name);
        for (var n = 2; File.Exists(candidate) || Directory.Exists(candidate); n++)
            candidate = Path.Combine(folder, $"{stem} {n}" + (ext.Length > 0 ? "." + ext : ""));
        return candidate;
    }
}

/// <summary>Swift <c>URL</c> path rules on file-system paths (either separator).</summary>
internal static class SwiftPath
{
    /// <summary><c>lastPathComponent</c>.</summary>
    public static string FileName(string path) => Path.GetFileName(Path.TrimEndingDirectorySeparator(path));

    /// <summary><c>pathExtension</c>: after the last dot, none for ".adg" or "Bus.".</summary>
    public static string Extension(string path)
    {
        var name = FileName(path);
        var dot = name.LastIndexOf('.');
        return dot <= 0 || dot == name.Length - 1 ? "" : name[(dot + 1)..];
    }

    /// <summary><c>deletingPathExtension().lastPathComponent</c> of a file name.</summary>
    public static string DeletingExtension(string name)
    {
        var ext = Extension(name);
        return ext.Length == 0 ? name : name[..^(ext.Length + 1)];
    }

    /// <summary><c>standardizedFileURL.pathComponents</c>: the root ("/" or "C:\"), then the folders and name, with "." and ".."
    /// resolved.</summary>
    public static List<string> Components(string path)
    {
        var full = Path.GetFullPath(path);
        var root = Path.GetPathRoot(full) ?? "";
        var parts = new List<string> { root };
        parts.AddRange(full[root.Length..].Split(new[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar },
            StringSplitOptions.RemoveEmptyEntries));
        return parts;
    }
}
