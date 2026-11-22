namespace HyneAsm.Core;

// MARK: - Parsing LES menuconfig.ini

public sealed record LESItem(string Display, string Query);

public sealed record LESCategory
{
    public string Name { get; init; }
    public List<LESItem> Items { get; init; }
    /// <summary>Index of the top-level category this <c>//</c> subfolder sits in (deeper levels attach to their top-level ancestor).</summary>
    public int? Parent { get; set; }

    public LESCategory(string name, List<LESItem> items, int? parent = null) { Name = name; Items = items; Parent = parent; }

    public bool Equals(LESCategory? o) => o is not null && Name == o.Name && Items.SequenceEqual(o.Items) && Parent == o.Parent;

    public override int GetHashCode() => HashCode.Combine(Name, ValueEquality.Hash(Items), Parent);
}

/// <summary>Parses the Live Enhancement Suite plugin menu (<c>menuconfig.ini</c>): <c>/Category</c>, <c>//Sub</c>, <c>..</c>
/// back up, item pairs (display name line, search query line), <c>--</c> dividers, <c>;</c> comments, <c>/nocategory</c>,
/// trailing <c>End</c>. Subfolders keep a link to their top-level category; dividers are dropped.
/// Windows-made files work too: CRLF line endings and a UTF-8 BOM.</summary>
public static class LESMenuParser
{
    /// <summary>%USERPROFILE%\.les\menuconfig.ini (~/.les/menuconfig.ini on the Mac). To confirm on Windows in Plan 2;
    /// the import screen also lets the user pick the file.</summary>
    public static string DefaultPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".les", "menuconfig.ini");

    /// <summary>Reads and parses the file: a UTF-8 BOM is skipped, invalid UTF-8 throws (as Swift's
    /// <c>String(contentsOf:encoding: .utf8)</c> does).</summary>
    public static List<LESCategory> ParseFile(string path) => Parse(Json.SwiftJson.DecodeUtf8(File.ReadAllBytes(path)));

    public static List<LESCategory> Parse(string text)
    {
        if (text.StartsWith('﻿')) text = text[1..];
        var categories = new List<LESCategory>();
        var stack = new List<int>();   // indices into categories for the current folder path
        int? current = null;
        string? pendingDisplay = null;

        void Open(string name, int depth)
        {
            pendingDisplay = null;
            stack = stack.Take(Math.Max(depth - 1, 0)).ToList();
            categories.Add(new LESCategory(name, new(), stack.Count > 0 ? stack[0] : null));
            stack.Add(categories.Count - 1);
            current = categories.Count - 1;
        }

        var lines = text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n').Split('\n').Select(Text.TrimWhitespaces);
        foreach (var line in lines)
        {
            if (line.Length == 0 || Text.HasPrefix(line, ";") || Text.Equal(line, "--")) continue;
            if (Text.Equal(line, ".."))
            {
                pendingDisplay = null;
                if (stack.Count > 1) stack.RemoveAt(stack.Count - 1);
                current = stack.Count > 0 ? stack[^1] : null;
                continue;
            }
            if (Text.HasPrefix(line, "/"))
            {
                var depth = Text.Characters(line).TakeWhile(c => c == "/").Count();
                var name = Text.TrimWhitespaces(Text.DropFirst(line, depth));
                Open(Text.Equal(Text.Lower(name), "nocategory") ? Loc.T("Sonstiges", "Other") : name, depth);
                continue;
            }
            if (pendingDisplay is not { } display)
            {
                pendingDisplay = line;
                continue;
            }
            pendingDisplay = null;
            if (Text.Equal(Text.Lower(display), "readme")) continue;
            if (current == null) Open(Loc.T("Sonstiges", "Other"), 1);
            categories[current!.Value].Items.Add(new LESItem(display, line));
        }
        // A dangling single line is LES's "End" marker (or garbage) — never an item.
        return Compact(categories);
    }

    /// <summary>Drops empty folders (a parent with only subfolders stays), merges repeated top-level names
    /// ("/nocategory" can appear several times) and re-points <c>Parent</c> to the new indices.</summary>
    static List<LESCategory> Compact(List<LESCategory> categories)
    {
        var hasChildren = categories.Where(c => c.Items.Count > 0 && c.Parent != null).Select(c => c.Parent!.Value).ToHashSet();
        var result = new List<LESCategory>();
        var newIndex = new Dictionary<int, int>();
        for (var i = 0; i < categories.Count; i++)
        {
            var c = categories[i];
            if (c.Items.Count == 0 && !hasChildren.Contains(i)) continue;
            c = c with { Items = c.Items.ToList(), Parent = c.Parent is { } p && newIndex.TryGetValue(p, out var np) ? np : null };
            var same = c.Parent == null ? result.FindIndex(r => r.Parent == null && Text.Equal(r.Name, c.Name)) : -1;
            if (same >= 0)
            {
                result[same].Items.AddRange(c.Items);
                newIndex[i] = same;
            }
            else
            {
                result.Add(c);
                newIndex[i] = result.Count - 1;
            }
        }
        return result;
    }
}

