using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>One row of the panel or the quick search.</summary>
public sealed record PanelRow
{
    public string Uri { get; init; } = "";
    public string Name { get; init; } = "";
    public ItemSource Source { get; init; }
    public IReadOnlyList<string> Path { get; init; } = Array.Empty<string>();
    public string IconID { get; init; } = "";
    public string Title { get; init; } = "";
    public bool IsAvailable { get; init; }
    /// <summary>Set for folder rows: activating them opens the folder instead of inserting.</summary>
    public Guid? FolderID { get; init; }
    public int ChildCount { get; init; }
    /// <summary>A search hit from the whole plugin list, shown after the category's own hits.</summary>
    public bool IsGlobal { get; init; }
    /// <summary>Counts inserts per plugin (shared by its formats).</summary>
    public string UsageKey { get; init; } = "";
    /// <summary>Color label (<c>ColorPalette</c> id), already resolved against the color rules.</summary>
    public string? ColorID { get; init; }
    /// <summary>A chain: the URIs to insert, in order.</summary>
    public IReadOnlyList<string>? Chain { get; init; }
    /// <summary>A Live action to run instead of inserting.</summary>
    public LiveAction? Action { get; init; }
    /// <summary>Not yet filed or inserted, first seen recently.</summary>
    public bool IsNew { get; init; }

    /// <summary>Row for a chain or Live action entry; null for plugins and folders.</summary>
    internal static PanelRow? Special(Entry e, SearchIndex index, string? colorID)
    {
        if (e.Action != null)
            return new PanelRow
            {
                Uri = "", Name = e.Name, Source = e.Source, IconID = e.IconID, Title = e.Title, IsAvailable = true,
                UsageKey = "action|" + Text.Lower(e.Title), ColorID = colorID, Action = e.Action,
            };
        if (e.Chain is { } steps)
        {
            var uris = steps.Select(s => index.Resolver.Resolve(new Entry(s))?.Uri).ToList();
            return new PanelRow
            {
                Uri = "", Name = e.Name, Source = e.Source, IconID = e.IconID, Title = e.Title,
                IsAvailable = uris.Count > 0 && !uris.Contains(null), UsageKey = "chain|" + Text.Lower(e.Title),
                ColorID = colorID, Chain = uris.OfType<string>().ToList(),
            };
        }
        return null;
    }

    public bool Equals(PanelRow? o) => o is not null && Uri == o.Uri && Name == o.Name && Source == o.Source &&
        Path.SequenceEqual(o.Path) && IconID == o.IconID && Title == o.Title && IsAvailable == o.IsAvailable &&
        FolderID == o.FolderID && ChildCount == o.ChildCount && IsGlobal == o.IsGlobal && UsageKey == o.UsageKey &&
        ColorID == o.ColorID && (Chain is null ? o.Chain is null : o.Chain is not null && Chain.SequenceEqual(o.Chain)) &&
        Equals(Action, o.Action) && IsNew == o.IsNew;

    public override int GetHashCode() => HashCode.Combine(Uri, Title, UsageKey);
}

public enum PanelKeyKind { Digit, Character, Backspace, Left, Right, Tab, Up, Down, ReturnKey, Escape, SelectAll, DeleteWord, DeleteToStart }

/// <summary>A key the open panel / quick search reacts to (Swift <c>PanelKey</c>). <see cref="Character"/> is one Character (text element).</summary>
public readonly record struct PanelKey(PanelKeyKind Kind, int Digit = 0, string Character = "")
{
    public static PanelKey OfDigit(int d) => new(PanelKeyKind.Digit, d);
    public static PanelKey OfCharacter(string c) => new(PanelKeyKind.Character, 0, c);
    public static PanelKey Of(PanelKeyKind kind) => new(kind);
}

public enum PanelActionKind { None, Close, Insert }

/// <summary>What a key press asks the window to do (Swift <c>PanelAction</c>).</summary>
public sealed record PanelAction(PanelActionKind Kind, PanelRow? Row = null)
{
    public static readonly PanelAction None = new(PanelActionKind.None);
    public static readonly PanelAction Close = new(PanelActionKind.Close);
    public static PanelAction Insert(PanelRow row) => new(PanelActionKind.Insert, row);
}

/// <summary>One tab per category. (An "All" tab drew every installed plugin at once and froze the panel;
/// typing searches all plugins instead.)</summary>
public abstract record PanelTab
{
    public sealed record Category(Guid Id, string Name) : PanelTab;
}

/// <summary>The open panel: tabs, the typed filter, the highlighted row, the open folder and the rows it shows.</summary>
public sealed class PanelState
{
    public const int MaxGlobalResults = 50;

    readonly LauncherConfig config;
    /// <summary>Shared, prebuilt view of the plugin list (see <see cref="SearchIndex"/>).</summary>
    readonly SearchIndex search;
    readonly Dictionary<string, int> usage;
    TextInput input = new();
    int selectedTab;
    Guid? openFolderID;

