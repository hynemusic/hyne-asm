using System.Text.Json;
using System.Text.Json.Serialization;
using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>A whole menu (categories with order, icons and display names) as a shareable file (<c>.hmlmenu</c>).</summary>
public sealed class MenuDocument : IJsonOnDeserialized
{
    public const string FormatID = "hm-launcher-menu";
    public const string FileExtension = "hmlmenu";

    [JsonRequired] public string Format { get; set; } = FormatID;
    [JsonRequired] public int FormatVersion { get; set; } = 1;
    [JsonRequired] public string Name { get; set; } = "";
    [JsonRequired, JsonConverter(typeof(SwiftJson.Iso8601Converter))] public DateTime CreatedAt { get; set; }
    [JsonRequired] public List<Category> Categories { get; set; } = new();

    /// <summary>For the JSON reader.</summary>
    public MenuDocument() { }

    /// <summary>Holds a copy of <paramref name="categories"/> (a Swift value), so later menu edits don't change it.</summary>
    public MenuDocument(string name, IReadOnlyList<Category> categories, DateTime? createdAt = null)
    {
        Name = name;
        Categories = SwiftJson.Clone(categories.ToList());
        CreatedAt = createdAt ?? DateTime.UtcNow;
    }

    public sealed class NotAMenuFile : Exception
    {
        public NotAMenuFile() : base("not a HYNE ASM menu file") { }
    }

    void IJsonOnDeserialized.OnDeserialized()
    {
        SwiftJson.RejectNull(nameof(MenuDocument), Format, Name, Categories);
        SwiftJson.RejectNullElements(nameof(MenuDocument), Categories);
    }

    /// <summary>Pretty-printed with sorted keys, ISO-8601 date, written atomically (the folder must exist).</summary>
    public void Write(string path) => AtomicFile.WriteText(path, SwiftJson.Serialize(this, pretty: true));

    /// <summary>Reads a menu file (a BOM and CRLF are fine). Not JSON or missing fields → <see cref="JsonException"/>;
    /// another kind of file → <see cref="NotAMenuFile"/>.</summary>
    public static MenuDocument Read(string path)
    {
        var doc = SwiftJson.Deserialize<MenuDocument>(SwiftJson.DecodeUtf8(File.ReadAllBytes(path)));
        if (!Text.Equal(doc.Format, FormatID)) throw new NotAMenuFile();
        return doc;
    }
}

public sealed record MenuVersion(string Id, string Name, DateTime Date, bool IsAutomatic, int CategoryCount, int EntryCount);

/// <summary>Saved states of the menu, one JSON file each. Automatic versions (made before an import, push or restore)
/// are pruned to the newest <c>maxAutomatic</c>; versions saved by hand are kept.</summary>
public sealed class MenuVersionStore
{
    internal sealed class Stored : IJsonOnDeserialized
    {
        [JsonRequired] public bool IsAutomatic { get; set; }
        [JsonRequired] public MenuDocument Document { get; set; } = new();

        void IJsonOnDeserialized.OnDeserialized() => SwiftJson.RejectNull(nameof(Stored), Document);
    }

    public string Directory { get; }
    readonly int maxAutomatic;

    public MenuVersionStore(string directory, int maxAutomatic = 30)
    {
        Directory = directory;
        this.maxAutomatic = maxAutomatic;
    }

    public static string DefaultDirectory => Path.Combine(Path.GetDirectoryName(ConfigStore.DefaultPath)!, "Versions");

    /// <summary>Saves a copy of <paramref name="categories"/> as "&lt;milliseconds since 1970&gt;-&lt;8 hex&gt;.json".</summary>
    public MenuVersion Save(string name, IReadOnlyList<Category> categories, bool isAutomatic, DateTime? date = null)
    {
        System.IO.Directory.CreateDirectory(Directory);
        var when = date ?? DateTime.UtcNow;
        var millis = (when.ToUniversalTime() - DateTime.UnixEpoch).Ticks / TimeSpan.TicksPerMillisecond;
        var id = $"{millis}-{Guid.NewGuid().ToString("N")[..8].ToUpperInvariant()}";
        var stored = new Stored { IsAutomatic = isAutomatic, Document = new MenuDocument(name, categories, when) };
        AtomicFile.WriteText(FilePath(id), SwiftJson.Serialize(stored, pretty: true));
        if (isAutomatic) Prune();
        return Version(id, stored);
    }

    /// <summary>Newest first; unreadable files and files other than *.json are skipped.</summary>
    public List<MenuVersion> List()
    {
        if (!System.IO.Directory.Exists(Directory)) return new();
        var versions = new List<MenuVersion>();
        foreach (var file in System.IO.Directory.GetFiles(Directory).OrderBy(f => f, StringComparer.Ordinal))
        {
            if (SwiftPath.Extension(file) != "json") continue;
            Stored stored;
            try { stored = SwiftJson.Deserialize<Stored>(SwiftJson.DecodeUtf8(File.ReadAllBytes(file))); }
            catch (Exception e) when (e is not OutOfMemoryException) { continue; }
            versions.Add(Version(SwiftPath.DeletingExtension(SwiftPath.FileName(file)), stored));
        }
        return versions.OrderByDescending(v => v.Date).ToList();
    }

    public MenuDocument Load(string id) => SwiftJson.Deserialize<Stored>(SwiftJson.DecodeUtf8(File.ReadAllBytes(FilePath(id)))).Document;

    /// <summary>Throws when there is no such version (as Swift's <c>removeItem</c>).</summary>
    public void Delete(string id)
    {
        var path = FilePath(id);
        if (!File.Exists(path)) throw new FileNotFoundException("no such menu version", path);
        File.Delete(path);
    }

    void Prune()
    {
        foreach (var old in List().Where(v => v.IsAutomatic).Skip(maxAutomatic)) Delete(old.Id);
    }

    string FilePath(string id) => Path.Combine(Directory, id + ".json");

    static MenuVersion Version(string id, Stored s) => new(id, s.Document.Name, s.Document.CreatedAt, s.IsAutomatic,
        s.Document.Categories.Count, s.Document.Categories.Sum(c => c.Entries.Count));
}
