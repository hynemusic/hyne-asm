using System;
using System.Runtime.InteropServices;
using System.Text;

namespace HyneAsm.App;

/// <summary>The Win32 calls the app needs (hooks, windows, input).</summary>
static class Native
{
    public const int WH_KEYBOARD_LL = 13, WH_MOUSE_LL = 14;
    public const int WM_KEYDOWN = 0x0100, WM_KEYUP = 0x0101, WM_SYSKEYDOWN = 0x0104, WM_SYSKEYUP = 0x0105;
    public const int WM_LBUTTONDOWN = 0x0201, WM_LBUTTONUP = 0x0202, WM_RBUTTONDOWN = 0x0204, WM_RBUTTONUP = 0x0205, WM_MBUTTONDOWN = 0x0207;
    public const int WM_CLOSE = 0x0010;
    public const uint LLKHF_INJECTED = 0x10, LLMHF_INJECTED = 0x01;
    public const uint EVENT_SYSTEM_FOREGROUND = 3, WINEVENT_OUTOFCONTEXT = 0;
    public const int GWL_STYLE = -16, GWL_EXSTYLE = -20;
    public const long WS_CAPTION = 0x00C00000, WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000, WS_EX_TOPMOST = 0x8;
    public const uint GW_OWNER = 4;
    public const uint SWP_NOSIZE = 0x1, SWP_NOZORDER = 0x4, SWP_NOACTIVATE = 0x10, SWP_SHOWWINDOW = 0x40;
    public static readonly IntPtr HWND_TOPMOST = new(-1);

    public const int VK_BACK = 0x08, VK_TAB = 0x09, VK_RETURN = 0x0D, VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12,
        VK_CAPITAL = 0x14, VK_ESCAPE = 0x1B, VK_SPACE = 0x20, VK_LEFT = 0x25, VK_UP = 0x26, VK_RIGHT = 0x27, VK_DOWN = 0x28,
        VK_LWIN = 0x5B, VK_RWIN = 0x5C, VK_LSHIFT = 0xA0, VK_RSHIFT = 0xA1, VK_LCONTROL = 0xA2, VK_RCONTROL = 0xA3,
        VK_LMENU = 0xA4, VK_RMENU = 0xA5;

    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSLLHOOKSTRUCT { public POINT pt; public uint mouseData, flags, time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUTUNION { [FieldOffset(0)] public KEYBDINPUT ki; [FieldOffset(0)] public MOUSEINPUTPAD pad; }

    /// <summary>Makes the union as large as MOUSEINPUT, which SendInput expects.</summary>
    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUTPAD { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public uint type; public INPUTUNION u; }

    public delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);
    public delegate void WinEventProc(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);
    public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SetWindowsHookEx(int idHook, HookProc fn, IntPtr hMod, uint threadId);
    [DllImport("user32.dll")] public static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hook, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr GetModuleHandle(string? name);
    [DllImport("user32.dll")] public static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr hmod, WinEventProc fn, uint pid, uint tid, uint flags);
    [DllImport("user32.dll")] public static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc fn, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hwnd, uint cmd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int max);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern uint GetDoubleClickTime();
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern short GetKeyState(int vk);
    [DllImport("user32.dll")] public static extern IntPtr GetKeyboardLayout(uint threadId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int ToUnicodeEx(uint vk, uint scan, byte[] state, StringBuilder buffer, int size, uint flags, IntPtr layout);
    [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);

    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    /// <summary>Title bar in the theme: dark mode on dark themes, caption and text colour (Windows 11) to match.</summary>
    public static void ThemeTitleBar(IntPtr hwnd, bool dark, System.Windows.Media.Color caption, System.Windows.Media.Color text)
    {
        if (hwnd == IntPtr.Zero) return;
        var on = dark ? 1 : 0;
        if (DwmSetWindowAttribute(hwnd, 20, ref on, sizeof(int)) != 0) DwmSetWindowAttribute(hwnd, 19, ref on, sizeof(int));
        var c = caption.R | caption.G << 8 | caption.B << 16;
        DwmSetWindowAttribute(hwnd, 35, ref c, sizeof(int));
        var t = text.R | text.G << 8 | text.B << 16;
        DwmSetWindowAttribute(hwnd, 36, ref t, sizeof(int));
    }

    public static bool IsDown(int vk) => (GetAsyncKeyState(vk) & 0x8000) != 0;

    public static void Tap(ushort vk)
    {
        var inputs = new[]
        {
            new INPUT { type = 1, u = new INPUTUNION { ki = new KEYBDINPUT { wVk = vk } } },
            new INPUT { type = 1, u = new INPUTUNION { ki = new KEYBDINPUT { wVk = vk, dwFlags = 2 } } },
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    public static uint ProcessOf(IntPtr hwnd) { GetWindowThreadProcessId(hwnd, out var pid); return pid; }

    public static string Title(IntPtr hwnd)
    {
        var sb = new StringBuilder(256);
        GetWindowText(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    /// <summary>Floating, never takes focus from Live, no taskbar button.</summary>
    public static void MakeNoActivate(IntPtr hwnd)
    {
        var ex = (long)GetWindowLongPtr(hwnd, GWL_EXSTYLE);
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(ex | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST));
    }

    public static bool Contains(IntPtr hwnd, POINT p) =>
        hwnd != IntPtr.Zero && IsWindowVisible(hwnd) && GetWindowRect(hwnd, out var r) &&
        p.X >= r.Left && p.X < r.Right && p.Y >= r.Top && p.Y < r.Bottom;
}
