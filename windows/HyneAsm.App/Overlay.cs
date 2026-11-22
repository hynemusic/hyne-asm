using System;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Forms = System.Windows.Forms;

namespace HyneAsm.App;

/// <summary>Colours of the Original theme (the pad look): warm black, pads #262421→#1D1C1A, Ableton orange.</summary>
static class Theme
{
    public static readonly Brush Background = Solid(0x12, 0x11, 0x10);
    public static readonly Brush PadTop = Solid(0x26, 0x24, 0x21);
    public static readonly Brush Pad = new LinearGradientBrush(Color.FromRgb(0x26, 0x24, 0x21), Color.FromRgb(0x1D, 0x1C, 0x1A), 90);
    public static readonly Brush PadHover = new LinearGradientBrush(Color.FromRgb(0x33, 0x30, 0x2B), Color.FromRgb(0x26, 0x24, 0x21), 90);
    public static readonly Brush Accent = Solid(0xFF, 0x8C, 0x1A);
    public static readonly Brush Text = Solid(0xF2, 0xEE, 0xE8);
    public static readonly Brush Dim = Solid(0x8A, 0x84, 0x7C);
    public static readonly Brush Faint = Solid(0x4A, 0x46, 0x40);
    public static readonly Brush Border = Solid(0x2E, 0x2B, 0x27);
    public static readonly FontFamily Font = new("Segoe UI Variable Text, Segoe UI");

    static SolidColorBrush Solid(byte r, byte g, byte b) { var s = new SolidColorBrush(Color.FromRgb(r, g, b)); s.Freeze(); return s; }

    public static Brush Of(HyneAsm.Core.ColorDef c) =>
        new SolidColorBrush(Color.FromRgb((byte)(c.Red * 255), (byte)(c.Green * 255), (byte)(c.Blue * 255)));
}

/// <summary>A floating window that never takes focus from Live: keys reach it through the keyboard hook.
/// Positions are physical pixels (the mouse hook's coordinates).</summary>
class Overlay : Window
{
    public IntPtr Hwnd { get; private set; }

    public Overlay()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        SizeToContent = SizeToContent.WidthAndHeight;
        FontFamily = Theme.Font;
        SourceInitialized += (_, _) =>
        {
            Hwnd = new WindowInteropHelper(this).Handle;
            Native.MakeNoActivate(Hwnd);
        };
    }

    public bool Contains(Native.POINT p) => IsVisible && Native.Contains(Hwnd, p);

    /// <summary>Shows the window with its top-left at <paramref name="p"/>, kept inside that monitor's work area.</summary>
    public void ShowAt(Native.POINT p, bool centerOnScreen = false)
    {
        if (!IsVisible) { Left = -32000; Top = -32000; Show(); }
        UpdateLayout();
        Native.GetWindowRect(Hwnd, out var r);
        int w = r.Right - r.Left, h = r.Bottom - r.Top;
        var area = Forms.Screen.FromPoint(new System.Drawing.Point(p.X, p.Y)).WorkingArea;
        int x = centerOnScreen ? area.Left + (area.Width - w) / 2 : p.X;
        int y = centerOnScreen ? area.Top + area.Height / 4 : p.Y;
        x = Math.Max(area.Left, Math.Min(x, area.Right - w));
        y = Math.Max(area.Top, Math.Min(y, area.Bottom - h));
        Native.SetWindowPos(Hwnd, Native.HWND_TOPMOST, x, y, 0, 0, Native.SWP_NOSIZE | Native.SWP_NOACTIVATE | Native.SWP_SHOWWINDOW);
    }

    /// <summary>Keeps the top-left corner where it is after the content changed size, still inside the screen.</summary>
    public void Reposition()
    {
        if (!IsVisible) return;
        Native.GetWindowRect(Hwnd, out var r);
        ShowAt(new Native.POINT { X = r.Left, Y = r.Top });
    }
}

/// <summary>Short message near the mouse that never takes focus.</summary>
sealed class Hud
{
    Overlay? window;
    System.Windows.Controls.TextBlock? label;
    System.Windows.Threading.DispatcherTimer? timer;

    public void Show(string text)
    {
        if (window == null)
        {
            label = new System.Windows.Controls.TextBlock { Foreground = Theme.Text, FontSize = 13, Margin = new Thickness(14, 8, 14, 8) };
            window = new Overlay
            {
                Content = new System.Windows.Controls.Border
                {
                    Background = Theme.Background, BorderBrush = Theme.Accent, BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(8), Child = label,
                },
            };
            timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1.8) };
            timer.Tick += (_, _) => { timer!.Stop(); window!.Hide(); };
        }
        label!.Text = text;
        Native.GetCursorPos(out var p);
        p.X += 16; p.Y += 20;
        window.ShowAt(p);
        timer!.Stop();
        timer.Start();
    }
}
