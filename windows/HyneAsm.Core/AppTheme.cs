namespace HyneAsm.Core;

/// <summary>The look of the settings window, the panel and the quick search.</summary>
public enum AppTheme { Original, Ableton, Hyne, Light, Retro }

public static class AppThemeExtensions
{
    public static string Title(this AppTheme theme) => theme switch
    {
        AppTheme.Original => "Original",
        AppTheme.Ableton => "Ableton",
        AppTheme.Hyne => "HYNE",
        AppTheme.Light => Loc.T("Hell", "Light"),
        AppTheme.Retro => "Retro PS1",
        _ => throw new ArgumentOutOfRangeException(nameof(theme)),
    };

    public static string Subtitle(this AppTheme theme) => theme switch
    {
        AppTheme.Original => Loc.T("Warmes Schwarz, leuchtende Pads in Orange", "Warm black, glowing pads in orange"),
        AppTheme.Ableton => Loc.T("Lives Grau mit Orange", "Live's grey with orange"),
        AppTheme.Hyne => Loc.T("Aus deinem Live-Theme", "From your Live theme"),
        AppTheme.Light => Loc.T("Weiß und klar", "White and clean"),
        AppTheme.Retro => Loc.T("PS1-Konsolengrau, Türkis & Blau, Logofarben", "PS1 console grey, teal & blue, logo colours"),
        _ => throw new ArgumentOutOfRangeException(nameof(theme)),
    };
}
