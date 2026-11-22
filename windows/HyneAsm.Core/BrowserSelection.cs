namespace HyneAsm.Core;

/// <summary>What is selected in the settings browser: whole folders (presets folder, manufacturer, Live group) and single items.</summary>
public sealed record BrowserSelection
{
    public sealed record Folder(string Title, IReadOnlyList<PluginItem> Items);

    public List<Folder> Folders { get; set; }
    public List<PluginItem> Items { get; set; }
    /// <summary>Live actions (with their default values: Tempo 120, 4/4).</summary>
    public List<LiveAction> Actions { get; set; }

    public BrowserSelection(IEnumerable<Folder>? folders = null, IEnumerable<PluginItem>? items = null, IEnumerable<LiveAction>? actions = null)
    {
        Folders = folders?.ToList() ?? new();
        Items = items?.ToList() ?? new();
        Actions = actions?.ToList() ?? new();
    }

    public bool IsEmpty => Folders.Count == 0 && Items.Count == 0 && Actions.Count == 0;

    /// <summary>Number of entries it adds (an item inside a selected folder counts once).</summary>
    public int PluginCount
    {
        get
        {
            var inFolders = new HashSet<string>(Folders.SelectMany(f => f.Items.Select(i => i.Uri)), Text.Canonical);
            return inFolders.Count + Items.Count(i => !inFolders.Contains(i.Uri)) + Actions.Count;
        }
    }
}

public sealed partial record LauncherConfig
{
    /// <summary>Adds a browser selection to a category.
    /// <para><paramref name="asFolders"/>: each selected folder becomes a folder of the same name (an existing one is reused),
    /// single items go to the top level. Otherwise everything is added loose.</para>
    /// <para><paramref name="folder"/>: dropped into an existing folder — everything goes in there (folders can't nest).</para>
    /// Plugins the target already holds are skipped.</summary>
    public void Add(BrowserSelection selection, Guid categoryID, Guid? folder = null, bool asFolders = true)
    {
        var inFolders = new HashSet<string>(selection.Folders.SelectMany(f => f.Items.Select(i => i.Uri)), Text.Canonical);
        var loose = selection.Items.Where(i => !inFolders.Contains(i.Uri)).ToList();
        if (folder != null || !asFolders)
        {
            foreach (var item in selection.Folders.SelectMany(f => f.Items).Concat(loose)) AddEntry(item, categoryID, folder);
            foreach (var action in selection.Actions) AddAction(action, categoryID, folder);
            return;
        }
        foreach (var f in selection.Folders)
        {
            var existing = Categories.FirstOrDefault(c => c.Id == categoryID)?.Entries
                .FirstOrDefault(e => e.IsFolder && Text.Equal(e.Title, f.Title))?.Id;
            var id = existing ?? AddFolder(f.Title, categoryID);
            foreach (var item in f.Items) AddEntry(item, categoryID, id);
        }
        foreach (var item in loose) AddEntry(item, categoryID);
        foreach (var action in selection.Actions) AddAction(action, categoryID);
    }
}
