using System.Runtime.Serialization;
using System.Text.Json;
using System.Text.Json.Serialization;
using HyneAsm.Core.Json;

namespace HyneAsm.Core;

public enum ItemSource
{
    Plugins,
    Instruments,
    [EnumMember(Value = "audio_effects")] AudioEffects,
    [EnumMember(Value = "midi_effects")] MidiEffects,
    [EnumMember(Value = "max_for_live")] MaxForLive,
    /// <summary>The user's own presets (.adg, .vstpreset …) from Live's User Library and from the folders under "Places".</summary>
    [EnumMember(Value = "user_library")] UserLibrary,
    [EnumMember(Value = "user_folders")] UserFolders,
}

public static class ItemSourceExtensions
{
    public static bool IsPreset(this ItemSource source) => source is ItemSource.UserLibrary or ItemSource.UserFolders;
}

/// <summary>A plugin, device or preset from Live's browser. Immutable (a Swift value): one instance is shared by the
/// catalog, the config, the search index and the panel across threads; change one with <c>with</c>.</summary>
public sealed record PluginItem : IJsonOnDeserialized
{
    readonly IReadOnlyList<string> path = Array.Empty<string>();

    [JsonRequired] public string Uri { get; init; } = "";
    [JsonRequired] public string Name { get; init; } = "";
    [JsonRequired] public ItemSource Source { get; init; }
    /// <summary>A read-only copy of the list it was given.</summary>
    [JsonRequired] public IReadOnlyList<string> Path { get => path; init => path = ValueEquality.ReadOnlyCopy(value); }
    /// <summary>Presets only: file extension without the dot ("adg", "vstpreset"). Null for devices and plugins.</summary>
    public string? Format { get; init; }

    public PluginItem() { }

    public PluginItem(string uri, string name, ItemSource source, IReadOnlyList<string> path, string? format = null)
    {
        Uri = uri; Name = name; Source = source; Path = path; Format = format;
    }

    void IJsonOnDeserialized.OnDeserialized()
    {
        SwiftJson.RejectNull(nameof(PluginItem), Uri, Name, Path);
        SwiftJson.RejectNullElements(nameof(PluginItem), Path);
    }

    public bool Equals(PluginItem? other) => other is not null && Uri == other.Uri && Name == other.Name &&
        Source == other.Source && ValueEquality.Lists(Path, other.Path) && Format == other.Format;

    public override int GetHashCode() => HashCode.Combine(Uri, Name, Source, ValueEquality.Hash(Path), Format);
}

public sealed record Entry : IJsonOnDeserialized
{
    [JsonRequired] public Guid Id { get; set; }
    [JsonRequired] public string Uri { get; set; } = "";
    [JsonRequired] public string Name { get; set; } = "";
    [JsonRequired] public ItemSource Source { get; set; }
    [JsonRequired] public List<string> Path { get; set; } = new();
    [JsonRequired] public string IconID { get; set; } = "";
    public string? DisplayName { get; set; }
    /// <summary>Non-null makes this entry a folder of plugins (one level deep; folders hold no folders).</summary>
    public List<Entry>? Children { get; set; }
    /// <summary>Own color label (<c>ColorPalette</c> id); null = follow the color rules.</summary>
    public string? ColorID { get; set; }
    /// <summary>A chain: these items are inserted one after the other.</summary>
    public List<PluginItem>? Chain { get; set; }
    /// <summary>A Live action ("New MIDI Track", "Tempo 128") instead of a plugin.</summary>
    public LiveAction? Action { get; set; }

    [JsonIgnore] public string Title => DisplayName ?? Name;
    [JsonIgnore] public bool IsFolder => Children != null;

    /// <summary>For the JSON reader.</summary>
    public Entry() { }

    /// <summary>Swift <c>init(item:iconID:)</c>.</summary>
    public Entry(PluginItem item, string iconID = IconCatalog.DefaultID)
    {
        Id = Guid.NewGuid(); Uri = item.Uri; Name = item.Name; Source = item.Source; Path = item.Path.ToList(); IconID = iconID;
    }

    /// <summary>Swift <c>init(action:)</c>.</summary>
    public Entry(LiveAction action)
    {
        Id = Guid.NewGuid(); Uri = ""; Name = action.Title; Source = ItemSource.Plugins; Path = new();
        IconID = action.Kind.IconID(); Action = action;
    }

    /// <summary>Swift <c>init(folderNamed:)</c>: an empty folder.</summary>
    public static Entry FolderNamed(string name) => new()
    {
        Id = Guid.NewGuid(), Uri = "", Name = name, Source = ItemSource.Plugins, Path = new(), IconID = IconCatalog.FolderID,
        Children = new(),
    };

