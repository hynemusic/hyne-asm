namespace HyneAsm.Core;

/// <summary>The welcome window's steps, in order.</summary>
public enum OnboardingStep { Welcome, Permission, Connect, Menu, TryIt }

/// <summary>What the app knows right now; each step ticks off when its part is true.</summary>
public record struct OnboardingStatus
{
    public bool Permission { get; set; }
    public bool ScriptInstalled { get; set; }
    public bool Connected { get; set; }
    public bool PanelOpened { get; set; }
    public bool MenuChosen { get; set; }

    public readonly bool IsDone(OnboardingStep step) => step switch
    {
        OnboardingStep.Welcome => true,
        OnboardingStep.Permission => Permission,
        OnboardingStep.Connect => Connected,
        OnboardingStep.Menu => MenuChosen,
        OnboardingStep.TryIt => PanelOpened,
        _ => throw new ArgumentOutOfRangeException(nameof(step)),
    };
}

public static class Onboarding
{
    /// <summary>Only for new users: no config file when the app started, and not finished or skipped before.</summary>
    public static bool ShowOnLaunch(bool configExisted, bool done) => !configExisted && !done;
}

/// <summary>Live's own devices offered as a first menu.</summary>
public static class StarterSet
{
    public static readonly IReadOnlyList<string> Effects =
        new[] { "EQ Eight", "Compressor", "Glue Compressor", "Reverb", "Delay", "Utility", "Saturator", "Limiter" };
    public static readonly IReadOnlyList<string> Instruments = new[] { "Drift", "Operator", "Simpler", "Drum Rack" };
}

public sealed partial record LauncherConfig
{
    /// <summary>Adds the starter devices that exist in this Live (effects → "Effects", instruments → "Instruments");
    /// returns how many were new.</summary>
    public int AddStarterSet(IReadOnlyList<PluginItem> items)
    {
        var effectsID = (Categories.FirstOrDefault(c => Text.Equal(c.Name, "Effects")) ?? Categories.LastOrDefault(c => !c.IsFavorites))?.Id;
        var instrumentsID = (Categories.FirstOrDefault(c => Text.Equal(c.Name, "Instruments")) ?? Categories.FirstOrDefault(c => !c.IsFavorites))?.Id;
        var added = 0;
        void Add(IReadOnlyList<string> names, ItemSource source, Guid? id)
        {
            if (id is not { } categoryID) return;
            int Count() => Categories.FirstOrDefault(c => c.Id == categoryID)?.Entries.Count ?? 0;
            foreach (var name in names)
            {
                if (items.FirstOrDefault(i => i.Source == source && Text.Equal(i.Name, name)) is not { } item) continue;
                var before = Count();
                AddEntry(item, categoryID);
                if (Count() > before) added++;
            }
        }
        Add(StarterSet.Effects, ItemSource.AudioEffects, effectsID);
        Add(StarterSet.Instruments, ItemSource.Instruments, instrumentsID);
        return added;
    }
}