// MARK: - Queries

public enum LESFormat { Vst3, Vst2, Au, MaxForLive }

/// <summary>An LES search query: quotes removed, trailing format hint (<c>vst3</c>, <c>vst</c>, <c>au</c>, <c>amxd</c>)
/// and file extension parsed.</summary>
public sealed record LESQuery
{
    public string Text { get; }
    public LESFormat? Format { get; }
    public bool IsPreset { get; }

    public LESQuery(string text, LESFormat? format, bool isPreset) { Text = text; Format = format; IsPreset = isPreset; }

    static readonly Dictionary<string, LESFormat> Hints = new(Core.Text.Canonical)
    {
        ["vst3"] = LESFormat.Vst3, ["vst"] = LESFormat.Vst2, ["au"] = LESFormat.Au, ["amxd"] = LESFormat.MaxForLive,
    };

    static readonly string[] PresetExtensions = { ".adv", ".adg", ".aupreset", ".fxp", ".fxb", ".vstpreset", ".als", ".alc" };

    public LESQuery(string raw)
    {
        var tokens = Core.Text.SplitWhitespace(raw);
        LESFormat? format = null;
        if (tokens.Count > 1 && Hints.TryGetValue(Core.Text.Lower(tokens[^1]), out var hint))
        {
            format = hint;
            tokens.RemoveAt(tokens.Count - 1);
        }
        var text = Core.Text.Lower(string.Join(" ", tokens).Replace("\"", "", StringComparison.Ordinal));
        var preset = false;
        if (Core.Text.HasSuffix(text, ".amxd"))
        {
            text = text[..^5];
            format = LESFormat.MaxForLive;
        }
        else if (PresetExtensions.FirstOrDefault(e => Core.Text.HasSuffix(text, e)) is { } ext)
        {
            text = text[..^ext.Length];
            preset = true;
        }
        Text = LESMatcher.Normalize(text);
        Format = format;
        IsPreset = preset;
    }
}

// MARK: - Matching against Live's plugin list

public enum LESMatchStatus { Found, Uncertain, NotFound }

public sealed record LESMatch
{
    public LESMatchStatus Status { get; init; }
    public PluginItem? Item { get; init; }
    /// <summary>For uncertain matches: one candidate per distinct plugin name, best first.</summary>
    public IReadOnlyList<PluginItem> Alternatives { get; init; } = Array.Empty<PluginItem>();
    /// <summary>The LES entry pointed at a preset/rack file; presets cannot be imported, only a suggested plugin.</summary>
    public bool IsPreset { get; init; }

    public static LESMatch Manual(PluginItem item) => new() { Status = LESMatchStatus.Found, Item = item };

    public bool Equals(LESMatch? o) => o is not null && Status == o.Status && Equals(Item, o.Item) &&
        Alternatives.SequenceEqual(o.Alternatives) && IsPreset == o.IsPreset;

    public override int GetHashCode() => HashCode.Combine(Status, Item, Alternatives.Count, IsPreset);
}

/// <summary>Finds Live's items for the entries of an LES menu.</summary>
public sealed partial class LESMatcher
{
    readonly List<(PluginItem Item, string Name)> items;

    public LESMatcher(IEnumerable<PluginItem> items)
    {
        this.items = items.Select(i => (i, Normalize(i.Name))).ToList();
    }

    /// <summary>Lowercase, single spaces (keeps the normalization form, as Swift does).</summary>
    internal static string Normalize(string s) => Text.CollapseWhitespace(Text.Lower(s));

