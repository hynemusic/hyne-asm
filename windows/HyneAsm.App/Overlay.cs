using System;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Forms = System.Windows.Forms;

namespace HyneAsm.App;

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
            label = new System.Windows.Controls.TextBlock { FontSize = 13, Margin = new Thickness(14, 8, 14, 8) };
            window = new Overlay();
            timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1.8) };
            timer.Tick += (_, _) => { timer!.Stop(); window!.Hide(); };
        }
        label!.Text = text;
        label.Foreground = Theme.TextPrimary;
        if (label.Parent is System.Windows.Controls.Panel old) old.Children.Remove(label);   // re-wrapped in the current theme
        window.Content = Theme.Chrome(label, 8);
        Native.GetCursorPos(out var p);
        p.X += 16; p.Y += 20;
        window.ShowAt(p);
        timer!.Stop();
        timer.Start();
    }
}
