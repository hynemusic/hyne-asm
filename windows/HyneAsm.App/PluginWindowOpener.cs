using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Automation;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>Opens Live's plugin windows by pressing the device view's "Show/Hide Plug-In Window" buttons (the wrench)
/// through UI Automation, the Windows counterpart of the Mac's Accessibility API. Live 12 names them
/// <c>TrackView.Device[…].TitleBar.PluginEdit</c> (the AutomationId), whatever its language.
/// Every call is a round trip to Live: run it off the UI thread (UI Automation wants an MTA thread anyway).</summary>
static class PluginWindowOpener
{
    public enum Outcome { Pressed, NoDeviceView, NoPlugins }

    /// <summary>What a click at a point landed on: the element and its AutomationId.</summary>
    public sealed record Hit(AutomationElement Element, string? Id);

    record Found(AutomationElement Element, PluginWindowButton Button);

    /// <summary>The point lookup runs while the mouse hook waits; past this Live keeps the click.</summary>
    static readonly TimeSpan ClickTimeout = TimeSpan.FromMilliseconds(60);
    static Task<Hit?>? pending;

    /// <summary>Shortcut: every plugin of the selected track (opens the closed ones, or closes all when all are open).</summary>
    public static Outcome OpenAll(uint pid)
    {
        if (FindTrackView(pid) is not { } trackView) return Outcome.NoDeviceView;
        var found = Buttons(trackView);
        var press = PluginWindowPlanner.ToPress(found.Select(f => f.Button).ToList());
        if (press.Count == 0) return Outcome.NoPlugins;
        foreach (var b in press)
            if (found.FirstOrDefault(f => f.Button.Identifier == b.Identifier) is { } f) Press(f.Element);
        return Outcome.Pressed;
    }

    /// <summary>The element under a click (called from the mouse hook, which waits at most <see cref="ClickTimeout"/>).
    /// The lookup runs on a pool thread; while an earlier one still hangs, every click goes to Live.</summary>
    public static Hit? ElementAt(Native.POINT point)
    {
        if (pending is { IsCompleted: false }) return null;
        var task = pending = Task.Run(() =>
        {
            try
            {
                var e = AutomationElement.FromPoint(new System.Windows.Point(point.X, point.Y));
                return e == null ? null : new Hit(e, Id(e));
            }
            catch (Exception) { return null; }
        });
        return task.Wait(ClickTimeout) ? task.Result : null;
    }

    /// <summary>The first lookup in a process is slow (UI Automation sets itself up); do it before the first click.</summary>
    public static void Warm(Native.POINT point) => Task.Run(() =>
    {
        try { AutomationElement.FromPoint(new System.Windows.Point(point.X, point.Y)); } catch (Exception) { }
    });

    /// <summary>Several selected devices: opens their closed plugin windows, or closes them all when all are open.</summary>
    public static void Toggle(IReadOnlyList<string> devices, uint pid)
    {
        if (FindTrackView(pid) is not { } trackView) return;
        var wanted = devices.ToHashSet();
        var found = Buttons(trackView).Where(f => f.Button.DevicePath is { } d && wanted.Contains(d)).ToList();
        foreach (var b in PluginWindowPlanner.ToPress(found.Select(f => f.Button).ToList()))
            if (found.FirstOrDefault(f => f.Button.Identifier == b.Identifier) is { } f) Press(f.Element);
    }

    /// <summary>Presses the wrench of the plugin the X-Y field belongs to: up from the field to the device, which holds
    /// the title bar's wrench.</summary>
    public static void Toggle(AutomationElement field, string wrenchID)
    {
        try
        {
            var byId = new PropertyCondition(AutomationElement.AutomationIdProperty, wrenchID);
            for (var e = field; e != null; e = TreeWalker.RawViewWalker.GetParent(e))
            {
                if (e.FindFirst(TreeScope.Descendants, byId) is { } wrench) { Press(wrench); return; }
                if (Id(e) == PluginWindowPlanner.TrackViewID) return;
            }
        }
        catch (Exception) { /* Live changed the view meanwhile */ }
    }

    // MARK: UI Automation tree

    /// <summary>The device view inside one of Live's top-level windows.</summary>
    static AutomationElement? FindTrackView(uint pid)
    {
        try
        {
            var byId = new PropertyCondition(AutomationElement.AutomationIdProperty, PluginWindowPlanner.TrackViewID);
            var windows = AutomationElement.RootElement.FindAll(TreeScope.Children,
                new PropertyCondition(AutomationElement.ProcessIdProperty, (int)pid));
            foreach (AutomationElement w in windows)
                if (w.FindFirst(TreeScope.Descendants, byId) is { } trackView) return trackView;
        }
        catch (Exception) { }
        return null;
    }

    /// <summary>Every wrench in the device view, racks included (their contents are devices inside the rack).</summary>
    static List<Found> Buttons(AutomationElement trackView)
    {
        var result = new List<Found>();
        try
        {
            foreach (AutomationElement e in trackView.FindAll(TreeScope.Descendants, Condition.TrueCondition))
            {
                if (Id(e) is not { } id || !id.EndsWith(PluginWindowPlanner.ButtonSuffix, StringComparison.Ordinal)) continue;
                result.Add(new Found(e, new PluginWindowButton(id, IsOn(e))));
            }
        }
        catch (Exception) { }
        return result;
    }

    static string? Id(AutomationElement e)
    {
        try { return e.Current.AutomationId is { Length: > 0 } id ? id : null; }
        catch (Exception) { return null; }
    }

    /// <summary>The wrench is a check box: on = the plugin window is open.</summary>
    static bool IsOn(AutomationElement e)
    {
        try { return e.TryGetCurrentPattern(TogglePattern.Pattern, out var p) && ((TogglePattern)p).Current.ToggleState == ToggleState.On; }
        catch (Exception) { return false; }
    }

    static void Press(AutomationElement e)
    {
        try
        {
            if (e.TryGetCurrentPattern(TogglePattern.Pattern, out var t)) ((TogglePattern)t).Toggle();
            else if (e.TryGetCurrentPattern(InvokePattern.Pattern, out var i)) ((InvokePattern)i).Invoke();
        }
        catch (Exception) { /* the device went away */ }
    }
}
