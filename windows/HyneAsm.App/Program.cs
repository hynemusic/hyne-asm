using System;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>Starts the app: one instance per user; a second start (e.g. a hyneasm:// link) hands its arguments over.</summary>
static class Program
{
    const string PipeName = "HyneAsm.Commands";

    [STAThread]
    static int Main(string[] args)
    {
        using var single = new Mutex(true, @"Local\HyneAsm.SingleInstance", out var first);
        if (!first) { Forward(args); return 0; }
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var shell = Shell.Create(app.Dispatcher, args);
        if (shell == null) return 1;
        app.Run();
        shell.Dispose();
        return 0;
    }

    /// <summary>Sends the arguments to the running instance (or asks it to show the introduction).</summary>
    static void Forward(string[] args)
    {
        try
        {
            using var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
            pipe.Connect(2000);
            using var writer = new StreamWriter(pipe);
            writer.WriteLine(args.Length > 0 ? args[0] : "--show");
        }
        catch (Exception) { /* the running instance is busy or quitting */ }
    }

    public static void ListenForForwards(Action<string> onMessage, CancellationToken stop) => Task.Run(async () =>
    {
        while (!stop.IsCancellationRequested)
        {
            try
            {
                using var pipe = new NamedPipeServerStream(PipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
                await pipe.WaitForConnectionAsync(stop);
                using var reader = new StreamReader(pipe);
                if (await reader.ReadLineAsync(stop) is { } line) onMessage(line);
            }
            catch (OperationCanceledException) { return; }
            catch (Exception) { await Task.Delay(200, CancellationToken.None); }
        }
    });
}

/// <summary>Wires the parts together (the counterpart of the Mac AppDelegate).</summary>
sealed class Shell : IDisposable
{
    readonly Dispatcher ui;
    readonly AppModel model;
    readonly LiveMonitor monitor = new();
    readonly InputHook hook;
    readonly PanelWindow panel;
    readonly QuickSearchWindow quickSearch;
    readonly TrayIcon tray;
    readonly CancellationTokenSource stop = new();
    IntroWindow? intro;
    Settings.SettingsWindow? settings;
    StreamDeckServer streamDeck => model.StreamDeck;

    Shell(Dispatcher ui, AppModel model)
    {
        this.ui = ui;
        this.model = model;
        panel = new PanelWindow(model);
        quickSearch = new QuickSearchWindow(model);
        tray = new TrayIcon(model) { OnShowIntroduction = ShowIntro, OnOpenSettings = () => ShowSettings(), OnQuit = () => Application.Current.Shutdown() };
        panel.OnOpenSettings = () => { panel.Hide(); ShowSettings(); };
        tray.OnStreamDeckChanged = on => streamDeck.SetEnabled(on);
        hook = new InputHook(monitor)
        {
            OnDoubleRightClick = p => ui.BeginInvoke(() => { quickSearch.Hide(); panel.ShowAt(p); }),
            OnClickOutside = _ => ui.BeginInvoke(() =>
            {
                quickSearch.Hide();
                if (!Native.IsDown(Native.VK_SHIFT)) panel.Hide();   // pinned: Shift keeps the panel open
            }),
            IsOverlayVisible = () => panel.IsVisible || quickSearch.IsVisible,
            IsPointInOverlay = p => panel.Contains(p) || quickSearch.Contains(p),
            PanelBindings = () => model.Config.PanelKeys,
            OnOverlayKey = key => ui.BeginInvoke(() => { if (quickSearch.IsVisible) quickSearch.Handle(key); else panel.Handle(key); }),
            OnShortcut = Shortcut,
        };
        monitor.Changed += front => ui.BeginInvoke(() => { if (!front) { panel.Hide(); quickSearch.Hide(); } });
    }

    public static Shell? Create(Dispatcher ui, string[] args)
    {
        var store = new ConfigStore(ConfigStore.DefaultPath);
        var existed = File.Exists(store.Path);
        LauncherConfig config;
        while (true)
        {
            try { config = store.Load(); break; }
            catch (ConfigUnreadableException e)
            {
                var answer = MessageBox.Show(
                    Loc.T($"Die Einstellungen können gerade nicht gelesen werden (z. B. von OneDrive oder einem Virenscanner gesperrt):\n{e.FilePath}\n\nNochmal versuchen?",
                          $"Your settings can't be read right now (e.g. locked by OneDrive or an antivirus):\n{e.FilePath}\n\nTry again?"),
                    "HYNE ASM", MessageBoxButton.OKCancel, MessageBoxImage.Warning);
                if (answer != MessageBoxResult.OK) return null;
            }
        }
        var model = new AppModel(ui, config, store, existed);
        var shell = new Shell(ui, model);
        shell.Start(args);
        return shell;
    }

    void Start(string[] args)
    {
        WindowsDefaults.RegisterLinkScheme();
        model.Start();
        hook.Start();
        streamDeck.Token = model.Config.StreamDeckToken;
        streamDeck.OnCommand = c => ui.BeginInvoke(() => Perform(c));
        streamDeck.SetEnabled(model.Config.StreamDeckEnabled);
        model.Changed += () => { streamDeck.Token = model.Config.StreamDeckToken; streamDeck.SetEnabled(model.Config.StreamDeckEnabled); };
        Program.ListenForForwards(line => ui.BeginInvoke(() => Handle(line)), stop.Token);
        if (Onboarding.ShowOnLaunch(model.ConfigExistedAtLaunch, model.Config.OnboardingDone)) ShowIntro();
        else if (!args.Contains("--background"))
            tray.Notify("HYNE ASM", Loc.T("Läuft im Infobereich. Doppelter Rechtsklick in Live öffnet dein Menü.",
                                          "Running in the notification area. Double right-click in Live opens your menu."));
        foreach (var a in args.Where(a => !a.StartsWith("--"))) Handle(a);
    }

    void Handle(string message)
    {
        if (message == "--show") { ShowSettings(); return; }
        if (RemoteCommand.TryParse(message) is { } command) Perform(command);
    }

    public void ShowSettings(int page = 0)
    {
        if (settings != null) { settings.Activate(); return; }
        settings = new Settings.SettingsWindow(model, page);
        settings.Closed += (_, _) => settings = null;
        settings.Show();
        settings.Activate();
    }

    void ShowIntro()
    {
        if (intro != null) { intro.Activate(); return; }
        intro = new IntroWindow(model);
        intro.Closed += (_, _) => intro = null;
        intro.Show();
        intro.Activate();
    }

    /// <summary>A key pressed in Live (Mac-format combo). Runs on the hook thread: decide quickly, work later.</summary>
    bool Shortcut(KeyCombo combo)
    {
        if (monitor.LivePid is not { } pid) return false;
        var matcher = new ShortcutMatcher(model.Config.Shortcuts);
        switch (matcher.Match(combo.KeyCode, combo.Modifiers))
        {
            case CloseShortcutAction.CloseFocused:
                return WindowCloser.CloseFocused(pid);
            case CloseShortcutAction.CloseAll:
                ui.BeginInvoke(() => WindowCloser.CloseAll(pid));
                return true;
            case CloseShortcutAction.QuickSearch:
                ui.BeginInvoke(() => { panel.Hide(); quickSearch.Toggle(); });
                return true;
            case CloseShortcutAction.NextProfile:
                ui.BeginInvoke(() =>
                {
                    panel.Hide();
                    model.Config.SwitchToNextProfile();
                    model.ConfigChanged();
                    model.Hud.Show(Loc.T("Profil: ", "Profile: ") + model.Config.ActiveProfile.Name);
                });
                return true;
        }
        if (ShortcutMatcher.ItemShortcutFor(combo.KeyCode, combo.Modifiers, model.Config.ItemShortcuts) is not { } item) return false;
        ui.BeginInvoke(() => { panel.Hide(); quickSearch.Hide(); model.Insert(item); });
        return true;
    }

    /// <summary>Runs a command from outside the app (hyneasm:// link or Stream Deck).</summary>
    void Perform(RemoteCommand command)
    {
        switch (command.Kind)
        {
            case RemoteCommandKind.Insert:
                if (RemoteTarget.Row(command.Name ?? "", model.Config, model.SearchIndex) is { } row) model.Insert(row);
                else model.Hud.Show(Loc.T($"„{command.Name}“ nicht gefunden", $"“{command.Name}” not found"));
                break;
            case RemoteCommandKind.Action when command.Action != null:
                model.Run(command.Action, "action|" + command.Action.Title.ToLowerInvariant());
                break;
            case RemoteCommandKind.QuickSearch:
                panel.Hide();
                quickSearch.Open();
                break;
            case RemoteCommandKind.Panel:
                quickSearch.Hide();
                Native.GetCursorPos(out var p);
                panel.ShowAt(p);
                break;
            case RemoteCommandKind.Profile:
                var profile = model.Config.Profiles.FirstOrDefault(x => string.Equals(x.Name, command.Name, StringComparison.CurrentCultureIgnoreCase));
                if (profile == null) { model.Hud.Show(Loc.T($"Profil „{command.Name}“ nicht gefunden", $"Profile “{command.Name}” not found")); break; }
                model.Config.SwitchProfile(profile.Id);
                model.ConfigChanged();
                model.Hud.Show(Loc.T("Profil: ", "Profile: ") + profile.Name);
                break;
            case RemoteCommandKind.NextProfile:
                model.Config.SwitchToNextProfile();
                model.ConfigChanged();
                model.Hud.Show(Loc.T("Profil: ", "Profile: ") + model.Config.ActiveProfile.Name);
                break;
            case RemoteCommandKind.ClosePluginWindows:
                if (monitor.LivePid is { } pid) WindowCloser.CloseAll(pid);
                break;
        }
    }

    public void Dispose()
    {
        stop.Cancel();
        hook.Dispose();
        monitor.Dispose();
        streamDeck.SetEnabled(false);
        tray.Dispose();
        model.Client.Dispose();
    }
}
