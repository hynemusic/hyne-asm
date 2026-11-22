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

        LauncherConfig? config = null;
        try { config = SwiftJson.Deserialize<LauncherConfig>(Encoding.UTF8.GetString(data)); }
        catch (JsonException) { }
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

    /// <summary>v1 → v2: "close all plugin windows" moved from ⌘⌥W to ⌘⌃W.</summary>
    internal static void Migrate(LauncherConfig config)
    {
        if (config.Version < 2)
        {
            var old = new KeyCombo(13, ModifierSet.Cmd | ModifierSet.Alt);
            var @new = new KeyCombo(13, ModifierSet.Cmd | ModifierSet.Ctrl);
            config.Shortcuts.CloseAll = config.Shortcuts.CloseAll.Select(c => c == old ? @new : c).ToList();
        }
        // v2 → v3 and v3 → v4 re-guess the icons of entries still on the generic icon (IconGuesser): ported with
        // IconGuesser in Task 4.
        config.Version = LauncherConfig.CurrentVersion;
    }

    public void Save(LauncherConfig config)
    {
        var dir = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(Path))!;
        Directory.CreateDirectory(dir);
        var bytes = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false).GetBytes(SwiftJson.Serialize(config, pretty: true));
        var temp = System.IO.Path.Combine(dir, $".{System.IO.Path.GetFileName(Path)}.{Guid.NewGuid():N}.tmp");
        File.WriteAllBytes(temp, bytes);
        File.Move(temp, Path, overwrite: true);
    }
}
