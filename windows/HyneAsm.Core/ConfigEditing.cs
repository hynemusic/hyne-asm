using System.Text.Json.Serialization;

namespace HyneAsm.Core;

/// <summary>Editing the menu: entries (top level or inside a folder), folders, categories, icons and names.</summary>
public sealed partial record LauncherConfig
{
    [JsonIgnore] public Guid FavoritesID => Categories.First(c => c.IsFavorites).Id;

    int? IndexOf(Guid categoryID)
    {
        var i = Categories.FindIndex(c => c.Id == categoryID);
        return i < 0 ? null : i;
    }

    // MARK: Entries (top level or inside a folder)

    /// <summary>Adds a plugin to the category, or into one of its folders. Ignored if that container already holds it.
    /// The icon is the one this plugin already has elsewhere, else a guess from its name.</summary>
    public void AddEntry(PluginItem item, Guid categoryID, Guid? folder = null)
    {
        var icon = ExistingIcon(item.Name, item.Source) ?? IconGuesser.Guess(item);
        WithContainer(categoryID, folder, list =>
        {
            if (list.Any(e => !e.IsFolder && Text.Equal(e.Uri, item.Uri))) return;
            list.Add(new Entry(item, icon));
        });
    }

    /// <summary>A chain of items inserted one after the other; returns its entry id.</summary>
    public Guid AddChain(string name, IReadOnlyList<PluginItem> steps, Guid categoryID, Guid? folder = null)
    {
        var entry = Entry.ChainNamed(name, steps.ToList());
        WithContainer(categoryID, folder, list => list.Add(entry));
        return entry.Id;
    }

    public void UpdateChain(Guid id, Guid categoryID, string name, IReadOnlyList<PluginItem> steps) => UpdateEntry(id, categoryID, e =>
    {
        e.Name = name;
        e.DisplayName = null;
        e.Chain = steps.ToList();
    });

    /// <summary>New values for an action entry ("Tempo 120" → "Tempo 128"); a name the user typed stays.</summary>
    public void UpdateAction(Guid id, Guid categoryID, LiveAction action) => UpdateEntry(id, categoryID, e =>
    {
        e.Action = action;
        e.Name = action.Title;
    });

    /// <summary>A Live action; the same action with the same values only once per container.</summary>
    public void AddAction(LiveAction action, Guid categoryID, Guid? folder = null) => WithContainer(categoryID, folder, list =>
    {
        if (list.Any(e => Equals(e.Action, action))) return;
        list.Add(new Entry(action));
    });

    public Guid AddFolder(string name, Guid categoryID)
    {
        var folder = Entry.FolderNamed(name);
        WithContainer(categoryID, null, list => list.Add(folder));
        return folder.Id;
    }

    /// <summary>Removes a plugin or a whole folder, wherever it sits in the category.</summary>
    public void RemoveEntry(Guid entryID, Guid categoryID)
    {
        if (IndexOf(categoryID) is not { } c) return;
        Categories[c].Entries.RemoveAll(e => e.Id == entryID);
        foreach (var e in Categories[c].Entries.Where(e => e.IsFolder)) e.Children!.RemoveAll(k => k.Id == entryID);
    }

    /// <summary>Reorders within the category, or within one folder of it.</summary>
    public void MoveEntry(Guid categoryID, Guid? folder, int from, int to) => WithContainer(categoryID, folder, list =>
    {
        if (from < 0 || from >= list.Count || to < 0 || to >= list.Count) return;
        var e = list[from];
        list.RemoveAt(from);
        list.Insert(to, e);
    });

    /// <summary>Moves a plugin into a folder (appended) or, with null, out to the end of the category. Folders never nest.</summary>
    public void MoveEntry(Guid entryID, Guid? toFolder, Guid categoryID)
    {
        if (FindEntry(entryID, categoryID) is not { IsFolder: false } entry) return;
        if (toFolder is { } f && FindEntry(f, categoryID)?.IsFolder != true) return;
        RemoveEntry(entryID, categoryID);
        WithContainer(categoryID, toFolder, list => list.Add(entry));
    }

    public void RenameFolder(Guid folderID, Guid categoryID, string name)
    {
        var trimmed = Text.TrimWhitespaces(name);
        if (trimmed.Length == 0) return;
        UpdateEntry(folderID, categoryID, e => { if (e.IsFolder) e.Name = trimmed; });
    }

    /// <summary>Replaces the folder by its plugins, at the folder's position.</summary>
    public void DissolveFolder(Guid folderID, Guid categoryID)
    {
        if (IndexOf(categoryID) is not { } c) return;
        var entries = Categories[c].Entries;
        var f = entries.FindIndex(e => e.Id == folderID && e.IsFolder);
        if (f < 0) return;
        var children = entries[f].Children ?? new();
        entries.RemoveAt(f);
        entries.InsertRange(f, children);
    }

