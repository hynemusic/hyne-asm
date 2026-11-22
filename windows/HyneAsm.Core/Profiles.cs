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
}