    static readonly int[] QueryPoints = { 100, 90, 85, 75, 60 };
    static readonly int[] DisplayPoints = { 95, 85, 80, 70, 55 };

    /// <summary>Query matches score 100 exact / 90 exact ignoring spaces &amp; punctuation / 85 prefix / 75 contains / 60 all
    /// words; the LES display name a bit lower (95/85/80/70/55) so the search query stays decisive. Below 55 nothing
    /// matched. A single plugin name scoring ≥ 70 counts as found; ties between names or weaker hits are "uncertain".</summary>
    public LESMatch Match(string display, string query)
    {
        var q = new LESQuery(query);
        var displayText = Normalize(display);
        var best = 0;
        var scored = new List<(PluginItem Item, string Name, int Score)>();
        foreach (var (item, name) in items)
        {
            var s = Math.Max(Score(name, q.Text, QueryPoints), Score(name, displayText, DisplayPoints));
            if (s < 55) continue;
            scored.Add((item, name, s));
            best = Math.Max(best, s);
        }
        if (best < 55) return new LESMatch { Status = LESMatchStatus.NotFound, IsPreset = q.IsPreset };

        // One representative per distinct name, preferring the hinted format.
        var byName = new Dictionary<string, (PluginItem Item, int Score)>(Text.Canonical);
        foreach (var s in scored)
        {
            if (byName.TryGetValue(s.Name, out var existing) && Rank(existing.Item, q.Format) <= Rank(s.Item, q.Format)) continue;
            byName[s.Name] = (s.Item, s.Score);
        }
        var ranked = byName.Values.OrderByDescending(v => v.Score)
            .ThenBy(v => v.Item.Name, Comparer<string>.Create(Text.LocalizedCaseInsensitiveCompare)).ToList();
        var top = ranked.Where(r => r.Score == best).ToList();
        var unique = top.Count == 1;
        var status = unique && best >= 70 && !q.IsPreset ? LESMatchStatus.Found : LESMatchStatus.Uncertain;
        return new LESMatch
        {
            Status = status, Item = top[0].Item, IsPreset = q.IsPreset,
            Alternatives = status == LESMatchStatus.Found ? Array.Empty<PluginItem>() : ranked.Take(8).Select(r => r.Item).ToList(),
        };
    }

    static int Score(string name, string q, int[] points)
    {
        if (q.Length == 0) return 0;
        if (Text.Equal(name, q)) return points[0];
        var (cn, cq) = (SearchMatcher.Compact(name), SearchMatcher.Compact(q));
        if (cq.Length > 0 && cn == cq) return points[1];
        if (Text.HasPrefix(name, q)) return points[2];
        if (Text.Contains(name, q) || (Text.Count(cq) >= 4 && Text.ContainsNfc(cn, cq))) return points[3];
        var words = Text.Split(q, ' ');
        if (words.Count > 1 && words.All(w => Text.Contains(name, w))) return points[4];
        return 0;
    }

    /// <summary>Lower is better: the hinted format first; without a hint Live's own devices, then VST3, AU, VST2, Max for Live.</summary>
    static int Rank(PluginItem item, LESFormat? hint)
    {
        var format = FormatOf(item);
        if (hint != null && format == hint) return -1;
        return format switch
        {
            null => 0,
            LESFormat.Vst3 => 1,
            LESFormat.Au => 2,
            LESFormat.Vst2 => 3,
            _ => 4,
        };
    }

    internal static LESFormat? FormatOf(PluginItem item)
    {
        if (item.Source == ItemSource.MaxForLive) return LESFormat.MaxForLive;
        if (item.Source != ItemSource.Plugins) return null;
        var f = item.Path.Count > 0 ? item.Path[0] : "";
        if (Text.Equal(f, "VST3")) return LESFormat.Vst3;
        if (Text.HasPrefix(f, "AU")) return LESFormat.Au;
        if (Text.Equal(f, "VST")) return LESFormat.Vst2;
        return null;
    }
}

// MARK: - Editable import preview

public sealed class ImportRow
{
    public Guid Id { get; }
    public string Display { get; set; }
    public string Query { get; }
    public LESMatch Match { get; set; }

