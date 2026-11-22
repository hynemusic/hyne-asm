namespace HyneAsm.Core;

/// <summary>One row of the panel or the quick search. (Only the row is here so far; the panel state comes with the panel.)</summary>
public sealed record PanelRow
{
    public string Uri { get; init; } = "";
    public string Name { get; init; } = "";
    public ItemSource Source { get; init; }
    public IReadOnlyList<string> Path { get; init; } = Array.Empty<string>();
    public string IconID { get; set; } = "";
    public string Title { get; init; } = "";
    public bool IsAvailable { get; init; }
    /// <summary>Set for folder rows: activating them opens the folder instead of inserting.</summary>
    public Guid? FolderID { get; set; }
    public int ChildCount { get; set; }
    /// <summary>A search hit from the whole plugin list, shown after the category's own hits.</summary>
    public bool IsGlobal { get; set; }
    /// <summary>Counts inserts per plugin (shared by its formats).</summary>
    public string UsageKey { get; set; } = "";
    /// <summary>Color label (<c>ColorPalette</c> id), already resolved against the color rules.</summary>
    public string? ColorID { get; set; }
    /// <summary>A chain: the URIs to insert, in order.</summary>
    public IReadOnlyList<string>? Chain { get; set; }
    /// <summary>A Live action to run instead of inserting.</summary>
    public LiveAction? Action { get; set; }
    /// <summary>Not yet filed or inserted, first seen recently.</summary>
    public bool IsNew { get; set; }

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
