namespace HyneAsm.Core;

/// <summary>Editing several entries at once: move them together, to another category, or group them into a folder.</summary>
public sealed partial record LauncherConfig
{
    /// <summary>Every entry id of the category in list order: top level, each folder followed by its plugins.</summary>
    public List<Guid> OrderedEntryIDs(Guid categoryID) =>
        (Categories.FirstOrDefault(c => c.Id == categoryID)?.Entries ?? new())
            .SelectMany(e => new[] { e.Id }.Concat((e.Children ?? new()).Select(k => k.Id))).ToList();

    /// <summary>Moves several entries together (kept in list order) into the category's top level or into a folder,
    /// in front of <paramref name="anchor"/> (an entry of that container) or at its end. Folders never go into folders.</summary>
    public void MoveEntries(IEnumerable<Guid> ids, Guid? toFolder, Guid? anchor, Guid categoryID)
    {
        var wanted = new HashSet<Guid>(ids);
        var moving = OrderedEntryIDs(categoryID).Where(wanted.Contains).Select(id => FindEntry(id, categoryID)).OfType<Entry>()
            .Where(e => toFolder == null || !e.IsFolder)
            .Where(e => e.Id != toFolder)
            .ToList();
        if (moving.Count == 0) return;
        if (toFolder is { } f && FindEntry(f, categoryID)?.IsFolder != true) return;
        foreach (var e in moving) RemoveEntry(e.Id, categoryID);
        InsertEntries(moving, toFolder, anchor, categoryID);
    }

    /// <summary>Moves entries (plugins, folders with their plugins) to the end of another category, keeping list order,
    /// icons and display names. A plugin the target already has is only removed from the source.</summary>
    public void MoveEntries(IEnumerable<Guid> ids, Guid toCategory, Guid fromCategory)
    {
        if (toCategory == fromCategory || IndexOf(toCategory) is not { } t) return;
        var wanted = new HashSet<Guid>(ids);
        var source = Categories.FirstOrDefault(c => c.Id == fromCategory)?.Entries ?? new();
        // A selected folder carries its plugins; don't move those a second time.
        var carried = new HashSet<Guid>(source.Where(e => e.IsFolder && wanted.Contains(e.Id))
            .SelectMany(e => e.Children ?? new()).Select(e => e.Id));
        var moving = OrderedEntryIDs(fromCategory).Where(id => wanted.Contains(id) && !carried.Contains(id))
            .Select(id => FindEntry(id, fromCategory)).OfType<Entry>().ToList();
        foreach (var e in moving)
        {
            RemoveEntry(e.Id, fromCategory);
            var existing = new HashSet<string>(Categories[t].Entries.SelectMany(x => x.Children ?? new List<Entry> { x })
                .Where(x => !x.IsFolder).Select(x => x.Uri), Text.Canonical);
            if (e.IsFolder || !existing.Contains(e.Uri)) Categories[t].Entries.Add(e);
        }
    }

    /// <summary>Puts the selected plugins (from anywhere in the category, folders ignored) into a new folder placed
    /// where the first of them was. Returns the folder, or null when no plugin was selected.</summary>
    public Guid? GroupEntries(IEnumerable<Guid> ids, Guid categoryID, string name)
    {
        if (IndexOf(categoryID) is not { } c) return null;
        var wanted = new HashSet<Guid>(ids);
        var plugins = OrderedEntryIDs(categoryID).Where(wanted.Contains).Select(id => FindEntry(id, categoryID)).OfType<Entry>()
            .Where(e => !e.IsFolder).ToList();
        if (plugins.Count == 0) return null;
        var first = plugins[0];
        // The folder goes where the first plugin sits at top level (or in front of the folder holding it).
        var moved = new HashSet<Guid>(plugins.Select(p => p.Id));
        var entries = Categories[c].Entries;
        var slot = entries.FindIndex(e => e.Id == first.Id || e.Children?.Any(k => k.Id == first.Id) == true);
        if (slot < 0) slot = 0;
        var anchor = entries.Skip(slot).FirstOrDefault(e => !moved.Contains(e.Id))?.Id;
        foreach (var p in plugins) RemoveEntry(p.Id, categoryID);
        var folder = Entry.FolderNamed(name);
        folder.Children = plugins;
        InsertEntries(new List<Entry> { folder }, null, anchor, categoryID);
        return folder.Id;
    }

    void InsertEntries(List<Entry> entries, Guid? folderID, Guid? anchor, Guid categoryID)
    {
        if (IndexOf(categoryID) is not { } c) return;
        List<Entry> list;
        if (folderID is { } id)
        {
            var folder = Categories[c].Entries.FirstOrDefault(e => e.Id == id);
            if (folder == null) return;
            list = folder.Children ??= new();
        }
        else list = Categories[c].Entries;
        var at = anchor is { } a ? list.FindIndex(e => e.Id == a) : -1;
        list.InsertRange(at < 0 ? list.Count : at, entries);
    }
}