    public ImportRow(Guid id, string display, string query, LESMatch match) { Id = id; Display = display; Query = query; Match = match; }
}

public sealed class ImportCategory
{
    public Guid Id { get; }
    public string Name { get; set; }
    public List<ImportRow> Rows { get; set; }
    /// <summary>Set: this becomes a folder inside that (top-level) category instead of a category of its own.</summary>
    public Guid? ParentID { get; set; }

    public ImportCategory(Guid id, string name, List<ImportRow> rows, Guid? parentID = null) { Id = id; Name = name; Rows = rows; ParentID = parentID; }
}

public enum ImportMode { Replace, Add }

/// <summary>The import preview the user edits before applying it (Swift value type: a class edited in place here).</summary>
public sealed class ImportDraft
{
    public readonly record struct DraftCounts(int Found = 0, int Uncertain = 0, int NotFound = 0);

    public List<ImportCategory> Categories { get; set; }

    public ImportDraft(List<ImportCategory>? categories = null) { Categories = categories ?? new(); }

    public static ImportDraft Make(string text, IReadOnlyList<PluginItem> items)
    {
        var matcher = new LESMatcher(items);
        var parsed = LESMenuParser.Parse(text);
        var ids = parsed.Select(_ => Guid.NewGuid()).ToList();
        return new ImportDraft(parsed.Select((les, index) =>
        {
            var seen = new HashSet<string>(Text.Canonical);
            var rows = new List<ImportRow>();
            foreach (var it in les.Items)
            {
                var match = matcher.Match(it.Display, it.Query);
                var key = match.Item?.Uri ?? "query:" + Text.Lower(it.Query);
                if (!seen.Add(key)) continue;
                rows.Add(new ImportRow(Guid.NewGuid(), it.Display, it.Query, match));
            }
            return new ImportCategory(ids[index], les.Name, rows, les.Parent is { } p ? ids[p] : null);
        }).ToList());
    }

    public DraftCounts Counts
    {
        get
        {
            var rows = Categories.SelectMany(c => c.Rows).ToList();
            return new DraftCounts(rows.Count(r => r.Match.Status == LESMatchStatus.Found),
                rows.Count(r => r.Match.Status == LESMatchStatus.Uncertain), rows.Count(r => r.Match.Status == LESMatchStatus.NotFound));
        }
    }

    int? IndexOf(Guid id)
    {
        var i = Categories.FindIndex(c => c.Id == id);
        return i < 0 ? null : i;
    }

    public void RemoveRow(Guid rowID, Guid categoryID)
    {
        if (IndexOf(categoryID) is { } c) Categories[c].Rows.RemoveAll(r => r.Id == rowID);
    }

    public void MoveRow(Guid categoryID, int from, int to)
    {
        if (IndexOf(categoryID) is not { } c) return;
        var rows = Categories[c].Rows;
        if (from < 0 || from >= rows.Count || to < 0 || to >= rows.Count) return;
        var row = rows[from];
        rows.RemoveAt(from);
        rows.Insert(to, row);
    }

    public void RenameCategory(Guid id, string name)
    {
        if (IndexOf(id) is { } c) Categories[c].Name = name;
    }

    /// <summary>Removes the category and the folders inside it.</summary>
    public void RemoveCategory(Guid id) => Categories.RemoveAll(c => c.Id == id || c.ParentID == id);

    /// <summary>Makes a category a folder inside <paramref name="parent"/> (a top-level category), or with null a category
    /// of its own. Categories that contain folders cannot become folders themselves.</summary>
    public void SetParent(Guid id, Guid? parent)
    {
        if (IndexOf(id) is not { } c || id == parent) return;
        if (parent is { } p)
        {
            if (IndexOf(p) is not { } pi || Categories[pi].ParentID != null || Categories.Any(x => x.ParentID == id)) return;
        }
        Categories[c].ParentID = parent;
    }

    public void MoveCategory(int from, int to)
    {
        if (from < 0 || from >= Categories.Count || to < 0 || to >= Categories.Count) return;
        var c = Categories[from];
        Categories.RemoveAt(from);
        Categories.Insert(to, c);
    }

