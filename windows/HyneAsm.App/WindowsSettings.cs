using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace HyneAsm.App;

/// <summary>Settings only the Windows app has (kept out of config.json, so the file stays the same as the Mac's):
/// %APPDATA%\HYNE ASM\windows.json.</summary>
sealed class WindowsSettings
{
    /// <summary>Folders dropped presets can be copied to. Empty = just User Library\Presets\HYNE ASM.</summary>
    public List<string> PresetFolders { get; set; } = new();
    /// <summary>The one used without asking (index into <see cref="Folders"/>).</summary>
    public int DefaultPresetFolder { get; set; }
    /// <summary>Older single-folder setting, read once and moved into <see cref="PresetFolders"/>.</summary>
    public string? PresetFolderSetting { get; set; }

    public static string BuiltInPresetFolder => Path.Combine(ScriptInstaller.UserLibrary, "Presets", "HYNE ASM");

    /// <summary>All preset folders, the built-in one when none was added.</summary>
    public IReadOnlyList<string> Folders => PresetFolders.Count > 0 ? PresetFolders : new[] { BuiltInPresetFolder };

    public string PresetFolder => Folders[Math.Clamp(DefaultPresetFolder, 0, Folders.Count - 1)];

    public void AddFolder(string path)
    {
        if (PresetFolders.Count == 0) PresetFolders.Add(BuiltInPresetFolder);
        if (!PresetFolders.Any(f => string.Equals(Path.GetFullPath(f), Path.GetFullPath(path), StringComparison.OrdinalIgnoreCase))) PresetFolders.Add(path);
        Save();
    }

    public void RemoveFolder(int index)
    {
        if (PresetFolders.Count == 0 || index < 0 || index >= PresetFolders.Count) return;
        PresetFolders.RemoveAt(index);
        if (DefaultPresetFolder >= index) DefaultPresetFolder = Math.Max(0, DefaultPresetFolder - 1);
        Save();
    }

    public void MakeDefault(int index) { DefaultPresetFolder = index; Save(); }

    static string FilePath => Path.Combine(Path.GetDirectoryName(HyneAsm.Core.ConfigStore.DefaultPath)!, "windows.json");

    static WindowsSettings? current;
    public static WindowsSettings Current => current ??= Load();

    static WindowsSettings Load()
    {
        WindowsSettings s;
        try { s = JsonSerializer.Deserialize<WindowsSettings>(File.ReadAllText(FilePath)) ?? new(); }
        catch (Exception) { s = new(); }
        if (!string.IsNullOrWhiteSpace(s.PresetFolderSetting))
        {
            s.PresetFolders = new() { BuiltInPresetFolder, s.PresetFolderSetting! };
            s.DefaultPresetFolder = 1;
            s.PresetFolderSetting = null;
            s.Save();
        }
        return s;
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception) { /* a setting that isn't kept is not worth an error */ }
    }
}