    /// <summary>Swift <c>init(chainNamed:steps:iconID:)</c>.</summary>
    public static Entry ChainNamed(string name, List<PluginItem> steps, string iconID = "rack") => new()
    {
        Id = Guid.NewGuid(), Uri = "", Name = name, Source = ItemSource.Plugins, Path = new(), IconID = iconID, Chain = steps,
    };

    void IJsonOnDeserialized.OnDeserialized()
    {
        SwiftJson.RejectNull(nameof(Entry), Uri, Name, Path, IconID);
        SwiftJson.RejectNullElements(nameof(Entry), Path, Children, Chain);
    }

    public bool Equals(Entry? o) => o is not null && Id == o.Id && Uri == o.Uri && Name == o.Name && Source == o.Source &&
        ValueEquality.Lists(Path, o.Path) && IconID == o.IconID && DisplayName == o.DisplayName &&
        ValueEquality.Lists(Children, o.Children) && ColorID == o.ColorID && ValueEquality.Lists(Chain, o.Chain) &&
        Equals(Action, o.Action);

    public override int GetHashCode()
    {
        var h = new HashCode();
        h.Add(Id); h.Add(Uri); h.Add(Name); h.Add(Source); h.Add(ValueEquality.Hash(Path)); h.Add(IconID);
        h.Add(DisplayName); h.Add(ValueEquality.Hash(Children)); h.Add(ColorID); h.Add(ValueEquality.Hash(Chain)); h.Add(Action);
        return h.ToHashCode();
    }
}

public sealed record Category : IJsonOnDeserialized
{
    [JsonRequired] public Guid Id { get; set; }
    [JsonRequired] public string Name { get; set; } = "";
    [JsonRequired] public bool IsFavorites { get; set; }
    [JsonRequired] public List<Entry> Entries { get; set; } = new();

    public Category() { }

    public Category(string name, bool isFavorites = false, List<Entry>? entries = null)
    {
        Id = Guid.NewGuid(); Name = name; IsFavorites = isFavorites; Entries = entries ?? new();
    }

    void IJsonOnDeserialized.OnDeserialized()
    {
        SwiftJson.RejectNull(nameof(Category), Name, Entries);
        SwiftJson.RejectNullElements(nameof(Category), Entries);
    }
}

/// <summary>Swift <c>ModifierSet</c> option set, stored as its UInt8 raw value.</summary>
[Flags]
public enum ModifierSet : byte
{
    None = 0,
    Cmd = 1 << 0,
    Alt = 1 << 1,
    Shift = 1 << 2,
    Ctrl = 1 << 3,
}

/// <summary>A key in macOS virtual key codes with Mac modifiers (the file format on both platforms).</summary>
public sealed record KeyCombo
{
    [JsonRequired] public ushort KeyCode { get; init; }
    [JsonRequired] public ModifierSet Modifiers { get; init; }

    public KeyCombo() { }

    public KeyCombo(ushort keyCode, ModifierSet modifiers) { KeyCode = keyCode; Modifiers = modifiers; }
}

public sealed record ShortcutSettings : IJsonOnDeserialized
{
    /// <summary>null = disabled</summary>
    public KeyCombo? CloseFocused { get; set; }
    /// <summary>empty = disabled</summary>
    public List<KeyCombo> CloseAll { get; set; } = new();
    /// <summary>Opens the quick search window; empty = disabled.</summary>
    public List<KeyCombo> QuickSearch { get; set; } = DefaultQuickSearch();
    /// <summary>Switches to the next profile; empty = disabled (the default).</summary>
    public List<KeyCombo> NextProfile { get; set; } = new();

    static List<KeyCombo> DefaultQuickSearch() => new() { new KeyCombo(49, ModifierSet.Ctrl) };

    /// <summary>A fresh copy of the defaults on every call.</summary>
    public static ShortcutSettings Default => new(
        new KeyCombo(13, ModifierSet.Cmd),
        new() { new KeyCombo(13, ModifierSet.Cmd | ModifierSet.Ctrl), new KeyCombo(53, ModifierSet.Cmd) });

    public ShortcutSettings() { }

    public ShortcutSettings(KeyCombo? closeFocused, List<KeyCombo> closeAll, List<KeyCombo>? quickSearch = null)
    {
        CloseFocused = closeFocused;
        CloseAll = closeAll;
        QuickSearch = quickSearch ?? DefaultQuickSearch();
    }

