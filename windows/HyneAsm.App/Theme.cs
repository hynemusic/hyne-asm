using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>All colours of one theme, the same five palettes as the Mac app (Palette.swift). Every brush in the
/// panel and the quick search reads from <see cref="Theme"/>, so switching the theme re-colours both.</summary>
sealed record Palette(
    bool IsDark, Color PanelSurface, Color PanelRow, Color PanelStroke, Color TextPrimary, Color TextSecondary,
    Color TextTertiary, Color Accent, Color OnAccent, Color Ink, Color? PadTop, Color PadStripe, Color OnLitPad,
    double RadiusScale = 1, Color[]? LogoColors = null, string? DisplayFont = null)
{
    static Color Hex(uint v, double alpha = 1) =>
        Color.FromArgb((byte)(alpha * 255), (byte)(v >> 16), (byte)(v >> 8), (byte)v);

    static Color White(double a) => Color.FromArgb((byte)(a * 255), 255, 255, 255);
    static Color Black(double a) => Color.FromArgb((byte)(a * 255), 0, 0, 0);

    public static Palette Make(AppTheme theme) => theme switch
    {
        // Warm black like a pad controller's housing, Ableton orange for the lit pad and the active category.
        AppTheme.Original => new(true, Hex(0x121110), Hex(0x1D1C1A), White(0.07), Hex(0xEEEAE4), Hex(0xB5AFA6), Hex(0x8D877E),
            Hex(0xFF8C1A), Hex(0x15120E), Colors.White, Hex(0x262421), Hex(0x34312D), Hex(0x15120E)),
        // Live 12's neutral dark greys with its orange highlight.
        AppTheme.Ableton => new(true, Hex(0x242424), Hex(0x363636), White(0.10), Hex(0xE6E6E6), Hex(0xB3B3B3), Hex(0x8C8C8C),
            Hex(0xFFA529), Hex(0x111111), Colors.White, null, White(0.12), Color.FromRgb(20, 20, 20)),
        AppTheme.Hyne => new(true, Hex(0x1F1F1F), Hex(0x2A2A2A), White(0.09), Colors.White, Hex(0xC9C9C9), Hex(0x8C8C8C),
            Hex(0xFFB901), Hex(0x0D0D0D), Colors.White, null, White(0.12), Color.FromRgb(20, 20, 20)),
        AppTheme.Light => new(false, Colors.White, Hex(0xF2F2F5), Black(0.10), Hex(0x1D1D1F), Hex(0x55555C), Hex(0x7A7A82),
            Hex(0xE0442F), Colors.White, Colors.Black, null, Black(0.12), Color.FromRgb(20, 20, 20)),
        // PS1 console grey, turquoise accent, the four PlayStation logo colours on the stripe.
        AppTheme.Retro => new(false, Hex(0xC2C2C4), Hex(0xD3D3D5), Black(0.22), Hex(0x1C1C20), Hex(0x45454C), Hex(0x5E5E66),
            Hex(0x0E8C87), Colors.White, Colors.Black, null, Black(0.12), Color.FromRgb(20, 20, 20), 0.5,
            new[] { Hex(0xDF0024), Hex(0xF3C300), Hex(0x00AC9F), Hex(0x2E6DB4) }, "Segoe UI Rounded, Segoe UI"),
        _ => Make(AppTheme.Original),
    };
}

static class Theme
{
    public static Palette Current { get; private set; } = Palette.Make(AppTheme.Original);
    public static AppTheme Id { get; private set; } = AppTheme.Original;

    public static void Apply(AppTheme theme) { Id = theme; Current = Palette.Make(theme); }

