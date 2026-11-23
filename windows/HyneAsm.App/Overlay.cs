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

    /// <summary>Creates the window and lays it out once off screen, so the first real show is instant.</summary>
    public void Prewarm()
    {
        if (IsVisible) return;
        Left = -32000; Top = -32000;
        Show();
        UpdateLayout();
        Hide();
    }

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

/// <summary>Where an element is on screen, in the mouse hook's physical pixels.</summary>
static class ScreenRect
{
    public static bool Contains(FrameworkElement? e, Native.POINT p)
    {
        if (e == null || !e.IsVisible || PresentationSource.FromVisual(e) == null) return false;
        var a = e.PointToScreen(new Point(0, 0));
        var b = e.PointToScreen(new Point(e.ActualWidth, e.ActualHeight));
        return p.X >= Math.Min(a.X, b.X) && p.X <= Math.Max(a.X, b.X) && p.Y >= Math.Min(a.Y, b.Y) && p.Y <= Math.Max(a.Y, b.Y);
    }
}

/// <summary>The orange bar that shows where a dragged item will land: before or after the one under the pointer.</summary>
static class DropBar
{
    sealed record Saved(Brush? Brush, Thickness Thickness);

    /// <summary>True = after the element (lower or right half).</summary>
    public static bool Show(System.Windows.Controls.Border target, DragEventArgs e, bool horizontal)
    {
        var p = e.GetPosition(target);
        var after = horizontal ? p.X > target.ActualWidth / 2 : p.Y > target.ActualHeight / 2;
        if (target.Tag is not Saved) target.Tag = new Saved(target.BorderBrush, target.BorderThickness);
        target.BorderBrush = Theme.Accent;
        target.BorderThickness = horizontal
            ? (after ? new Thickness(0, 0, 3, 0) : new Thickness(3, 0, 0, 0))
            : (after ? new Thickness(0, 0, 0, 3) : new Thickness(0, 3, 0, 0));
        return after;
    }

    public static bool After(System.Windows.Controls.Border target, DragEventArgs e, bool horizontal)
    {
        var p = e.GetPosition(target);
        return horizontal ? p.X > target.ActualWidth / 2 : p.Y > target.ActualHeight / 2;
    }

    public static void Clear(System.Windows.Controls.Border target)
    {
        if (target.Tag is not Saved s) return;
        target.BorderBrush = s.Brush;
        target.BorderThickness = s.Thickness;
        target.Tag = null;
    }
}

/// <summary>Short message near the mouse that never takes focus.</summary>
sealed class Hud
{
    Overlay? window;
    System.Windows.Controls.TextBlock? label;
    System.Windows.Threading.DispatcherTimer? timer;

    public void Show(string text, double seconds = 1.8)
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
        timer.Interval = TimeSpan.FromSeconds(seconds);
        timer.Start();
    }
}