    /// <summary>Shortcuts added later get their default in older config files (null counts as missing, as in Swift).</summary>
    void IJsonOnDeserialized.OnDeserialized()
    {
        CloseAll ??= new();
        QuickSearch ??= DefaultQuickSearch();
        NextProfile ??= new();
        SwiftJson.RejectNullElements(nameof(ShortcutSettings), CloseAll, QuickSearch, NextProfile);
    }

    public bool Equals(ShortcutSettings? o) => o is not null && Equals(CloseFocused, o.CloseFocused) &&
        ValueEquality.Lists(CloseAll, o.CloseAll) && ValueEquality.Lists(QuickSearch, o.QuickSearch) &&
        ValueEquality.Lists(NextProfile, o.NextProfile);

    public override int GetHashCode() => HashCode.Combine(CloseFocused, ValueEquality.Hash(CloseAll),
        ValueEquality.Hash(QuickSearch), ValueEquality.Hash(NextProfile));
}

/// <summary>The whole config.json. Property order = Swift declaration order (the compact encoding's key order).</summary>
public sealed partial record LauncherConfig
{
    public int Version { get; set; }
    public List<Category> Categories { get; set; } = new();
    public ShortcutSettings Shortcuts { get; set; } = ShortcutSettings.Default;
    public PanelKeyBindings PanelKeys { get; set; } = PanelKeyBindings.Default;
    /// <summary>null = follow the system language</summary>
    public Language? Language { get; set; }
    /// <summary>Color rules by <c>ColorRule.key</c> (Live devices, a manufacturer) → <c>ColorPalette</c> id.</summary>
    public Dictionary<string, string> ColorRules { get; set; } = new();
    /// <summary>Pinned / hidden search results per search term.</summary>
    public List<SearchRule> SearchRules { get; set; } = new();
    /// <summary>Key combinations that insert a single plugin, rack or preset.</summary>
    public List<ItemShortcut> ItemShortcuts { get; set; } = new();
    /// <summary>Look of the app's windows.</summary>
    public AppTheme Theme { get; set; } = AppTheme.Original;
    /// <summary>Where inserted items land and on which tracks.</summary>
    public InsertOptions Insert { get; set; } = InsertOptions.Default;
    /// <summary>Stats page: list panel entries that are hardly used (can be switched off).</summary>
    public bool ShowRarelyUsed { get; set; } = true;
    /// <summary>Entries the user chose to keep although they are rarely used.</summary>
    public List<Guid> KeptEntries { get; set; } = new();
    /// <summary>Local HTTP endpoint for Stream Deck &amp; co. (127.0.0.1 only); off unless switched on.</summary>
    public bool StreamDeckEnabled { get; set; }
    /// <summary>Width of a panel column and height of an entry (resize grip in the panel).</summary>
    public PanelSize PanelSize { get; set; } = PanelSize.Default;
    /// <summary>Pads per page of the panel (columns × rows).</summary>
    public PanelGridSize PanelGrid { get; set; } = PanelGridSize.Default;
    /// <summary>Pads in a grid or rows of a list, and the list's size.</summary>
    public PanelStyle PanelStyle { get; set; } = PanelStyle.Grid;
    public PanelListSize PanelList { get; set; } = PanelListSize.Default;
    /// <summary>Where each entry sits on a page, from the style and its size.</summary>
    [JsonIgnore] public PanelPage PanelPage => new(PanelStyle, PanelGrid, PanelList);
    /// <summary>Categories as tabs on top of the panel or as a column on its left.</summary>
    public CategoryPlacement CategoryPlacement { get; set; } = CategoryPlacement.Top;
    /// <summary>The welcome window was finished or skipped.</summary>
    public bool OnboardingDone { get; set; }
    /// <summary>Secret part of every Stream Deck link, so a web page can't trigger commands on the local endpoint.</summary>
    public string StreamDeckToken { get; set; } = NewToken();
    /// <summary>All profiles (named menus); the active one's menu is <see cref="Categories"/>.</summary>
    public List<Profile> Profiles { get; set; } = new();
    public Guid ActiveProfileID { get; set; } = Guid.NewGuid();

    public const int CurrentVersion = 4;

    /// <summary>For the JSON reader, which calls <see cref="EnsureProfile"/> itself.</summary>
    LauncherConfig() { }

    public LauncherConfig(int version, List<Category> categories, ShortcutSettings shortcuts, PanelKeyBindings? panelKeys = null)
    {
        Version = version;
        Categories = categories;
        Shortcuts = shortcuts;
        PanelKeys = panelKeys ?? PanelKeyBindings.Default;
        EnsureProfile();
    }