    public static readonly FontFamily Font = new("Segoe UI Variable Text, Segoe UI");
    public static FontFamily Display => Current.DisplayFont is { } f ? new FontFamily(f) : Font;
    public static readonly FontFamily Icons = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    public static Brush B(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
    public static Brush Surface => B(Current.PanelSurface);
    public static Brush Stroke => B(Current.PanelStroke);
    public static Brush TextPrimary => B(Current.TextPrimary);
    public static Brush TextSecondary => B(Current.TextSecondary);
    public static Brush TextTertiary => B(Current.TextTertiary);
    public static Brush Accent => B(Current.Accent);
    public static Brush OnAccent => B(Current.OnAccent);
    public static Brush Ink(double a) => B(Color.FromArgb((byte)(a * 255), Current.Ink.R, Current.Ink.G, Current.Ink.B));
    public static double Radius(double r) => r * Current.RadiusScale;

    // Kept for the welcome window (always dark, like the Mac's).
    public static readonly Brush Background = B(Color.FromRgb(0x12, 0x11, 0x10));
    public static readonly Brush PadTopFixed = B(Color.FromRgb(0x26, 0x24, 0x21));
    public static readonly Brush Text = B(Color.FromRgb(0xEE, 0xEA, 0xE4));
    public static readonly Brush Dim = B(Color.FromRgb(0x8D, 0x87, 0x7E));
    public static readonly Brush Border = B(Color.FromArgb(0x30, 255, 255, 255));
    public static readonly Brush Orange = B(Color.FromRgb(0xFF, 0x8C, 0x1A));

    public static Color? LabelColor(string? id) =>
        ColorPalette.Color(id) is { } c ? Color.FromRgb((byte)(c.Red * 255), (byte)(c.Green * 255), (byte)(c.Blue * 255)) : null;

    static Color Mix(Color a, Color b, double t) => Color.FromRgb(
        (byte)(a.R + (b.R - a.R) * t), (byte)(a.G + (b.G - a.G) * t), (byte)(a.B + (b.B - a.B) * t));

    /// <summary>Background, border and the Retro logo stripe shared by the panel and the quick search.</summary>
    public static Border Chrome(UIElement content, double radius)
    {
        var r = Radius(radius);
        var inner = new DockPanel();
        if (Current.LogoColors is { } logo)
        {
            var stripe = new UniformGrid1(logo);
            DockPanel.SetDock(stripe, Dock.Top);
            inner.Children.Add(stripe);
        }
        inner.Children.Add(content);
        return new Border
        {
            Background = Surface, BorderBrush = Stroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(r),
            Child = inner, ClipToBounds = true,
        };
    }

    sealed class UniformGrid1 : System.Windows.Controls.Primitives.UniformGrid
    {
        public UniformGrid1(Color[] colors)
        {
            Rows = 1; Height = 3;
            foreach (var c in colors) Children.Add(new Rectangle { Fill = B(c) });
        }
    }

    /// <summary>The pad plate: a top-lit gradient, or filled with <paramref name="lit"/> and glowing while active.
    /// Light catches the top edge and a shade runs along the bottom, so it reads as raised.</summary>
    public static Border Plate(UIElement content, bool active, Color lit)
    {
        var top = Current.PadTop ?? Mix(Current.PanelRow, Colors.White, 0.045);
        var border = new Border
        {
            CornerRadius = new CornerRadius(Radius(8)), Child = content,
            Background = active ? B(lit) : new LinearGradientBrush(top, Current.PanelRow, 90),
            BorderThickness = new Thickness(1),
            BorderBrush = new LinearGradientBrush(new GradientStopCollection
            {
                new(Color.FromArgb((byte)(active ? 90 : 18), 255, 255, 255), 0),
                new(Colors.Transparent, 0.5),
                new(Color.FromArgb(90, 0, 0, 0), 1),
            }, 90),
        };
        if (active) border.Effect = new DropShadowEffect { Color = lit, BlurRadius = 18, ShadowDepth = 0, Opacity = 0.45 };
        return border;
    }

    /// <summary>The colour label as a short glowing stripe centred at the bottom; dim when there is none.</summary>
    public static UIElement Stripe(bool active, Color? label, double width, double height)
    {
        var fill = label is { } c ? (active ? Mix(c, Colors.White, 0.45) : c)
            : active ? Color.FromArgb(77, Current.OnLitPad.R, Current.OnLitPad.G, Current.OnLitPad.B) : Current.PadStripe;
        var stripe = new Border { Width = width, Height = height, CornerRadius = new CornerRadius(height / 2), Background = B(fill) };
        if (label is { } l) stripe.Effect = new DropShadowEffect { Color = l, BlurRadius = active ? 10 : 8, ShadowDepth = 0, Opacity = active ? 0.9 : 0.55 };
        return stripe;
    }

    public static TextBlock Icon(string iconID, double size, Brush brush) => new()
    {
        Text = IconGlyphs.Glyph(iconID), FontFamily = Icons, FontSize = size, Foreground = brush,
        HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
    };

    public static Border NewBadge() => new()
    {
        Background = Accent, CornerRadius = new CornerRadius(4), Padding = new Thickness(5, 1, 5, 1),
        Child = new TextBlock { Text = Loc.T("NEU", "NEW"), FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = OnAccent, FontFamily = Display },
    };

    public static Border KeyCap(string key, Brush foreground, Brush background) => new()
    {
        Background = background, CornerRadius = new CornerRadius(Radius(5)), Padding = new Thickness(5, 1, 5, 1), MinWidth = 20,
        Child = new TextBlock { Text = key, FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = foreground, HorizontalAlignment = HorizontalAlignment.Center },
    };
}

/// <summary>The Mac's SF Symbol icon ids drawn with Windows' own icon font (Segoe Fluent Icons / MDL2 Assets).
/// The ids stay what the config stores, so menus stay the same on both.</summary>
static class IconGlyphs
{
    static readonly Dictionary<string, char> Map = new()
    {
        ["generic"] = '', ["folder"] = '', ["eq-curve"] = '\uE9D2', ["eq"] = '', ["filter"] = '', ["compressor"] = '',
        ["glue"] = '', ["limiter"] = '', ["gate"] = '', ["deesser"] = '', ["transient"] = '',
        ["reverb"] = '', ["delay"] = '', ["echo"] = '', ["stereo"] = '', ["space"] = '',
        ["saturation"] = '', ["distortion"] = '', ["bitcrush"] = '', ["tape"] = '', ["console"] = '',
        ["texture"] = '', ["modulation"] = '', ["chorus"] = '', ["phaser"] = '', ["pitch"] = '',
        ["vocal"] = '', ["synth"] = '', ["sine"] = '', ["keys"] = '', ["sampler"] = '',
        ["drums"] = '', ["bass"] = '', ["strings"] = '', ["pad"] = '', ["utility"] = '',
        ["meter"] = '', ["analyzer"] = '', ["tuner"] = '', ["midi"] = '', ["arp"] = '',
        ["chord"] = '', ["rack"] = '', ["amp"] = '', ["mic"] = '', ["repair"] = '',
        ["headphones"] = '', ["mastering"] = '', ["resonance"] = '', ["sidechain"] = '',
        ["granular"] = '', ["star"] = '', ["heart"] = '', ["sparkles"] = '',
    };

