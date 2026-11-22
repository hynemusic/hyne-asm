namespace HyneAsm.Core;

public enum Language { De, En }

/// <summary>Two-language UI text: <c>Loc.T("Deutsch", "English")</c>. The app sets <see cref="Language"/> from the config.</summary>
public static class Loc
{
    public static Language Language { get; set; } = Language.De;

    public static string T(string de, string en) => Language == Language.De ? de : en;
}
