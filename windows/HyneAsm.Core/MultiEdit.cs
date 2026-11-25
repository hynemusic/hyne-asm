using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>Entries copied (Ctrl+C) or cut (Ctrl+X) in the settings, put back with Ctrl+V. Holds its own copies,
/// so later edits don't change what was copied. Same as EntryClipboard in Sources/HMLauncherCore/MultiEdit.swift.</summary>
public sealed record EntryClipboard(List<Entry> Entries, Guid SourceCategory, bool IsCut);

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

    // MARK: Copy, cut, paste

    /// <summary>The selected entries for Ctrl+C / Ctrl+X, in list order. A selected folder carries its plugins, so they
    /// aren't taken twice.</summary>
    public EntryClipboard? Clipboard(ISet<Guid> ids, Guid categoryID, bool cut)
    {
        if (Categories.FirstOrDefault(c => c.Id == categoryID) is not { } category) return null;
        var output = new List<Entry>();
        foreach (var e in category.Entries)
        {
            if (ids.Contains(e.Id)) { output.Add(e); continue; }
            output.AddRange((e.Children ?? new()).Where(k => ids.Contains(k.Id)));
        }
        return output.Count == 0 ? null : new EntryClipboard(output.Select(SwiftJson.Clone).ToList(), categoryID, cut);
    }

    /// <summary>Ctrl+V: the clipboard's entries go into the category's top level or into a folder, in front of
    /// <paramref name="anchor"/> (an entry of that container; at its end when null or gone). Cut entries move (ids kept);
    /// copied ones are added as new entries. Into a folder, a folder gives its plugins (folders don't nest). A plugin
    /// the container already holds is skipped. Returns the ids of the pasted entries.</summary>
    public List<Guid> Paste(EntryClipboard clip, Guid categoryID, Guid? folder, Guid? anchor)
    {
        if (IndexOf(categoryID) is null) return new();
        if (folder is { } f)
        {
            if (FindEntry(f, categoryID)?.IsFolder != true) return new();
            if (clip.IsCut && clip.Entries.Any(e => e.Id == f)) return new(); // a folder into itself
        }
        var items = clip.Entries.Select(SwiftJson.Clone).ToList();
        if (folder != null) items = items.SelectMany(e => e.IsFolder ? e.Children! : new List<Entry> { e }).ToList();
        if (clip.IsCut) foreach (var e in clip.Entries) RemoveEntry(e.Id, clip.SourceCategory);
        else items = items.Select(FreshCopy).ToList();
        var container = folder is { } id ? FindEntry(id, categoryID)?.Children ?? new() : Categories[IndexOf(categoryID)!.Value].Entries;
        var taken = new HashSet<string>(container.Where(IsPlainPlugin).Select(e => e.Uri));
        items = items.Where(e => !IsPlainPlugin(e) || taken.Add(e.Uri)).ToList();
        InsertEntries(items, folder, anchor, categoryID);
        return items.Select(e => e.Id).ToList();
    }

    static bool IsPlainPlugin(Entry e) => !e.IsFolder && e.Chain == null && e.Action == null && e.Uri.Length > 0;

    /// <summary>The same entry (and a folder's plugins) with new ids.</summary>
    static Entry FreshCopy(Entry e)
    {
        e.Id = Guid.NewGuid();
        foreach (var k in e.Children ?? new()) k.Id = Guid.NewGuid();
        return e;
    }
}
