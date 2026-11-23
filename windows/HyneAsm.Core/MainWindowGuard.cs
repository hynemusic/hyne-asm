namespace HyneAsm.Core;

/// <summary>Decides which of Live's windows must never be closed by the close-plugin-window shortcuts.
/// Live 12 titles its main window with just the set name ("Untitled", "My Song"), so the title alone
/// can't tell it apart. Plugin windows float (window layer &gt; 0); the main window is on layer 0.
/// Plan 2 feeds it Win32 data (topmost/owned windows as layer &gt; 0).</summary>
public static class MainWindowGuard
{
    public readonly record struct ScreenWindow(Rect Frame, int Layer, string Title)
    {
        public bool Equals(ScreenWindow o) => Frame == o.Frame && Layer == o.Layer && Text.Equal(Title, o.Title);

        public override int GetHashCode() => HashCode.Combine(Frame, Layer);
    }

    /// <summary>Main windows on screen: the largest normal-layer window plus any other normal-layer window
    /// with the same title (Live's second window shows the same set name).</summary>
    public static List<ScreenWindow> MainWindows(IReadOnlyList<ScreenWindow> windows)
    {
        var normal = windows.Where(w => w.Layer == 0 && w.Frame.StandardWidth >= 300 && w.Frame.StandardHeight >= 300).ToList();
        if (normal.Count == 0) return new();
        var largest = normal[0];   // Swift max(by:): the first of equal maxima
        foreach (var w in normal.Skip(1))
            if (Area(largest) < Area(w)) largest = w;
        return normal.Where(w => w == largest || (largest.Title.Length > 0 && Text.Equal(w.Title, largest.Title))).ToList();
    }

    /// <summary>True if an accessibility window with this frame/title is one of Live's main windows.</summary>
    public static bool IsMain(Rect? frame, string? title, bool isAXMain, IReadOnlyList<ScreenWindow> screen)
    {
        if (isAXMain) return true;
        if (title != null && Text.Contains(title, "Ableton Live")) return true;
        if (frame is not { } f) return false;
        return MainWindows(screen).Any(w => Close(w.Frame, f));
    }

    static double Area(ScreenWindow w) => w.Frame.StandardWidth * w.Frame.StandardHeight;

    static bool Close(Rect a, Rect b) =>
        Math.Abs(a.MinX - b.MinX) <= 4 && Math.Abs(a.MinY - b.MinY) <= 4 &&
        Math.Abs(a.StandardWidth - b.StandardWidth) <= 4 && Math.Abs(a.StandardHeight - b.StandardHeight) <= 4;
}
