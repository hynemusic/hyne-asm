using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>The welcome window: each step ticks itself off when it really works.</summary>
sealed class IntroWindow : Window
{
    readonly AppModel model;
    readonly StackPanel steps = new();
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1) };

    public IntroWindow(AppModel model)
    {
        this.model = model;
        Title = "HYNE ASM";
        Width = 560;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Theme.Background;
        FontFamily = Theme.Font;
        Icon = TrayIcon.ImageSource();
        var root = new StackPanel { Margin = new Thickness(28, 24, 28, 24) };
        root.Children.Add(new TextBlock { Text = Loc.T("Willkommen bei HYNE ASM", "Welcome to HYNE ASM"), FontSize = 22, FontWeight = FontWeights.SemiBold, Foreground = Theme.Text });
        root.Children.Add(new TextBlock
        {
            Text = Loc.T("Doppelter Rechtsklick in Live öffnet dein Menü, Strg+Leertaste die Schnellsuche.",
                         "A double right-click in Live opens your menu, Ctrl+Space the quick search."),
            Foreground = Theme.Dim, FontSize = 13, Margin = new Thickness(0, 4, 0, 18), TextWrapping = TextWrapping.Wrap,
        });
        root.Children.Add(steps);
        var done = Button(Loc.T("Fertig", "Done"), primary: true);
        done.HorizontalAlignment = HorizontalAlignment.Right;
        done.Margin = new Thickness(0, 18, 0, 0);
        done.Click += (_, _) => Close();
        root.Children.Add(done);
        Content = root;
        model.Changed += Refresh;
        timer.Tick += (_, _) => Refresh();
        Closed += (_, _) =>
        {
            timer.Stop();
            model.Changed -= Refresh;
            if (!model.Config.OnboardingDone) { model.Config.OnboardingDone = true; model.ConfigChanged(); }
        };
        Refresh();
        timer.Start();
    }

    void Refresh()
    {
        steps.Children.Clear();
        var install = Button(ScriptInstaller.IsInstalled ? Loc.T("Neu installieren", "Reinstall") : Loc.T("Installieren", "Install"));
        install.Click += (_, _) => TrayIcon.InstallScript(model);
        steps.Children.Add(Step(1, ScriptInstaller.IsInstalled, Loc.T("Live-Script ASMbridge installieren", "Install the Live script ASMbridge"),
            Loc.T("Kommt in deine User Library: ", "Goes into your User Library: ") + ScriptInstaller.ScriptsFolder, install));
        steps.Children.Add(Step(2, model.IsConnected, Loc.T("Live neu starten und ASMbridge wählen", "Restart Live and choose ASMbridge"),
            model.IsConnected
                ? Loc.T("Verbunden mit Live ", "Connected to Live ") + (model.Hello?.LiveVersion ?? "")
                : Loc.T("Live → Einstellungen (Strg+,) → Link, Tempo & MIDI → Control Surface: ASMbridge, Input/Output: None.",
                        "Live → Settings (Ctrl+,) → Link, Tempo & MIDI → Control Surface: ASMbridge, Input/Output: None."), null));
        steps.Children.Add(Step(3, model.PanelOpened, Loc.T("Ausprobieren", "Try it"),
            Loc.T("Doppelter Rechtsklick in Live (z. B. auf eine Spur). Tippen sucht alle Plugins, 1–9 oder Klick fügt ein.",
                  "Double right-click in Live (e.g. on a track). Typing searches all plugins, 1–9 or a click inserts."), null));
        var import = Button(Loc.T("Menü importieren …", "Import menu …"));
        import.Click += (_, _) => TrayIcon.ImportMenu(model);
        steps.Children.Add(Step(4, false, Loc.T("Optional: Menü vom Mac oder aus LES übernehmen", "Optional: bring your menu from the Mac or from LES"),
            Loc.T("Am Mac: Einstellungen → Menü exportieren (.hmlmenu). LES-Menüs: Tray-Symbol → LES-Menü importieren.",
                  "On the Mac: Settings → export menu (.hmlmenu). LES menus: tray icon → Import LES menu."), import));
    }

    static UIElement Step(int number, bool done, string title, string detail, Button? action)
    {
        var grid = new Grid { Margin = new Thickness(0, 0, 0, 14) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(34) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var badge = new Border
        {
            Width = 24, Height = 24, CornerRadius = new CornerRadius(12), VerticalAlignment = VerticalAlignment.Top,
            Background = done ? new SolidColorBrush(Color.FromRgb(0x3C, 0xB3, 0x71)) : Theme.PadTopFixed,
            Child = new TextBlock { Text = done ? "✓" : number.ToString(), Foreground = Theme.Text, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, FontSize = 12 },
        };
        grid.Children.Add(badge);
        var text = new StackPanel();
        text.Children.Add(new TextBlock { Text = title, Foreground = Theme.Text, FontSize = 14, FontWeight = FontWeights.SemiBold });
        text.Children.Add(new TextBlock { Text = detail, Foreground = Theme.Dim, FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 12, 0) });
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        if (action != null) { Grid.SetColumn(action, 2); action.VerticalAlignment = VerticalAlignment.Top; grid.Children.Add(action); }
        return grid;
    }

    static Button Button(string title, bool primary = false) => new()
    {
        Content = title, Padding = new Thickness(14, 5, 14, 5), FontSize = 13, Cursor = System.Windows.Input.Cursors.Hand,
        Background = primary ? Theme.Orange : Theme.PadTopFixed, Foreground = primary ? Theme.Background : Theme.Text,
        BorderBrush = primary ? Theme.Orange : Theme.Border,
    };
}