    public static LauncherConfig MakeDefault() => new(
        CurrentVersion,
        new() { new Category("Favorites", isFavorites: true), new Category("Instruments"), new Category("Effects") },
        ShortcutSettings.Default);

    /// <summary>Swift's <c>init(from:)</c>: fields added later decode with defaults, so older config files keep loading.</summary>
    internal sealed class Reader : JsonConverter<LauncherConfig>
    {
        public override LauncherConfig Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions o)
        {
            using var doc = JsonDocument.ParseValue(ref reader);
            var c = doc.RootElement;
            if (c.ValueKind != JsonValueKind.Object) throw new JsonException("LauncherConfig must be an object");
            var config = new LauncherConfig
            {
                Version = SwiftJson.Required<int>(c, "version", o),
                Categories = SwiftJson.Required<List<Category>>(c, "categories", o),
                Shortcuts = SwiftJson.IfPresent(c, "shortcuts", o, () => ShortcutSettings.Default),
                PanelKeys = SwiftJson.IfPresent(c, "panelKeys", o, () => PanelKeyBindings.Default),
                Language = SwiftJson.IfPresent<Language?>(c, "language", o, () => null),
                ColorRules = SwiftJson.IfPresent(c, "colorRules", o, () => new Dictionary<string, string>()),
                SearchRules = SwiftJson.IfPresent(c, "searchRules", o, () => new List<SearchRule>()),
                ItemShortcuts = SwiftJson.IfPresent(c, "itemShortcuts", o, () => new List<ItemShortcut>()),
                Theme = SwiftJson.Lenient(c, "theme", o, () => AppTheme.Original),
                Insert = SwiftJson.Lenient(c, "insert", o, () => InsertOptions.Default),
                ShowRarelyUsed = SwiftJson.IfPresent(c, "showRarelyUsed", o, () => true),
                KeptEntries = SwiftJson.IfPresent(c, "keptEntries", o, () => new List<Guid>()),
                StreamDeckEnabled = SwiftJson.IfPresent(c, "streamDeckEnabled", o, () => false),
                PanelSize = SwiftJson.Lenient(c, "panelSize", o, () => PanelSize.Default),
                PanelGrid = SwiftJson.Lenient(c, "panelGrid", o, () => PanelGridSize.Default),
                CategoryPlacement = SwiftJson.Lenient(c, "categoryPlacement", o, () => CategoryPlacement.Top),
                PanelStyle = SwiftJson.Lenient(c, "panelStyle", o, () => PanelStyle.Grid),
                PanelList = SwiftJson.Lenient(c, "panelList", o, () => PanelListSize.Default),
                OnboardingDone = SwiftJson.IfPresent(c, "onboardingDone", o, () => false),
                StreamDeckToken = SwiftJson.IfPresent(c, "streamDeckToken", o, NewToken),
                Profiles = SwiftJson.IfPresent(c, "profiles", o, () => new List<Profile>()),
                ActiveProfileID = SwiftJson.IfPresent(c, "activeProfileID", o, Guid.NewGuid),
            };
            SwiftJson.RejectNullElements(nameof(LauncherConfig), config.Categories, config.ColorRules.Values,
                config.SearchRules, config.ItemShortcuts, config.Profiles);
            config.EnsureProfile();
            return config;
        }

        /// <summary>Writing is the plain member-wise encoding (Swift's synthesized <c>encode(to:)</c>).</summary>
        public override void Write(Utf8JsonWriter writer, LauncherConfig value, JsonSerializerOptions o) =>
            JsonSerializer.Serialize(writer, value, SwiftJson.PlainOptions);
    }
}

/// <summary>Value equality for the list-holding records, as Swift's synthesized Equatable/Hashable compare arrays.</summary>
internal static class ValueEquality
{
    /// <summary>A read-only copy for an immutable value's list; null stays null (so the JSON reader can reject it).</summary>
    public static IReadOnlyList<T> ReadOnlyCopy<T>(IEnumerable<T>? list) => list is null ? null! : Array.AsReadOnly(list.ToArray());

    public static bool Lists<T>(IReadOnlyList<T>? a, IReadOnlyList<T>? b) => a is null ? b is null : b is not null && a.SequenceEqual(b);

    public static int Hash<T>(IReadOnlyList<T>? list)
    {
        if (list is null) return 0;
        var h = new HashCode();
        foreach (var x in list) h.Add(x);
        return h.ToHashCode();
    }
}
