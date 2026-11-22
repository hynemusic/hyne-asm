using System.Text.Json.Serialization;
using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>Rebindable keys inside the open panel. Digits 1–9, typing and ⌫ stay fixed.</summary>
public enum PanelKeyAction { PrevTab, NextTab, Up, Down, Insert, Close }

public static class PanelKeyActionExtensions
{
    public static string Label(this PanelKeyAction action) => action switch
    {
        PanelKeyAction.PrevTab => Loc.T("Vorheriger Tab", "Previous tab"),
        PanelKeyAction.NextTab => Loc.T("Nächster Tab", "Next tab"),
        PanelKeyAction.Up => Loc.T("Nach oben", "Move up"),
        PanelKeyAction.Down => Loc.T("Nach unten", "Move down"),
        PanelKeyAction.Insert => Loc.T("Markiertes Plugin einfügen", "Insert highlighted plugin"),
        PanelKeyAction.Close => Loc.T("Panel schließen", "Close panel"),
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };

    internal static PanelKey ToPanelKey(this PanelKeyAction action) => action switch
    {
        PanelKeyAction.PrevTab => Core.PanelKey.Of(PanelKeyKind.Left),
        PanelKeyAction.NextTab => Core.PanelKey.Of(PanelKeyKind.Right),
        PanelKeyAction.Up => Core.PanelKey.Of(PanelKeyKind.Up),
        PanelKeyAction.Down => Core.PanelKey.Of(PanelKeyKind.Down),
        PanelKeyAction.Insert => Core.PanelKey.Of(PanelKeyKind.ReturnKey),
        PanelKeyAction.Close => Core.PanelKey.Of(PanelKeyKind.Escape),
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };
}

/// <summary>Stored as Swift encodes its private dictionary: <c>{"bindings": {"prevTab": [KeyCombo …], …}}</c>.</summary>
public sealed class PanelKeyBindings : IEquatable<PanelKeyBindings>, IJsonOnDeserialized
{
    [JsonInclude, JsonRequired, JsonPropertyName("bindings")]
    internal Dictionary<string, List<KeyCombo>> Bindings { get; set; } = new();

    /// <summary>A fresh copy of the defaults on every call.</summary>
    public static PanelKeyBindings Default => new()
    {
        Bindings =
        {
            [SwiftJson.RawValue(PanelKeyAction.PrevTab)] = new() { new KeyCombo(123, ModifierSet.None) },
            [SwiftJson.RawValue(PanelKeyAction.NextTab)] = new() { new KeyCombo(124, ModifierSet.None), new KeyCombo(48, ModifierSet.None) },
            [SwiftJson.RawValue(PanelKeyAction.Up)] = new() { new KeyCombo(126, ModifierSet.None) },
            [SwiftJson.RawValue(PanelKeyAction.Down)] = new() { new KeyCombo(125, ModifierSet.None) },
            [SwiftJson.RawValue(PanelKeyAction.Insert)] = new() { new KeyCombo(36, ModifierSet.None), new KeyCombo(76, ModifierSet.None) },
            [SwiftJson.RawValue(PanelKeyAction.Close)] = new() { new KeyCombo(53, ModifierSet.None) },
        },
    };

    /// <summary>Unset actions fall back to their default.</summary>
    public List<KeyCombo> this[PanelKeyAction action]
    {
        get
        {
            var key = SwiftJson.RawValue(action);
            return Bindings.TryGetValue(key, out var combos) ? combos
                : Default.Bindings.TryGetValue(key, out var fallback) ? fallback : new();
        }
        set => Bindings[SwiftJson.RawValue(action)] = value;
    }

    /// <summary>Swift <c>key(for:)</c>: the first action (in declaration order) that has this combo.</summary>
    public PanelKey? Key(KeyCombo combo)
    {
        foreach (var action in Enum.GetValues<PanelKeyAction>())
            if (this[action].Contains(combo)) return action.ToPanelKey();
        return null;
    }

    void IJsonOnDeserialized.OnDeserialized()
    {
        SwiftJson.RejectNull(nameof(PanelKeyBindings), Bindings);
        SwiftJson.RejectNullElements(nameof(PanelKeyBindings), Bindings.Values);
        SwiftJson.RejectNullElements(nameof(PanelKeyBindings), Bindings.Values.ToArray<IEnumerable<object?>?>());
    }

    public bool Equals(PanelKeyBindings? other) =>
        other is not null && Enum.GetValues<PanelKeyAction>().All(a => this[a].SequenceEqual(other[a]));

    public override bool Equals(object? obj) => Equals(obj as PanelKeyBindings);

    public override int GetHashCode()
    {
        var h = new HashCode();
        foreach (var a in Enum.GetValues<PanelKeyAction>()) h.Add(ValueEquality.Hash(this[a]));
        return h.ToHashCode();
    }
}
