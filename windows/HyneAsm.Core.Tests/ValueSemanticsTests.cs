namespace HyneAsm.Core.Tests;

/// <summary>Swift copies configs and menus (value types); the C# port must not let later edits leak through shared objects.</summary>
public class ValueSemanticsTests
{
    static PluginItem Item(string name, ItemSource source = ItemSource.Plugins, params string[] path) =>
        new("u:" + name, name, source, path.ToList());

    [Fact]
    public void PanelState_is_unaffected_by_later_config_edits()
    {
        var eq = Item("EQ Eight", ItemSource.AudioEffects);
        var diva = Item("Diva");
        var c = LauncherConfig.MakeDefault();
        c.AddEntry(eq, c.FavoritesID);
        c.AddEntry(diva, c.Categories[1].Id);
        var state = new PanelState(c, new[] { eq, diva });
        var tabs = state.Tabs.ToList();
        var rows = state.Rows.ToList();

        var other = c.AddProfile("Other", copyingCurrent: false);
        c.SwitchProfile(other);
        c.RenameCategory(c.FavoritesID, "Renamed");
        c.AddEntry(diva, c.FavoritesID);
        c.SwitchProfile(c.Profiles[0].Id);
        c.RenameCategory(c.FavoritesID, "Favs");
        c.SetColor("red", c.Categories[0].Entries[0].Id, c.FavoritesID);
        c.SetDisplayName("EQ8", c.Categories[0].Entries[0].Id, c.FavoritesID);
        c.AddEntry(diva, c.FavoritesID);

        Assert.Equal(tabs, state.Tabs);
        Assert.Equal(rows, state.Rows);
        state.SelectTab(1);
        state.SelectTab(0);   // recomputed from the snapshot, not the edited config
        Assert.Equal(rows, state.Rows);
        Assert.Equal(new[] { "EQ Eight" }, state.Rows.Select(r => r.Title));
        Assert.Null(state.Rows[0].ColorID);
    }

    [Fact]
    public void Profile_switch_does_not_share_actions_or_chain_items()
    {
        var proQ = Item("Pro-Q 4", ItemSource.Plugins, "VST3", "FabFilter");
        var c = LauncherConfig.MakeDefault();
        var first = c.ActiveProfileID;
        c.AddAction(new LiveAction(LiveActionKind.SetTempo, 128), c.FavoritesID);
        c.AddChain("Vocal", new[] { proQ }, c.FavoritesID);
        var other = c.AddProfile("Other", copyingCurrent: false);
        c.SwitchProfile(other);
        c.SwitchProfile(first);   // the stored "first" profile now holds the menu; the loaded one is its copy

        var loaded = c.Categories[0].Entries;
        loaded[0].Action!.Value = 174;
        loaded[1].Chain![0].Name = "Changed";
        loaded[1].Chain![0].Path.Add("X");

        var stored = c.Profiles.Single(p => p.Id == first).Categories[0].Entries;
        Assert.Equal(128, stored[0].Action!.Value);
        Assert.Equal("Pro-Q 4", stored[1].Chain![0].Name);
        Assert.Equal(new[] { "VST3", "FabFilter" }, stored[1].Chain![0].Path);
    }

    [Fact]
    public void Profile_copy_does_not_share_actions_or_chain_items()
    {
        var c = LauncherConfig.MakeDefault();
        c.AddAction(new LiveAction(LiveActionKind.SetTempo, 128), c.FavoritesID);
        c.AddChain("Vocal", new[] { Item("Pro-Q 4") }, c.FavoritesID);
        var id = c.AddProfile("Copy", copyingCurrent: true);
        var copy = c.Profiles.Single(p => p.Id == id).Categories[0].Entries;
        c.Categories[0].Entries[0].Action!.Value = 174;
        c.Categories[0].Entries[1].Chain![0].Name = "Changed";
        Assert.Equal(128, copy[0].Action!.Value);
        Assert.Equal("Pro-Q 4", copy[1].Chain![0].Name);
        Assert.NotEqual(c.Categories[0].Entries[0].Id, copy[0].Id);
    }
}
