using System;
using System.Diagnostics;

namespace HyneAsm.App;

/// <summary>Tracks whether Ableton Live is the foreground app (the hooks only act while it is).</summary>
sealed class LiveMonitor : IDisposable
{
    readonly Native.WinEventProc proc;   // kept alive: Windows calls it
    readonly IntPtr hook;
    uint lastPid;
    bool lastWasLive;

    public bool IsLiveFrontmost { get; private set; }
    public uint? LivePid { get; private set; }
    public event Action<bool>? Changed;

    public LiveMonitor()
    {
        proc = (_, _, hwnd, _, _, _, _) => Update(hwnd);
        hook = Native.SetWinEventHook(Native.EVENT_SYSTEM_FOREGROUND, Native.EVENT_SYSTEM_FOREGROUND, IntPtr.Zero, proc, 0, 0,
            Native.WINEVENT_OUTOFCONTEXT);
        Update(Native.GetForegroundWindow());
    }

    public static bool IsLiveProcess(uint pid)
    {
        try
        {
            using var p = Process.GetProcessById((int)pid);
            return p.ProcessName.StartsWith("Ableton Live", StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception) { return false; }
    }

    void Update(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        var pid = Native.ProcessOf(hwnd);
        if (pid == (uint)Environment.ProcessId) return;   // our own windows never count as "Live left"
        var live = pid == lastPid ? lastWasLive : IsLiveProcess(pid);
        lastPid = pid; lastWasLive = live;
        if (live) LivePid = pid;
        if (live == IsLiveFrontmost) return;
        IsLiveFrontmost = live;
        Changed?.Invoke(live);
    }

    public void Dispose() { if (hook != IntPtr.Zero) Native.UnhookWinEvent(hook); }
}
