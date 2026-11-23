using System.Globalization;

namespace HyneAsm.Core;

public enum Language { De, En }

/// <summary>Swift's static members of <c>Language</c> (a C# enum can't hold them; cf. <c>UsageKindExtensions.FromSource</c>).</summary>
public static class LanguageExtensions
{
    /// <summary>Swift <c>Language.resolve</c>: an explicit choice wins; otherwise German if the system prefers German, else
    /// English. Only the first preferred language counts (case-sensitive "de" prefix, as in Swift).
    /// <para><paramref name="preferred"/> defaults to the Windows display language (<see cref="CultureInfo.CurrentUICulture"/>),
    /// where Swift uses <c>Locale.preferredLanguages</c>.</para></summary>
    public static Language Resolve(Language? choice, IEnumerable<string>? preferred = null)
    {
        if (choice is { } c) return c;
        var first = (preferred ?? new[] { CultureInfo.CurrentUICulture.Name }).FirstOrDefault();
        return first != null && first.StartsWith("de", StringComparison.Ordinal) ? Language.De : Language.En;
    }
}

/// <summary>Two-language UI text: <c>Loc.T("Deutsch", "English")</c>. The app sets <see cref="Language"/> from the config.</summary>
public static class Loc
{
    public static Language Language { get; set; } = Language.De;

    public static string T(string de, string en) => Language == Language.De ? de : en;

    static readonly CultureInfo German = CultureInfo.GetCultureInfo("de-DE");
    static readonly CultureInfo English = CultureInfo.GetCultureInfo("en-US");

    /// <summary>Culture for numbers and dates, matching the UI language (an English UI on a German PC shows "1,455").</summary>
    public static CultureInfo Locale => Language == Language.De ? German : English;

    /// <summary>Swift <c>Loc.number</c>: grouped digits in <see cref="Locale"/> ("1.455" / "1,455").</summary>
    public static string Number(int value) => value.ToString("N0", Locale);
}
