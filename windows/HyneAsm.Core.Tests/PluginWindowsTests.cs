using HyneAsm.Core.Json;

namespace HyneAsm.Core.Tests;

/// <summary>Same cases as Tests/HMLauncherCoreTests/PluginWindowsTests.swift.</summary>
[Collection(LocCollection.Name)]
public class PluginWindowsTests
{
    static PluginWindowButton Button(string path, bool open = false) => new(path + PluginWindowPlanner.ButtonSuffix, open);

    [Fact]
    public void DevicePath()
    {
        Assert.Equal("TrackView.Device[0].Device[1]", PluginWindowPlanner.DevicePath("TrackView.Device[0].Device[1].TitleBar.PluginEdit"));
        Assert.Equal("TrackView.Device[2]", PluginWindowPlanner.DevicePath("TrackView.Device[2]"));
        Assert.Null(PluginWindowPlanner.DevicePath("TrackView"));
        Assert.Null(PluginWindowPlanner.DevicePath("Arrangement.Track[3]"));
        Assert.Null(PluginWindowPlanner.DevicePath(null));
    }

    [Fact]
    public void ToPress_opens_closed_or_toggles_all_closed()
    {
        PluginWindowButton open = Button("TrackView.Device[0]", open: true), closed = Button("TrackView.Device[1]");
        Assert.Equal(new[] { closed }, PluginWindowPlanner.ToPress(new[] { open, closed }));
        Assert.Equal(new[] { open }, PluginWindowPlanner.ToPress(new[] { open }));
        Assert.Empty(PluginWindowPlanner.ToPress(Array.Empty<PluginWindowButton>()));
    }

    [Fact]
    public void Settings_are_left_out_of_older_configs()
    {
        var config = LauncherConfig.MakeDefault();
        Assert.Null(config.PluginWindows);
        Assert.DoesNotContain("pluginWindows", SwiftJson.Serialize(config));
        config.PluginWindowSettings = config.PluginWindowSettings with { XyClick = true };
        Assert.Null(config.PluginWindows);
        config.PluginWindowSettings = new PluginWindowSettings
        {
            OpenAll = new() { new KeyCombo(35, ModifierSet.Cmd | ModifierSet.Ctrl) },
            XyClick = false,
        };
        var back = SwiftJson.Deserialize<LauncherConfig>(SwiftJson.Serialize(config));
        Assert.Equal(config.PluginWindows, back.PluginWindows);
    }

    [Fact]
    public void A_damaged_block_falls_back_to_the_defaults()
    {
        var json = SwiftJson.Serialize(LauncherConfig.MakeDefault()).TrimEnd().TrimEnd('}') + ",\"pluginWindows\":{\"openAll\":7}}";
        Assert.Null(SwiftJson.Deserialize<LauncherConfig>(json).PluginWindows);
        var partial = SwiftJson.Serialize(LauncherConfig.MakeDefault()).TrimEnd().TrimEnd('}') + ",\"pluginWindows\":{\"xyClick\":false}}";
        Assert.Equal(new PluginWindowSettings { XyClick = false }, SwiftJson.Deserialize<LauncherConfig>(partial).PluginWindows);
    }

    [Fact]
    public void Plugin_window_shortcuts_show_as_owners()
    {
        var config = LauncherConfig.MakeDefault();
        var combo = new KeyCombo(35, ModifierSet.Cmd | ModifierSet.Ctrl);
        config.PluginWindowSettings = config.PluginWindowSettings with { OpenAll = new() { combo } };
        Assert.Equal(Loc.T("Alle Plugin-Fenster der Spur öffnen", "Open all plugin windows of the track"), config.ShortcutOwner(combo));
        Assert.True(config.IsOpenPluginWindowsShortcut(35, ModifierSet.Cmd | ModifierSet.Ctrl));
        Assert.False(config.IsOpenPluginWindowsShortcut(35, ModifierSet.Cmd));
    }

    [Fact]
    public void XyButton()
    {
        Assert.Equal("TrackView.Device[3].TitleBar.PluginEdit", PluginWindowPlanner.XyButton("TrackView.Device[3].PluginXyControl"));
        Assert.Equal("TrackView.Device[0].Device[1].TitleBar.PluginEdit", PluginWindowPlanner.XyButton("TrackView.Device[0].Device[1].PluginXyControl.Slider"));
        Assert.Null(PluginWindowPlanner.XyButton("TrackView.Device[3]"));
        Assert.Null(PluginWindowPlanner.XyButton("TrackView.Device[3].PluginXyControlX"));
        Assert.Null(PluginWindowPlanner.XyButton("TrackView.Device[3].TitleBar.device_title"));
        Assert.Null(PluginWindowPlanner.XyButton(null));
    }

    [Fact]
    public void Selection_follows_clicks_and_shift_ranges()
    {
        var t = new DeviceSelectionTracker();
        t.Click("TrackView.Device[1].TitleBar.device_title", extend: false);
        Assert.Equal(new[] { "TrackView.Device[1]" }, t.Selection);
        t.Click("TrackView.Device[3].TitleBar.device_title", extend: true);
        Assert.Equal(new[] { "TrackView.Device[1]", "TrackView.Device[2]", "TrackView.Device[3]" }, t.Selection);
        Assert.Equal(t.Selection, t.DevicesForClickOn("TrackView.Device[2]"));
        Assert.Equal(new[] { "TrackView.Device[5]" }, t.DevicesForClickOn("TrackView.Device[5]"));
        t.Click("TrackView.Device[0]", extend: true);
        Assert.Equal(new[] { "TrackView.Device[0]", "TrackView.Device[1]" }, t.Selection);
        t.Click("ArrangementView", extend: false);
        Assert.Empty(t.Selection);
        Assert.Equal(new[] { "TrackView.Device[0]" }, t.DevicesForClickOn("TrackView.Device[0]"));
    }

    [Fact]
    public void Shift_without_anchor_or_across_chains_selects_one()
    {
        var t = new DeviceSelectionTracker();
        t.Click("TrackView.Device[2]", extend: true);
        Assert.Equal(new[] { "TrackView.Device[2]" }, t.Selection);
        t.Click("TrackView.Device[0].Device[1]", extend: true);
        Assert.Equal(new[] { "TrackView.Device[0].Device[1]" }, t.Selection);
        t.Click("TrackView.Device[0].Device[3].PluginXyControl", extend: true);
        Assert.Equal(new[] { "TrackView.Device[0].Device[1]", "TrackView.Device[0].Device[2]", "TrackView.Device[0].Device[3]" }, t.Selection);
    }
}
