using System.Text.Json.Serialization;
using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>Opening plugin windows from the keyboard or with a click in a plugin's X-Y field.
/// Stored as an optional block in the config, so files without it keep their exact form.</summary>
public sealed record PluginWindowSettings : IJsonOnDeserialized
{
    /// <summary>Opens (or closes) every plugin window of the selected track; empty = off.</summary>
    public List<KeyCombo> OpenAll { get; set; } = new();
    /// <summary>A click in a plugin's X-Y field opens its window; Live never gets the click, so the X-Y dot stays put.</summary>
    public bool XyClick { get; set; } = true;

    /// <summary>A fresh copy of the defaults on every call.</summary>
    public static PluginWindowSettings Default => new();

    void IJsonOnDeserialized.OnDeserialized()
    {
        OpenAll ??= new();
        SwiftJson.RejectNullElements(nameof(PluginWindowSettings), OpenAll);
    }

    public bool Equals(PluginWindowSettings? o) => o is not null && ValueEquality.Lists(OpenAll, o.OpenAll) && XyClick == o.XyClick;

    public override int GetHashCode() => HashCode.Combine(ValueEquality.Hash(OpenAll), XyClick);
}

/// <summary>One "Show/Hide Plug-In Window" button (the wrench) in Live's device view, as Live 12's accessibility tree
/// shows it. <c>Identifier</c> looks like <c>TrackView.Device[0].Device[1].TitleBar.PluginEdit</c>.</summary>
public sealed record PluginWindowButton(string Identifier, bool IsOpen)
{
    /// <summary><c>TrackView.Device[0].Device[1]</c>.</summary>
    public string? DevicePath => PluginWindowPlanner.DevicePath(Identifier);
}

public static class PluginWindowPlanner
{
    public const string TrackViewID = "TrackView";
    public const string ButtonSuffix = ".TitleBar.PluginEdit";
    public const string XySuffix = ".PluginXyControl";

    /// <summary>The device an element belongs to: <c>TrackView.Device[0].Device[1].TitleBar.DeviceOn</c> →
    /// <c>TrackView.Device[0].Device[1]</c>. Null outside the device view.</summary>
    public static string? DevicePath(string? identifier)
    {
        if (identifier == null) return null;
        var parts = identifier.Split('.');
        if (parts[0] != TrackViewID) return null;
        var devices = parts.Skip(1).TakeWhile(p => p.StartsWith("Device[", StringComparison.Ordinal) && p.EndsWith(']')).ToList();
        if (devices.Count == 0) return null;
        return string.Join(".", devices.Prepend(TrackViewID));
    }

    /// <summary>The wrench of the plugin whose X-Y field (or a part of it) is <paramref name="identifier"/>; null for
    /// anything else. <c>TrackView.Device[3].PluginXyControl</c> → <c>TrackView.Device[3].TitleBar.PluginEdit</c>.</summary>
    public static string? XyButton(string? identifier)
    {
        if (identifier == null || DevicePath(identifier) is not { } device || !identifier.StartsWith(device + XySuffix, StringComparison.Ordinal))
            return null;
        var rest = identifier[(device.Length + XySuffix.Length)..];
        return rest.Length == 0 || rest[0] == '.' ? device + ButtonSuffix : null;
    }

    /// <summary>Opens the closed ones; when every one is already open, closes them (the shortcut toggles).</summary>
    public static List<PluginWindowButton> ToPress(IReadOnlyList<PluginWindowButton> buttons)
    {
        var closed = buttons.Where(b => !b.IsOpen).ToList();
        return closed.Count == 0 ? buttons.ToList() : closed;
    }
}

/// <summary>Live doesn't report which devices are selected, so the app follows the clicks: a click on a device selects
/// it, Shift-click selects the range from the last plain click (within one chain), a click anywhere else clears it.</summary>
public sealed class DeviceSelectionTracker
{
    public string? Anchor { get; private set; }
    public IReadOnlyList<string> Selection { get; private set; } = Array.Empty<string>();

    /// <summary><paramref name="identifier"/>: what was clicked (any element; null or outside the device view clears).</summary>
    public void Click(string? identifier, bool extend)
    {
        if (PluginWindowPlanner.DevicePath(identifier) is not { } device)
        {
            Anchor = null; Selection = Array.Empty<string>();
            return;
        }
        if (extend && Anchor != null && Range(Anchor, device) is { } range)
        {
            Selection = range;
            return;
        }
        Anchor = device;
        Selection = new[] { device };
    }

    /// <summary>The devices a click in <paramref name="device"/>'s X-Y field acts on: the whole selection when the
    /// device is part of it.</summary>
    public IReadOnlyList<string> DevicesForClickOn(string device) =>
        Selection.Count > 1 && Selection.Contains(device) ? Selection : new[] { device };

    /// <summary><c>TrackView.Device[1]</c> … <c>TrackView.Device[3]</c>; null when the two aren't in the same chain.</summary>
    internal static List<string>? Range(string a, string b)
    {
        if (Split(a) is not var (parentA, i) || Split(b) is not var (parentB, j) || parentA != parentB) return null;
        return Enumerable.Range(Math.Min(i, j), Math.Abs(i - j) + 1).Select(n => $"{parentA}Device[{n}]").ToList();
    }

    /// <summary><c>TrackView.Device[0].Device[2]</c> → (<c>TrackView.Device[0].</c>, 2).</summary>
    static (string, int)? Split(string path)
    {
        var open = path.LastIndexOf("Device[", StringComparison.Ordinal);
        if (open < 0 || !path.EndsWith(']')) return null;
        var start = open + "Device[".Length;
        return int.TryParse(path.AsSpan(start, path.Length - 1 - start), out var index) ? (path[..open], index) : null;
    }
}

public sealed partial record LauncherConfig
{
    /// <summary>"Open all plugin windows of the track"; checked after the built-in shortcuts, before item shortcuts.</summary>
    public bool IsOpenPluginWindowsShortcut(ushort keyCode, ModifierSet modifiers) =>
        PluginWindowSettings.OpenAll.Contains(new KeyCombo(keyCode, modifiers));
}