    public Entry? FindEntry(Guid id, Guid categoryID)
    {
        if (IndexOf(categoryID) is not { } c) return null;
        foreach (var e in Categories[c].Entries)
        {
            if (e.Id == id) return e;
            if (e.Children?.FirstOrDefault(k => k.Id == id) is { } hit) return hit;
        }
        return null;
    }

    // MARK: Categories

    public Guid AddCategory(string name)
    {
        var c = new Category(name);
        Categories.Add(c);
        return c.Id;
    }

    public void RenameCategory(Guid id, string name)
    {
        if (IndexOf(id) is { } c) Categories[c].Name = name;
    }

    public void DeleteCategory(Guid id) => Categories.RemoveAll(c => c.Id == id && !c.IsFavorites);

    /// <summary>Favorites always stays at index 0.</summary>
    public void MoveCategory(int from, int to)
    {
        if (from < 0 || from >= Categories.Count || from == 0 || to < 0 || to >= Categories.Count) return;
        var c = Categories[from];
        Categories.RemoveAt(from);
        Categories.Insert(Math.Max(1, to), c);
    }

    /// <summary>Drag &amp; drop: moves a category in front of <paramref name="anchor"/> (null = to the end). Favorites never
    /// moves and stays first.</summary>
    public void MoveCategory(Guid id, Guid? anchor)
    {
        if (id == anchor || IndexOf(id) is not { } from || Categories[from].IsFavorites) return;
        var c = Categories[from];
        Categories.RemoveAt(from);
        var to = (anchor is { } a ? IndexOf(a) : null) ?? Categories.Count;
        Categories.Insert(Math.Max(1, to), c);
    }

    // MARK: Icons & names

    /// <summary>Icons are per plugin: every entry with the same name and source (e.g. Pro-L 2 VST3 and AU) changes too,
    /// also inside folders. A folder's icon only changes that folder.</summary>
    public void SetIcon(string iconID, Guid entry, Guid categoryID)
    {
        if (FindEntry(entry, categoryID) is not { } target) return;
        if (target.IsFolder)
        {
            UpdateEntry(entry, categoryID, e => e.IconID = iconID);
            return;
        }
        foreach (var category in Categories)
            foreach (var e in category.Entries)
            {
                if (!e.IsFolder && SamePlugin(e, target)) e.IconID = iconID;
                foreach (var child in e.Children ?? new())
                    if (SamePlugin(child, target)) child.IconID = iconID;
            }
    }

    public void SetDisplayName(string? name, Guid entry, Guid categoryID)
    {
        var trimmed = name == null ? null : Text.TrimWhitespaces(name);
        UpdateEntry(entry, categoryID, e => e.DisplayName = string.IsNullOrEmpty(trimmed) ? null : trimmed);
    }

    /// <summary>Every plugin entry, including those inside folders.</summary>
    [JsonIgnore] public List<Entry> AllPluginEntries => Categories.SelectMany(c => c.Entries.SelectMany(e => e.Children ?? new List<Entry> { e })).ToList();

    /// <summary>The Favorites entry for this panel row, matched by the entry's resolved uri (VST3 and AU stay distinct).</summary>
    public Entry? FavoriteEntry(PanelRow row, IReadOnlyList<PluginItem> items)
    {
        if (row.FolderID != null) return null;
        return Categories.FirstOrDefault(c => c.IsFavorites)?.Entries.SelectMany(e => e.Children ?? new List<Entry> { e })
            .FirstOrDefault(e => Text.Equal(e.Uri, row.Uri) || Text.Equal(EntryResolver.Resolve(e, items)?.Uri, row.Uri));
    }

    // MARK: Helpers

    string? ExistingIcon(string name, ItemSource source) =>
        AllPluginEntries.FirstOrDefault(e => Text.Equal(e.Name, name) && e.Source == source)?.IconID;

    /// <summary>Same plugin for icons and colors: same uri, or same name and source (another format).</summary>
    static bool SamePlugin(Entry a, Entry b) => Text.Equal(a.Uri, b.Uri) || (Text.Equal(a.Name, b.Name) && a.Source == b.Source);

    void WithContainer(Guid categoryID, Guid? folderID, Action<List<Entry>> change)
    {
        if (IndexOf(categoryID) is not { } c) return;
        if (folderID is { } id)
        {
            var folder = Categories[c].Entries.FirstOrDefault(e => e.Id == id && e.IsFolder);
            if (folder != null) change(folder.Children!);
        }
        else change(Categories[c].Entries);
    }

    void UpdateEntry(Guid id, Guid categoryID, Action<Entry> change)
    {
        if (IndexOf(categoryID) is not { } c) return;
        foreach (var e in Categories[c].Entries)
        {
            if (e.Id == id) { change(e); return; }
            if (e.Children?.FirstOrDefault(k => k.Id == id) is { } child) { change(child); return; }
        }
    }
}
