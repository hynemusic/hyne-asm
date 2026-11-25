namespace HyneAsm.Core.Tests;

/// <summary>Same cases as the copy/cut/paste tests in Tests/HMLauncherCoreTests/MultiEditTests.swift.</summary>
public class ClipboardTests
{
    readonly LauncherConfig c = LauncherConfig.MakeDefault();
    readonly Guid fx;
    readonly Dictionary<string, Guid> ids = new();

    public ClipboardTests()
    {
        fx = c.Categories[2].Id;
        foreach (var n in new[] { "A", "B", "C", "D", "E" })
        {
            c.AddEntry(new PluginItem("u:" + n, n, ItemSource.Plugins, new List<string>()), fx);
            ids[n] = c.Categories[2].Entries[^1].Id;
        }
    }

    List<string> Top => c.Categories[2].Entries.Select(e => e.Title).ToList();
    HashSet<Guid> Pick(params string[] names) => names.Select(n => ids[n]).ToHashSet();

    [Fact]
    public void Copy_paste_adds_new_entries()
    {
        var other = c.Categories[1].Id;
        var pasted = c.Paste(c.Clipboard(Pick("B", "D"), fx, cut: false)!, other, null, null);
        Assert.Equal(new[] { "B", "D" }, c.Categories[1].Entries.Select(e => e.Title));
        Assert.Equal(new[] { "A", "B", "C", "D", "E" }, Top);
        Assert.DoesNotContain(ids["B"], pasted);
    }

    [Fact]
    public void Copy_into_same_container_skips_plugins_it_holds()
    {
        Assert.Empty(c.Paste(c.Clipboard(Pick("A"), fx, cut: false)!, fx, null, null));
        Assert.Equal(new[] { "A", "B", "C", "D", "E" }, Top);
    }

    [Fact]
    public void Cut_paste_moves_in_front_of_anchor()
    {
        var pasted = c.Paste(c.Clipboard(Pick("D", "E"), fx, cut: true)!, fx, null, ids["B"]);
        Assert.Equal(new[] { "A", "D", "E", "B", "C" }, Top);
        Assert.Equal(new[] { ids["D"], ids["E"] }, pasted);
    }

    [Fact]
    public void Cut_paste_into_folder_and_across_categories()
    {
        var folder = c.AddFolder("F", fx);
        c.Paste(c.Clipboard(Pick("A", "C"), fx, cut: true)!, fx, folder, null);
        Assert.Equal(new[] { "B", "D", "E", "F" }, Top);
        Assert.Equal(new[] { "A", "C" }, c.FindEntry(folder, fx)!.Children!.Select(e => e.Title));
        var other = c.Categories[1].Id;
        c.Paste(c.Clipboard(new HashSet<Guid> { folder }, fx, cut: true)!, other, null, null);
        Assert.Equal(new[] { "B", "D", "E" }, Top);
        Assert.Equal(new[] { "A", "C" }, c.Categories[1].Entries[0].Children!.Select(e => e.Title));
    }

    [Fact]
    public void Folder_pasted_into_folder_gives_its_plugins_and_never_into_itself()
    {
        var f = c.AddFolder("F", fx);
        var g = c.AddFolder("G", fx);
        c.MoveEntries(new[] { ids["A"] }, f, null, fx);
        c.Paste(c.Clipboard(new HashSet<Guid> { f }, fx, cut: false)!, fx, g, null);
        Assert.Equal(new[] { "A" }, c.FindEntry(g, fx)!.Children!.Select(e => e.Title));
        Assert.Empty(c.Paste(c.Clipboard(new HashSet<Guid> { f }, fx, cut: true)!, fx, f, null));
        Assert.Equal(new[] { "A" }, c.FindEntry(f, fx)!.Children!.Select(e => e.Title));
    }

    [Fact]
    public void Selected_folder_carries_its_plugins_once()
    {
        var f = c.AddFolder("F", fx);
        c.MoveEntries(new[] { ids["A"] }, f, null, fx);
        var clip = c.Clipboard(new HashSet<Guid> { f, ids["A"] }, fx, cut: false)!;
        Assert.Equal(new[] { "F" }, clip.Entries.Select(e => e.Title));
    }

    [Fact]
    public void Clipboard_keeps_its_own_copies()
    {
        var clip = c.Clipboard(Pick("A"), fx, cut: false)!;
        c.Categories[2].Entries[0].DisplayName = "Renamed";
        Assert.Equal("A", clip.Entries[0].Title);
    }
}
