using System.Globalization;

namespace HyneAsm.Core.Tests;

/// <summary>The OS-dependent parts of Localization.swift; the rest is in loc-resolve.json / loc-number.json.</summary>
[Collection(LocCollection.Name)]
public class LocalizationTests
{
    static T WithUICulture<T>(string name, Func<T> body)
    {
        var saved = CultureInfo.CurrentUICulture;
        CultureInfo.CurrentUICulture = new CultureInfo(name);
        try { return body(); }
        finally { CultureInfo.CurrentUICulture = saved; }
    }

    [Fact]
    public void Resolve_without_a_choice_follows_the_system_UI_language()
    {
        Assert.Equal(Language.De, WithUICulture("de-DE", () => LanguageExtensions.Resolve(null)));
        Assert.Equal(Language.De, WithUICulture("de-CH", () => LanguageExtensions.Resolve(null)));
        Assert.Equal(Language.En, WithUICulture("en-GB", () => LanguageExtensions.Resolve(null)));
        Assert.Equal(Language.En, WithUICulture("fr-FR", () => LanguageExtensions.Resolve(null)));
        Assert.Equal(Language.En, WithUICulture("de-DE", () => LanguageExtensions.Resolve(Language.En)));
    }

    [Fact]
    public void Locale_and_Number_follow_the_UI_language_not_the_system_culture()
    {
        var saved = Loc.Language;
        var culture = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = new CultureInfo("fr-FR");
            Loc.Language = Language.En;
            Assert.Equal("en-US", Loc.Locale.Name);
            Assert.Equal("1,455", Loc.Number(1455));
            Loc.Language = Language.De;
            Assert.Equal("de-DE", Loc.Locale.Name);
            Assert.Equal("1.455", Loc.Number(1455));
        }
        finally
        {
            Loc.Language = saved;
            CultureInfo.CurrentCulture = culture;
        }
    }
}
