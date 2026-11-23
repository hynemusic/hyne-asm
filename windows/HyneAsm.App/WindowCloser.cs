using System;
using System.Collections.Generic;
using System.Linq;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>Closes Live's plugin windows. Live's main window is never closed.</summary>
static class WindowCloser
{
    record struct LiveWindow(IntPtr Hwnd, Rect Frame, bool Owned, bool Captioned, string Title);

    static List<LiveWindow> Windows(uint pid)
    {
        var list = new List<LiveWindow>();
        Native.EnumWindows((h, _) =>
        {
            if (Native.ProcessOf(h) != pid || !Native.IsWindowVisible(h) || !Native.GetWindowRect(h, out var r)) return true;
            var style = (long)Native.GetWindowLongPtr(h, Native.GWL_STYLE);
            list.Add(new LiveWindow(h, new Rect(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top),
                Native.GetWindow(h, Native.GW_OWNER) != IntPtr.Zero, (style & Native.WS_CAPTION) == Native.WS_CAPTION, Native.Title(h)));
            return true;
        }, IntPtr.Zero);
        return list;
    }

    /// <summary>Plugin windows float above the main window: on Windows they are owned, captioned top-level windows.</summary>
    static bool IsPluginWindow(LiveWindow w, IReadOnlyList<MainWindowGuard.ScreenWindow> screen) =>
        w.Owned && w.Captioned && !MainWindowGuard.IsMain(w.Frame, w.Title, isAXMain: false, screen);

    static List<MainWindowGuard.ScreenWindow> Screen(IEnumerable<LiveWindow> all) =>
        all.Select(w => new MainWindowGuard.ScreenWindow(w.Frame, w.Owned ? 1 : 0, w.Title)).ToList();

    /// <summary>False if the focused window is Live's main window (the key then goes to Live).</summary>
    public static bool CloseFocused(uint pid)
    {
        var fg = Native.GetForegroundWindow();
        var all = Windows(pid);
        var focused = all.FirstOrDefault(w => w.Hwnd == fg);
        if (focused.Hwnd == IntPtr.Zero || !IsPluginWindow(focused, Screen(all))) return false;
        return Native.PostMessage(fg, Native.WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
    }

    public static int CloseAll(uint pid)
    {
        var all = Windows(pid);
        var screen = Screen(all);
        return all.Where(w => IsPluginWindow(w, screen)).Count(w => Native.PostMessage(w.Hwnd, Native.WM_CLOSE, IntPtr.Zero, IntPtr.Zero));
    }
}
