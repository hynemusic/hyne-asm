using System;
using System.IO;
using System.Text.Json;

namespace HyneAsm.App;

/// <summary>Settings only the Windows app has (kept out of config.json, so the file stays the same as the Mac's):
/// %APPDATA%\HYNE ASM\windows.json.</summary>
sealed class WindowsSettings
{
    /// <summary>Where dropped preset files are copied. Empty = User Library\Presets\HYNE ASM.</summary>
    public string? PresetFolderSetting { get; set; }

    public string PresetFolder => string.IsNullOrWhiteSpace(PresetFolderSetting) ? DefaultPresetFolder : PresetFolderSetting!;

    public static string DefaultPresetFolder => Path.Combine(ScriptInstaller.UserLibrary, "Presets", "HYNE ASM");

    static string FilePath => Path.Combine(Path.GetDirectoryName(HyneAsm.Core.ConfigStore.DefaultPath)!, "windows.json");

    static WindowsSettings? current;
    public static WindowsSettings Current => current ??= Load();

    static WindowsSettings Load()
    {
        try { return JsonSerializer.Deserialize<WindowsSettings>(File.ReadAllText(FilePath)) ?? new(); }
        catch (Exception) { return new(); }
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
