using System;
using System.Runtime.InteropServices;
using System.Text;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>Low-level mouse and keyboard hooks: double right-click → panel, keys → panel/quick search while open,
/// shortcuts while Live is in front. Callbacks only decide whether to swallow; the work is posted to the UI thread,
/// because Windows drops a hook that takes too long.</summary>
sealed class InputHook : IDisposable
{
    readonly LiveMonitor monitor;
    readonly Native.HookProc mouseProc, keyProc;   // kept alive: Windows calls them
    IntPtr mouseHook, keyHook;
    readonly DoubleRightClickDetector detector = new(TimeSpan.FromMilliseconds(Native.GetDoubleClickTime()));
    bool swallowNextRightUp, swallowingLeftClick;

    public Action<Native.POINT>? OnDoubleRightClick;
    /// <summary>A left click in Live with no modifier or only Shift (point, Shift held); true = Live never gets the click
    /// (its button-up included).</summary>
    public Func<Native.POINT, bool, bool>? OnLeftClick;
    /// <summary>A click outside the open windows (they close unless Shift is held).</summary>
    public Action<Native.POINT>? OnClickOutside;
    public Func<bool>? IsOverlayVisible;
    public Func<Native.POINT, bool>? IsPointInOverlay;
    public Func<PanelKeyBindings>? PanelBindings;
    public Action<PanelKey>? OnOverlayKey;
    /// <summary>Mac-format combo of a key pressed in Live; returns true to swallow it.</summary>
    public Func<KeyCombo, bool>? OnShortcut;
    /// <summary>A Win+key combo while one of our own windows is in front (e.g. Win+G in the settings); true = swallow.</summary>
    public Func<KeyCombo, bool>? OnOwnWindowKey;

    public InputHook(LiveMonitor monitor)
    {
        this.monitor = monitor;
        mouseProc = MouseCallback;
        keyProc = KeyCallback;
    }