    public IReadOnlyList<PanelTab> Tabs { get; }
    public string Filter => input.Text;
    /// <summary>Select-all selected the whole filter (drawn highlighted; the next key replaces it).</summary>
    public bool IsFilterSelected => input.IsAllSelected;
    public int? Highlighted { get; private set; }
    /// <summary>What the panel shows (see <see cref="ComputeRows"/>). Kept, not recomputed on every read: with a search
    /// each computation ranks the whole plugin list.</summary>
    public IReadOnlyList<PanelRow> Rows { get; private set; }
    /// <summary>The panel's page on show and how many pads a page has: digit keys 1–9 pick from its first nine.</summary>
    public int Page { get; set; }
    public int PageSize { get; set; } = 9;

    public int SelectedTab
    {
        get => selectedTab;
        private set { if (value != selectedTab) { selectedTab = value; RefreshRows(); } }
    }

    /// <summary>The folder shown instead of the category's top level.</summary>
    public Guid? OpenFolderID
    {
        get => openFolderID;
        private set { if (value != openFolderID) { openFolderID = value; RefreshRows(); } }
    }

    public PanelState(LauncherConfig config, SearchIndex index, int selectedTab = 0, IReadOnlyDictionary<string, int>? usage = null)
    {
        // Swift's dictionary finds canonically equal keys.
        this.usage = new Dictionary<string, int>((usage ?? new Dictionary<string, int>()).GroupBy(p => p.Key, Text.Canonical)
            .Select(g => g.Last()), Text.Canonical);
        // A snapshot, as Swift copies the config: later edits to the app's config never reach an open panel.
        this.config = SwiftJson.Clone(config);
        search = index;
        Tabs = this.config.Categories.Select(c => (PanelTab)new PanelTab.Category(c.Id, c.Name)).ToList();
        this.selectedTab = Math.Min(Math.Max(selectedTab, 0), Tabs.Count - 1);
        Rows = ComputeRows();
    }

    /// <summary>Builds the index on the spot (tests, one-off use).</summary>
    public PanelState(LauncherConfig config, IReadOnlyList<PluginItem> items, int selectedTab = 0, IReadOnlyDictionary<string, int>? usage = null)
        : this(config, new SearchIndex(items, config), selectedTab, usage) { }

    void RefreshRows() => Rows = ComputeRows();

    /// <summary>Replaces the filter text; the rows follow when the text changes.</summary>
    void SetInput(TextInput next)
    {
        var before = input.Text;
        input = next;
        if (!Text.Equal(input.Text, before)) RefreshRows();
    }

    /// <summary>Without a filter: the category's top level (plugins and folders) or the open folder's plugins, in the
    /// user's order. With a filter: the category's hits (reaching into folders), then hits from all plugins —
    /// each ranked by match quality, then by how often the plugin was inserted.</summary>
    List<PanelRow> ComputeRows()
    {
        var entries = CategoryEntries;
        List<PanelRow> candidates;
        if (openFolderID is { } folderID)
            candidates = (entries.FirstOrDefault(e => e.Id == folderID)?.Children ?? new()).Select(Row).ToList();
        else
            candidates = Filter.Length == 0 ? entries.Select(Row).ToList()
                : entries.SelectMany(e => e.IsFolder ? new[] { Row(e) }.Concat((e.Children ?? new()).Select(Row)) : new[] { Row(e) }).ToList();
        if (Filter.Length == 0) return candidates;
        var query = new SearchMatcher.Prepared(Filter);
        var tags = SearchVocabulary.Icons(Filter);
        var rule = SearchTuning.Rule(Filter, config.SearchRules);
        var ranked = candidates
            .Select((r, i) => (Row: r, Score: SearchMatcher.Score(new SearchMatcher.Prepared(r.Title), query, r.IconID, tags), Index: i))
            .Where(x => x.Score != null)
            .OrderByDescending(x => x.Score!.Value)
            .ThenByDescending(x => Uses(x.Row))
            .ThenByDescending(x => Popularity.Score(x.Row.Title))
            .ThenBy(x => x.Index)
            .Select(x => x.Row)
            .ToList();
        // The user's search rules: hidden results go, pinned ones lead (in the category part and in "all plugins").
        var local = SearchTuning.Apply(ranked, r => r.UsageKey, rule);
        var excluded = new HashSet<string>(local.Select(r => r.UsageKey), Text.Canonical);
        if (rule != null) excluded.UnionWith(rule.Hidden);
        var global = SearchTuning.Apply(GlobalMatches(excluded, MaxGlobalResults), r => r.UsageKey, rule,
            key => excluded.Contains(key) ? null : search.GlobalRow(key));
        return local.Concat(global).ToList();
    }

    int Uses(PanelRow row) => usage.TryGetValue(row.UsageKey, out var n) ? n : 0;

