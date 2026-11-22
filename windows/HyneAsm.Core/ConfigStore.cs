using System.Text;
using System.Text.Json;
using HyneAsm.Core.Json;

namespace HyneAsm.Core;

public sealed class ConfigStore
{
    public string Path { get; }

    public ConfigStore(string path) { Path = path; }

    public const string FolderName = "HYNE ASM";
    internal const string LegacyFolderName = "HM Launcher";

    /// <summary>%APPDATA%\HYNE ASM\config.json on Windows; elsewhere the Mac location
    /// (~/Library/Application Support/HYNE ASM/config.json), so tests on the Mac mirror Swift.</summary>
    public static string DefaultPath
    {
        get
        {
            MoveLegacyFolder(SupportDirectory);
            return System.IO.Path.Combine(SupportDirectory, FolderName, "config.json");
        }
    }

    /// <summary>Swift's <c>.applicationSupportDirectory</c>; %APPDATA% on Windows.</summary>
    internal static string SupportDirectory => OperatingSystem.IsWindows()
        ? Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)
        : System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Library", "Application Support");

    /// <summary>The app used to be called "HM Launcher": carry its folder (config, versions, usage) over once.</summary>
    internal static void MoveLegacyFolder(string support)
    {
        var old = System.IO.Path.Combine(support, LegacyFolderName);
        var @new = System.IO.Path.Combine(support, FolderName);
        if (!Directory.Exists(old) || Directory.Exists(@new) || File.Exists(@new)) return;
        try { Directory.Move(old, @new); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    /// <summary>Missing file → default. Unreadable file → backed up as config.corrupt-&lt;timestamp&gt;.json, then default.</summary>
    public LauncherConfig Load()
    {
        byte[] data;
        try { data = File.ReadAllBytes(Path); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return LauncherConfig.MakeDefault(); }

        // Like Swift's `try?`: any failure to decode means a damaged file (backup + default), never a crash.
        LauncherConfig? config = null;
        try { config = SwiftJson.Deserialize<LauncherConfig>(Encoding.UTF8.GetString(data)); }
        catch (Exception e) when (e is not OutOfMemoryException) { }
        if (config != null && config.Categories.Any(c => c.IsFavorites))
        {
            Migrate(config);
            return config;
        }
        var stamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var backup = System.IO.Path.Combine(System.IO.Path.GetDirectoryName(Path)!, $"config.corrupt-{stamp}.json");
        try { File.Move(Path, backup); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        return LauncherConfig.MakeDefault();
    }

    /// <summary>v1 → v2: "close all plugin windows" moved from ⌘⌥W to ⌘⌃W; v2 → v3 → v4: icons re-guessed.</summary>
    internal static void Migrate(LauncherConfig config)
    {
        if (config.Version < 2)
        {
            var old = new KeyCombo(13, ModifierSet.Cmd | ModifierSet.Alt);
            var @new = new KeyCombo(13, ModifierSet.Cmd | ModifierSet.Ctrl);
            config.Shortcuts.CloseAll = config.Shortcuts.CloseAll.Select(c => c == old ? @new : c).ToList();
        }
        if (config.Version < 3)
        {
            // v2 → v3: entries still on the plain default icon get a guessed one.
            foreach (var e in config.Categories.SelectMany(c => c.Entries).Where(e => e.IconID == IconCatalog.DefaultID))
                e.IconID = IconGuesser.Guess(new PluginItem(e.Uri, e.Name, e.Source, e.Path));
        }
        if (config.Version < 4)
        {
            // v3 → v4: new icon kinds (amp, mic, repair, mastering …) for entries still on the generic icon,
            // in folders and in every stored profile too.
            RegessGeneric(config.Categories);
            foreach (var p in config.Profiles) RegessGeneric(p.Categories);
        }
        config.Version = LauncherConfig.CurrentVersion;
    }

    static void RegessGeneric(List<Category> categories)
    {
        void Fix(Entry e)
        {
            if (e.IsFolder) e.Children!.ForEach(Fix);
            else if (e.IconID == IconCatalog.DefaultID && e.Chain == null && e.Action == null)
                e.IconID = IconGuesser.Guess(new PluginItem(e.Uri, e.Name, e.Source, e.Path));
        }
        foreach (var c in categories) c.Entries.ForEach(Fix);
    }

    public void Save(LauncherConfig config)
    {
        var dir = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(Path))!;
        Directory.CreateDirectory(dir);
        AtomicFile.Write(Path, SwiftJson.EncodeUtf8(SwiftJson.Serialize(config, pretty: true)));
    }
}

/// <summary>Swift's <c>write(to:options: .atomic)</c>: a temporary file in the same folder, then moved over the target.
/// On failure the temporary file is removed and the error passed on. The folder must exist (as in Swift).</summary>
internal static class AtomicFile
{
    public static void Write(string path, byte[] bytes)
    {
        var full = System.IO.Path.GetFullPath(path);
        var temp = System.IO.Path.Combine(System.IO.Path.GetDirectoryName(full)!, $".{System.IO.Path.GetFileName(full)}.{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllBytes(temp, bytes);
            File.Move(temp, full, overwrite: true);
        }
        catch
        {
            try { File.Delete(temp); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            throw;
        }
    }

    public static void WriteText(string path, string text) => Write(path, SwiftJson.EncodeUtf8(text));
}
