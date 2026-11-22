using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;

namespace HyneAsm.App;

/// <summary>Writes the Live script ASMbridge (embedded in the exe) into Live's User Library.</summary>
static class ScriptInstaller
{
    /// <summary>The User Library Live uses: the one in the newest Live's Library.cfg, else the default
    /// Documents\Ableton\User Library.</summary>
    public static string UserLibrary
    {
        get
        {
            try
            {
                var prefs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Ableton");
                var cfg = Directory.Exists(prefs)
                    ? Directory.GetDirectories(prefs, "Live *")
                        .OrderByDescending(d => File.GetLastWriteTimeUtc(d))
                        .Select(d => Path.Combine(d, "Preferences", "Library.cfg"))
                        .FirstOrDefault(File.Exists)
                    : null;
                // <UserLibrary><LibraryProject><ProjectName Value="User Library"/><ProjectPath Value="…\Ableton"/>:
                // ProjectPath is the folder that *contains* the User Library, ProjectName its folder name.
                if (cfg != null && Regex.Match(File.ReadAllText(cfg), @"<UserLibrary>(.*?)</UserLibrary>", RegexOptions.Singleline) is { Success: true } block)
                {
                    var name = Regex.Match(block.Groups[1].Value, @"<ProjectName\s+Value=""([^""]*)""");
                    var parent = Regex.Match(block.Groups[1].Value, @"<ProjectPath\s+Value=""([^""]+)""");
                    if (parent.Success)
                    {
                        var library = Path.Combine(parent.Groups[1].Value, name.Success && name.Groups[1].Value.Length > 0 ? name.Groups[1].Value : "User Library");
                        if (Directory.Exists(library)) return library;
                    }
                }
            }
            catch (Exception) { /* fall back to the default */ }
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Ableton", "User Library");
        }
    }

    public static string ScriptsFolder => Path.Combine(UserLibrary, "Remote Scripts");
    public static string Target => Path.Combine(ScriptsFolder, "ASMbridge");

    public static bool IsInstalled => File.Exists(Path.Combine(Target, "__init__.py"));

    /// <summary>Replaces an older copy; removes the bridge's pre-rename copy so Live lists only one.</summary>
    public static void Install()
    {
        var assembly = Assembly.GetExecutingAssembly();
        var files = assembly.GetManifestResourceNames().Where(n => n.StartsWith("ASMbridge/")).ToList();
        if (files.Count == 0) throw new FileNotFoundException("ASMbridge is missing from the app");
        if (Directory.Exists(Target)) Directory.Delete(Target, recursive: true);
        Directory.CreateDirectory(Target);
        foreach (var name in files)
        {
            using var source = assembly.GetManifestResourceStream(name)!;
            using var target = File.Create(Path.Combine(Target, name["ASMbridge/".Length..]));
            source.CopyTo(target);
        }
        var legacy = Path.Combine(ScriptsFolder, "HMLauncherBridge");
        try { if (Directory.Exists(legacy)) Directory.Delete(legacy, recursive: true); } catch (Exception) { }
        // The first Windows test build put the script one folder too high (…\Ableton\Remote Scripts); remove that copy.
        var misplaced = Path.Combine(Path.GetDirectoryName(UserLibrary)!, "Remote Scripts", "ASMbridge");
        try
        {
            if (!string.Equals(misplaced, Target, StringComparison.OrdinalIgnoreCase) && Directory.Exists(misplaced))
                Directory.Delete(misplaced, recursive: true);
        }
        catch (Exception) { }
    }
}