    public void Start()
    {
        var module = Native.GetModuleHandle(null);
        mouseHook = Native.SetWindowsHookEx(Native.WH_MOUSE_LL, mouseProc, module, 0);
        keyHook = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, keyProc, module, 0);
    }

    IntPtr MouseCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && Mouse((int)wParam, Marshal.PtrToStructure<Native.MSLLHOOKSTRUCT>(lParam))) return new IntPtr(1);
        return Native.CallNextHookEx(mouseHook, nCode, wParam, lParam);
    }

    bool Mouse(int msg, Native.MSLLHOOKSTRUCT info)
    {
        if ((info.flags & Native.LLMHF_INJECTED) != 0) return false;
        var inOverlay = IsPointInOverlay?.Invoke(info.pt) ?? false;
        if ((msg == Native.WM_LBUTTONDOWN || msg == Native.WM_RBUTTONDOWN || msg == Native.WM_MBUTTONDOWN) && !inOverlay &&
            (IsOverlayVisible?.Invoke() ?? false))
            OnClickOutside?.Invoke(info.pt);
        if (msg == Native.WM_RBUTTONUP && swallowNextRightUp) { swallowNextRightUp = false; return true; }
        if (msg == Native.WM_LBUTTONUP && swallowingLeftClick) { swallowingLeftClick = false; return true; }
        if (msg == Native.WM_LBUTTONDOWN && !inOverlay && monitor.IsLiveFrontmost && OnLeftClick != null &&
            !Native.IsDown(Native.VK_CONTROL) && !Native.IsDown(Native.VK_MENU) && !Native.IsDown(Native.VK_LWIN) && !Native.IsDown(Native.VK_RWIN))
        {
            swallowingLeftClick = OnLeftClick(info.pt, Native.IsDown(Native.VK_SHIFT));
            return swallowingLeftClick;
        }
        if (msg != Native.WM_RBUTTONDOWN || !monitor.IsLiveFrontmost || inOverlay) return false;
        if (detector.RightMouseDown(DateTime.UtcNow) != ClickVerdict.OpenPanel) return false;
        swallowNextRightUp = true;
        // The first right-click already opened Live's context menu; Escape closes it.
        Native.Tap(Native.VK_ESCAPE);
        OnDoubleRightClick?.Invoke(info.pt);
        return true;
    }

    IntPtr KeyCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var msg = (int)wParam;
            var info = Marshal.PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);
            if ((msg == Native.WM_KEYDOWN || msg == Native.WM_SYSKEYDOWN) && (info.flags & Native.LLKHF_INJECTED) == 0 && Key(info))
            {
                // Swallowing a key while Win is held would leave a lone Win press: Windows would open Start.
                if (Native.IsDown(Native.VK_LWIN) || Native.IsDown(Native.VK_RWIN)) Native.Tap(0xE8);
                return new IntPtr(1);
            }
        }
        return Native.CallNextHookEx(keyHook, nCode, wParam, lParam);
    }

    static WinModifiers Modifiers()
    {
        var m = WinModifiers.None;
        if (Native.IsDown(Native.VK_CONTROL)) m |= WinModifiers.Ctrl;
        if (Native.IsDown(Native.VK_MENU)) m |= WinModifiers.Alt;
        if (Native.IsDown(Native.VK_SHIFT)) m |= WinModifiers.Shift;
        if (Native.IsDown(Native.VK_LWIN) || Native.IsDown(Native.VK_RWIN)) m |= WinModifiers.Win;
        return m;
    }

    static bool IsModifierKey(uint vk) => vk is Native.VK_SHIFT or Native.VK_CONTROL or Native.VK_MENU or Native.VK_LWIN or
        Native.VK_RWIN or Native.VK_LSHIFT or Native.VK_RSHIFT or Native.VK_LCONTROL or Native.VK_RCONTROL or Native.VK_LMENU or
        Native.VK_RMENU or Native.VK_CAPITAL;

    bool Key(Native.KBDLLHOOKSTRUCT info)
    {
        var vk = info.vkCode;
        if (IsModifierKey(vk)) return false;
        var mods = Modifiers();
        var combo = KeyTranslation.FromWindows((ushort)vk, mods);
        if (IsOverlayVisible?.Invoke() == true)
        {
            var key = (combo != null ? PanelBindings?.Invoke().Key(combo) : null) ?? EditKey(vk, mods) ?? TextKey(info, mods);
            if (key is { } k) { OnOverlayKey?.Invoke(k); return true; }
        }
        if (combo != null && (mods & WinModifiers.Win) != 0 && Native.ProcessOf(Native.GetForegroundWindow()) == (uint)Environment.ProcessId)
            return OnOwnWindowKey?.Invoke(combo) ?? false;
        if (!monitor.IsLiveFrontmost || combo == null) return false;
        return OnShortcut?.Invoke(combo) ?? false;
    }

    /// <summary>Windows text-field editing for the filter / quick search: Ctrl+A select all, Ctrl+Backspace delete word.
    /// (Without this, Ctrl+A would reach Live and select everything in the set.)</summary>
    static PanelKey? EditKey(uint vk, WinModifiers mods)
    {
        var ctrlOnly = (mods & (WinModifiers.Ctrl | WinModifiers.Alt | WinModifiers.Win)) == WinModifiers.Ctrl;
        if (vk == Native.VK_BACK && ctrlOnly)
            return PanelKey.Of((mods & WinModifiers.Shift) != 0 ? PanelKeyKind.DeleteToStart : PanelKeyKind.DeleteWord);
        if (vk == 'A' && ctrlOnly && (mods & WinModifiers.Shift) == 0) return PanelKey.Of(PanelKeyKind.SelectAll);
        return null;
    }

    /// <summary>Fixed panel keys: Backspace edits the filter, digits pick rows, everything printable filters.
    /// Navigation keys come from the rebindable PanelKeyBindings.</summary>
    static PanelKey? TextKey(Native.KBDLLHOOKSTRUCT info, WinModifiers mods)
    {
        var vk = info.vkCode;
        if (vk == Native.VK_BACK) return mods == WinModifiers.None || mods == WinModifiers.Shift ? PanelKey.Of(PanelKeyKind.Backspace) : null;
        if (vk is Native.VK_RETURN or Native.VK_TAB or Native.VK_ESCAPE or >= Native.VK_LEFT and <= Native.VK_DOWN) return null;
        // Ctrl or Win (without AltGr = Ctrl+Alt) means a shortcut, not typing.
        var altGr = (mods & (WinModifiers.Ctrl | WinModifiers.Alt)) == (WinModifiers.Ctrl | WinModifiers.Alt);
        if ((mods & WinModifiers.Win) != 0 || ((mods & WinModifiers.Ctrl) != 0 && !altGr)) return null;
        var ch = Character(info, mods);
        if (string.IsNullOrEmpty(ch) || char.IsControl(ch[0])) return null;
        if (ch.Length == 1 && ch[0] is >= '0' and <= '9') return PanelKey.OfDigit(ch[0] - '0');
        // Shift + a digit key (pinned mode) types "!" etc.; it still picks the row.
        if ((mods & WinModifiers.Shift) != 0 && vk is >= '0' and <= '9') return PanelKey.OfDigit((int)vk - '0');
        return PanelKey.OfCharacter(ch);
    }

    static string Character(Native.KBDLLHOOKSTRUCT info, WinModifiers mods)
    {
        var state = new byte[256];
        if ((mods & WinModifiers.Shift) != 0) state[Native.VK_SHIFT] = 0x80;
        if ((mods & WinModifiers.Ctrl) != 0) state[Native.VK_CONTROL] = 0x80;
        if ((mods & WinModifiers.Alt) != 0) state[Native.VK_MENU] = 0x80;
        if ((Native.GetKeyState(Native.VK_CAPITAL) & 1) != 0) state[Native.VK_CAPITAL] = 0x01;
        var layout = Native.GetKeyboardLayout(Native.GetWindowThreadProcessId(Native.GetForegroundWindow(), out _));
        var sb = new StringBuilder(8);
        // Flag 4: don't change the keyboard state (keeps dead keys working in Live).
        var n = Native.ToUnicodeEx(info.vkCode, info.scanCode, state, sb, sb.Capacity, 4, layout);
        return n > 0 ? sb.ToString(0, n) : "";
    }

    public void Dispose()
    {
        if (mouseHook != IntPtr.Zero) Native.UnhookWindowsHookEx(mouseHook);
        if (keyHook != IntPtr.Zero) Native.UnhookWindowsHookEx(keyHook);
        mouseHook = keyHook = IntPtr.Zero;
    }
}