    /// <summary>Appends the source's rows to the target (skipping plugins already there) and removes the source.</summary>
    public void MergeCategory(Guid sourceID, Guid targetID)
    {
        if (sourceID == targetID || IndexOf(sourceID) is not { } s || IndexOf(targetID) is not { } t) return;
        var existing = new HashSet<string>(Categories[t].Rows.Where(r => r.Match.Item != null).Select(r => r.Match.Item!.Uri), Text.Canonical);
        Categories[t].Rows.AddRange(Categories[s].Rows.Where(r => r.Match.Item is not { } item || !existing.Contains(item.Uri)));
        foreach (var c in Categories.Where(c => c.ParentID == sourceID)) c.ParentID = targetID;
        Categories.RemoveAll(c => c.Id == sourceID);
    }

    public void SetMatch(PluginItem item, Guid rowID, Guid categoryID)
    {
        if (IndexOf(categoryID) is not { } c || Categories[c].Rows.FirstOrDefault(r => r.Id == rowID) is not { } row) return;
        row.Match = LESMatch.Manual(item);
    }
}

public sealed partial record LauncherConfig
{
    /// <summary>Pushes an import preview into the menu. Replace swaps every category except Favorites; Add merges into
    /// same-named categories and appends new ones. Rows without a plugin are skipped. The LES display name is kept as
    /// display name when it differs from the plugin's name. Subfolder categories (ParentID) become folders inside their
    /// parent's category.</summary>
    public void Apply(ImportDraft draft, ImportMode mode)
    {
        if (mode == ImportMode.Replace) Categories.RemoveAll(c => !c.IsFavorites);
        var target = new Dictionary<Guid, Guid>();   // draft category → config category
        var draftIDs = draft.Categories.Select(c => c.Id).ToHashSet();
        foreach (var imported in draft.Categories.Where(c => c.ParentID is not { } p || !draftIDs.Contains(p)))
        {
            var existing = mode == ImportMode.Add
                ? Categories.FirstOrDefault(c => !c.IsFavorites && Text.LocalizedCaseInsensitiveCompare(c.Name, imported.Name) == 0)
                : null;
            target[imported.Id] = existing?.Id ?? AddCategory(imported.Name);
        }
        foreach (var imported in draft.Categories)
        {
            if (target.TryGetValue(imported.Id, out var categoryID))
            {
                AddRows(imported.Rows, categoryID, null);
            }
            else if (imported.ParentID is { } parent && target.TryGetValue(parent, out var parentCategory))
            {
                var folder = Categories.FirstOrDefault(c => c.Id == parentCategory)?.Entries
                    .FirstOrDefault(e => e.IsFolder && Text.LocalizedCaseInsensitiveCompare(e.Name, imported.Name) == 0)?.Id
                    ?? AddFolder(imported.Name, parentCategory);
                AddRows(imported.Rows, parentCategory, folder);
            }
        }
    }

    void AddRows(List<ImportRow> rows, Guid categoryID, Guid? folder)
    {
        foreach (var row in rows)
        {
            if (row.Match.Item is not { } item || row.Match.Status == LESMatchStatus.NotFound) continue;
            AddEntry(item, categoryID, folder);
            if (Text.Equal(LESMatcher.Normalize(row.Display), LESMatcher.Normalize(item.Name))) continue;
            var container = (folder is { } f ? FindEntry(f, categoryID)?.Children : null)
                ?? Categories.FirstOrDefault(c => c.Id == categoryID)?.Entries ?? new List<Entry>();
            if (container.LastOrDefault(e => Text.Equal(e.Uri, item.Uri)) is not { DisplayName: null } entry) continue;
            SetDisplayName(row.Display, entry.Id, categoryID);
        }
    }

    /// <summary>Replaces the menu (categories only — shortcuts and language stay) with a copy of
    /// <paramref name="restored"/>. Guarantees one Favorites category at index 0.</summary>
    public void RestoreMenu(IReadOnlyList<Category> restored)
    {
        var cats = Json.SwiftJson.Clone(restored.ToList());
        var f = cats.FindIndex(c => c.IsFavorites);
        if (f >= 0)
        {
            var fav = cats[f];
            cats.RemoveAt(f);
            foreach (var c in cats) c.IsFavorites = false;
            cats.Insert(0, fav);
        }
        else
        {
            cats.Insert(0, new Category("Favorites", isFavorites: true));
        }
        Categories = cats;
    }
}