    /// <summary>Hits from every installed plugin (one row per plugin), plugins already shown left out.</summary>
    List<PanelRow> GlobalMatches(HashSet<string> shown, int? limit)
    {
        var query = new SearchMatcher.Prepared(Filter);
        var tags = SearchVocabulary.Icons(Filter);
        var hits = new List<(PanelRow Row, int Score, int Popularity)>();
        for (var i = 0; i < search.GlobalRows.Count; i++)
        {
            var r = search.GlobalRows[i];
            if (shown.Contains(r.UsageKey)) continue;
            if (SearchMatcher.Score(search.GlobalPrepared[i], query, r.IconID, tags) is { } score)
                hits.Add((r, score, search.GlobalPopularity[i]));
        }
        // Stable: alphabetical last.
        var sorted = hits.OrderByDescending(h => h.Score).ThenByDescending(h => Uses(h.Row)).ThenByDescending(h => h.Popularity)
            .Select(h => h.Row);
        return (limit is { } n ? sorted.Take(n) : sorted).ToList();
    }

    /// <summary>The plugins of a folder in the current category, for the side list that opens on hover.</summary>
    public List<PanelRow> FolderRows(Guid folderID) =>
        (CategoryEntries.FirstOrDefault(e => e.Id == folderID)?.Children ?? new()).Select(Row).ToList();

    public string? OpenFolderName => openFolderID is { } id ? CategoryEntries.FirstOrDefault(e => e.Id == id)?.Title : null;

    List<Entry> CategoryEntries
    {
        get
        {
            if (Tabs[selectedTab] is not PanelTab.Category tab) return new();
            return config.Categories.FirstOrDefault(c => c.Id == tab.Id)?.Entries ?? new();
        }
    }

    PanelRow Row(Entry e)
    {
        if (e.IsFolder)
            return new PanelRow
            {
                Uri = "", Name = e.Name, Source = e.Source, IconID = e.IconID, Title = e.Title, IsAvailable = true,
                FolderID = e.Id, ChildCount = e.Children?.Count ?? 0, UsageKey = "folder:" + e.Id.ToString().ToUpperInvariant(),
                ColorID = config.ColorID(e),
            };
        if (PanelRow.Special(e, search, config.ColorID(e)) is { } special) return special;
        var resolved = search.Resolver.Resolve(e);
        var uri = resolved?.Uri ?? e.Uri;
        return new PanelRow
        {
            Uri = uri, Name = e.Name, Source = e.Source, Path = resolved?.Path ?? e.Path.ToArray(), IconID = e.IconID, Title = e.Title,
            IsAvailable = resolved != null, UsageKey = search.UsageKey.TryGetValue(uri, out var k) ? k : uri,
            ColorID = config.ColorID(e),
        };
    }

    public void SelectTab(int index)
    {
        SelectedTab = (index % Tabs.Count + Tabs.Count) % Tabs.Count;
        SetInput(new TextInput());
        Highlighted = null;
        OpenFolderID = null;
    }

    public void OpenFolder(Guid id)
    {
        OpenFolderID = id;
        SetInput(new TextInput());
        Highlighted = null;
    }

    public void CloseFolder()
    {
        OpenFolderID = null;
        SetInput(new TextInput());
        Highlighted = null;
    }

    public PanelAction Handle(PanelKey key)
    {
        switch (key.Kind)
        {
            case PanelKeyKind.Digit when Filter.Length == 0:
                if (key.Digit < 1 || key.Digit > 9 || key.Digit > PageSize) return PanelAction.None;
                return Insert(Page * PageSize + key.Digit - 1);
            case PanelKeyKind.Backspace when Filter.Length == 0 && openFolderID != null:
                CloseFolder();
                return PanelAction.None;
            case PanelKeyKind.Left:
                SelectTab(SelectedTab - 1);
                break;
            case PanelKeyKind.Right:
            case PanelKeyKind.Tab:
                SelectTab(SelectedTab + 1);
                break;
            case PanelKeyKind.Down:
                input.Deselect();
                if (Rows.Count == 0) return PanelAction.None;
                Highlighted = Highlighted is { } d ? Math.Min(d + 1, Rows.Count - 1) : 0;
                break;
            case PanelKeyKind.Up:
                input.Deselect();
                if (Rows.Count == 0) return PanelAction.None;
                Highlighted = Highlighted is { } u ? Math.Max(u - 1, 0) : 0;
                break;
            case PanelKeyKind.ReturnKey:
                if (Highlighted is { } h) return Insert(h);
                return Filter.Length == 0 ? PanelAction.None : Insert(0);
            case PanelKeyKind.Escape:
                if (openFolderID != null) { CloseFolder(); return PanelAction.None; }
                return PanelAction.Close;
            default:
                var before = input.Text;
                var handled = input.Apply(key);
                if (!Text.Equal(input.Text, before)) RefreshRows();
                if (handled) Highlighted = null;
                break;
        }
        return PanelAction.None;
    }

    /// <summary>Folder rows open; plugin rows insert.</summary>
    PanelAction Insert(int index)
    {
        var rows = Rows;
        if (index < 0 || index >= rows.Count || !rows[index].IsAvailable) return PanelAction.None;
        if (rows[index].FolderID is { } folder)
        {
            OpenFolder(folder);
            return PanelAction.None;
        }
        return PanelAction.Insert(rows[index]);
    }
}