    static readonly Dictionary<string, (string De, string En)> Labels = new()
    {
        ["generic"] = ("Plugin", "Plugin"),
        ["folder"] = ("Ordner", "Folder"),
        ["eq"] = ("EQ", "EQ"),
        ["eq-curve"] = ("EQ-Kurve", "EQ curve"),
        ["filter"] = ("Filter", "Filter"),
        ["compressor"] = ("Kompressor", "Compressor"),
        ["glue"] = ("Bus-Comp", "Bus-Comp"),
        ["limiter"] = ("Limiter", "Limiter"),
        ["gate"] = ("Gate", "Gate"),
        ["deesser"] = ("De-Esser", "De-Esser"),
        ["transient"] = ("Transient", "Transient"),
        ["reverb"] = ("Reverb", "Reverb"),
        ["delay"] = ("Delay", "Delay"),
        ["echo"] = ("Echo", "Echo"),
        ["stereo"] = ("Stereo", "Stereo"),
        ["space"] = ("Raum", "Room"),
        ["saturation"] = ("Sättigung", "Saturation"),
        ["distortion"] = ("Distortion", "Distortion"),
        ["bitcrush"] = ("Bitcrush", "Bitcrush"),
        ["tape"] = ("Tape", "Tape"),
        ["console"] = ("Konsole", "Console"),
        ["texture"] = ("Textur", "Texture"),
        ["modulation"] = ("Modulation", "Modulation"),
        ["chorus"] = ("Chorus", "Chorus"),
        ["phaser"] = ("Phaser", "Phaser"),
        ["pitch"] = ("Pitch", "Pitch"),
        ["vocal"] = ("Vocal", "Vocal"),
        ["synth"] = ("Synth", "Synth"),
        ["sine"] = ("Sinus", "Sine"),
        ["keys"] = ("Keys", "Keys"),
        ["sampler"] = ("Sampler", "Sampler"),
        ["drums"] = ("Drums", "Drums"),
        ["bass"] = ("Bass", "Bass"),
        ["strings"] = ("Strings", "Strings"),
        ["pad"] = ("Pad", "Pad"),
        ["utility"] = ("Utility", "Utility"),
        ["meter"] = ("Meter", "Meter"),
        ["analyzer"] = ("Analyzer", "Analyzer"),
        ["tuner"] = ("Tuner", "Tuner"),
        ["midi"] = ("MIDI", "MIDI"),
        ["arp"] = ("Arp", "Arp"),
        ["chord"] = ("Chord", "Chord"),
        ["rack"] = ("Rack", "Rack"),
        ["amp"] = ("Amp", "Amp"),
        ["mic"] = ("Mikrofon", "Mic"),
        ["repair"] = ("Reparatur", "Repair"),
        ["headphones"] = ("Kopfhörer", "Headphones"),
        ["mastering"] = ("Mastering", "Mastering"),
        ["resonance"] = ("Resonanzen", "Resonance"),
        ["sidechain"] = ("Sidechain", "Sidechain"),
        ["granular"] = ("Granular", "Granular"),
        ["star"] = ("Favorit", "Favorite"),
        ["heart"] = ("Herz", "Heart"),
        ["sparkles"] = ("Magic", "Magic"),
    };

    /// <summary>The icon's name as the Mac shows it in the icon picker.</summary>
    public static string Label(string id) => Labels.TryGetValue(id, out var l) ? Loc.T(l.De, l.En) : id;

    public static string Glyph(string id) => (Map.TryGetValue(id, out var c) ? c : Map["generic"]).ToString();
}
