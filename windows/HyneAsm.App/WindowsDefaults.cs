using System;
using System.Collections.Generic;
using System.Diagnostics;
using HyneAsm.Core;
using Microsoft.Win32;

namespace HyneAsm.App;

/// <summary>Windows-only settings: default shortcuts that don't clash with Windows, the hyneasm:// link, autostart.</summary>
static class WindowsDefaults
{
    // Stored in the Mac format (Cmd = Ctrl on Windows): Ctrl+W closes the focused plugin window,
    // Ctrl+Shift+W closes all, Ctrl+Space opens the quick search.
    public static ShortcutSettings Shortcuts => new(
        new KeyCombo(13, ModifierSet.Cmd),
        new List<KeyCombo> { new(13, ModifierSet.Cmd | ModifierSet.Shift) },
        new List<KeyCombo> { new(49, ModifierSet.Cmd) });

    /// <summary>The Mac defaults would be Win+Space (input switch) and Ctrl+Esc (Start menu) here: a new config, or one
    /// still on the Mac defaults, gets the Windows ones.</summary>
    public static void Apply(LauncherConfig config, bool existed)
    {
        if (!existed || Equals(config.Shortcuts, ShortcutSettings.Default)) config.Shortcuts = Shortcuts;
    }

    static string ExePath => Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule!.FileName;

    /// <summary>hyneasm://… opens this app (Stream Deck "Open", scripts). Per user, no admin needed.</summary>
    public static void RegisterLinkScheme()
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(@"Software\Classes\" + RemoteCommand.Scheme);
            key.SetValue("", "URL:HYNE ASM");
            key.SetValue("URL Protocol", "");
            using var command = key.CreateSubKey(@"shell\open\command");
            command.SetValue("", $"\"{ExePath}\" \"%1\"");
        }
        catch (Exception) { /* links just won't open the app */ }
    }

    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run", RunName = "HYNE ASM";

    public static bool StartsWithWindows
    {
        get { using var key = Registry.CurrentUser.OpenSubKey(RunKey); return key?.GetValue(RunName) != null; }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value) key.SetValue(RunName, $"\"{ExePath}\" --background");
            else key.DeleteValue(RunName, throwOnMissingValue: false);
        }
    }
}
