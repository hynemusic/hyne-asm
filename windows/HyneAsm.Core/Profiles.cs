using System.Text.Json.Serialization;
using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>A named menu: its own categories, entries and folders ("Production", "Mixing", "Live Show").
/// The active profile's menu is <see cref="LauncherConfig.Categories"/>; the others are kept here and swapped in on switch.</summary>
public sealed record Profile : IJsonOnDeserialized
{
    [JsonRequired] public Guid Id { get; set; }
    [JsonRequired] public string Name { get; set; } = "";
    /// <summary>Only up to date for inactive profiles; the active one lives in <see cref="LauncherConfig.Categories"/>.</summary>
    [JsonRequired] public List<Category> Categories { get; set; } = new();

    public Profile() { }

    public Profile(string name, List<Category>? categories = null, Guid? id = null)
    {
        Id = id ?? Guid.NewGuid(); Name = name; Categories = categories ?? new();
    }

    void IJsonOnDeserialized.OnDeserialized()
    {
        SwiftJson.RejectNull(nameof(Profile), Name, Categories);
        SwiftJson.RejectNullElements(nameof(Profile), Categories);
    }

    /// <summary>Same id and name (as in Swift; the categories are not compared).</summary>
    public bool Equals(Profile? other) => other is not null && Id == other.Id && Name == other.Name;

    public override int GetHashCode() => HashCode.Combine(Id, Name);
}

public sealed partial record LauncherConfig
{
    [JsonIgnore] public Profile ActiveProfile => Profiles.FirstOrDefault(p => p.Id == ActiveProfileID) ?? Profiles[0];

    /// <summary>Adds a profile (not switching to it): a copy of the current menu, or a fresh one with Favorites.</summary>
    public Guid AddProfile(string name, bool copyingCurrent)
    {
        var profile = new Profile(name, copyingCurrent ? Copy(Categories) : FreshCategories());
        Profiles.Add(profile);
        return profile.Id;
    }

    /// <summary>Saves the current menu into the active profile, then loads the other one.</summary>
    public void SwitchProfile(Guid id)
    {
        var target = Profiles.FindIndex(p => p.Id == id);
        if (id == ActiveProfileID || target < 0) return;
        var current = Profiles.FindIndex(p => p.Id == ActiveProfileID);
        if (current >= 0) Profiles[current].Categories = Categories;
        // A copy, as Swift's value types give: the stored menu stays as saved while the loaded one is edited.
        var loaded = SwiftJson.Clone(Profiles[target].Categories);
        if (!loaded.Any(c => c.IsFavorites)) loaded.Insert(0, new Category("Favorites", isFavorites: true));
        Categories = loaded;
        ActiveProfileID = id;
    }

    public void SwitchToNextProfile()
    {
        var i = Profiles.FindIndex(p => p.Id == ActiveProfileID);
        if (Profiles.Count <= 1 || i < 0) return;
        SwitchProfile(Profiles[(i + 1) % Profiles.Count].Id);
    }

    public void RenameProfile(Guid id, string name)
    {
        var trimmed = Text.TrimWhitespaces(name);
        var i = Profiles.FindIndex(p => p.Id == id);
        if (trimmed.Length == 0 || i < 0) return;
        Profiles[i].Name = trimmed;
    }

    /// <summary>The active profile and the last one stay.</summary>
    public void DeleteProfile(Guid id)
    {
        if (id == ActiveProfileID || Profiles.Count <= 1) return;
        Profiles.RemoveAll(p => p.Id == id);
    }

    /// <summary>Makes sure there is one profile and it is the active one (configs from before profiles).</summary>
    internal void EnsureProfile()
    {
        if (Profiles.Count == 0)
        {
            var first = new Profile(Loc.T("Standard", "Default"));
            Profiles = new() { first };
            ActiveProfileID = first.Id;
        }
        else if (!Profiles.Any(p => p.Id == ActiveProfileID))
        {
            ActiveProfileID = Profiles[0].Id;
        }
    }

    public static List<Category> FreshCategories() =>
        new() { new Category("Favorites", isFavorites: true), new Category("Instruments"), new Category("Effects") };

    /// <summary>Copies with new ids, so two profiles never share a category or entry id.</summary>
    public static List<Category> Copy(IEnumerable<Category> categories)
    {
        var copy = SwiftJson.Clone(categories.ToList());
        foreach (var c in copy)
        {
            c.Id = Guid.NewGuid();
            foreach (var e in c.Entries) RenewIDs(e);
        }
        return copy;
    }

    static void RenewIDs(Entry e)
    {
        e.Id = Guid.NewGuid();
        foreach (var k in e.Children ?? new()) RenewIDs(k);
    }
}
