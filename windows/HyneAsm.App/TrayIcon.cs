using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using HyneAsm.Core;
using Forms = System.Windows.Forms;

namespace HyneAsm.App;

/// <summary>The tray icon and its menu (the Windows counterpart of the Mac menu bar item).</summary>
sealed class TrayIcon : IDisposable
{
    readonly AppModel model;
    readonly Forms.NotifyIcon icon;
    public Action? OnShowIntroduction, OnQuit;
    public Action<bool>? OnStreamDeckChanged;

    public TrayIcon(AppModel model)
    {
        this.model = model;
        icon = new Forms.NotifyIcon { Icon = LoadIcon(), Text = "HYNE ASM", Visible = true, ContextMenuStrip = new Forms.ContextMenuStrip() };
        icon.ContextMenuStrip.Opening += (_, _) => Build();
        icon.DoubleClick += (_, _) => OnShowIntroduction?.Invoke();
        Build();
    }

    static Stream IconStream() => Assembly.GetExecutingAssembly().GetManifestResourceStream("AppIcon.ico")!;

    static System.Drawing.Icon LoadIcon() { using var s = IconStream(); return new System.Drawing.Icon(s, 32, 32); }

    public static ImageSource ImageSource()
    {
        using var s = IconStream();
        return BitmapFrame.Create(s, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
    }

    public void Notify(string title, string text) => icon.ShowBalloonTip(4000, title, text, Forms.ToolTipIcon.Info);

    void Build()
    {
        var m = icon.ContextMenuStrip!.Items;
        m.Clear();
        var status = model.IsConnected
            ? Loc.T("Verbunden mit Live ", "Connected to Live ") + (model.Hello?.LiveVersion ?? "")
            : Loc.T("Nicht mit Live verbunden", "Not connected to Live");
        m.Add(new Forms.ToolStripMenuItem(status) { Enabled = false });
        m.Add(new Forms.ToolStripMenuItem(Loc.T($"{model.Catalog.Items.Count} Plugins, Geräte und Presets", $"{model.Catalog.Items.Count} plugins, devices and presets")) { Enabled = false });
        m.Add(new Forms.ToolStripSeparator());

        if (model.Config.Profiles.Count > 1)
        {
            var profiles = new Forms.ToolStripMenuItem(Loc.T("Profil", "Profile"));
            foreach (var p in model.Config.Profiles)
            {
                var id = p.Id;
                profiles.DropDownItems.Add(new Forms.ToolStripMenuItem(p.Name, null, (_, _) => { model.Config.SwitchProfile(id); model.ConfigChanged(); })
                { Checked = p.Id == model.Config.ActiveProfileID });
            }
            m.Add(profiles);
        }
        m.Add(Item(Loc.T("Plugin-Liste neu laden", "Reload plugin list"), model.RefreshCatalog));
        m.Add(Item(Loc.T("Menü importieren (.hmlmenu) …", "Import menu (.hmlmenu) …"), () => ImportMenu(model)));
        m.Add(Item(Loc.T("Menü exportieren …", "Export menu …"), ExportMenu));
        m.Add(Item(Loc.T("LES-Menü importieren …", "Import LES menu …"), ImportLES));
        m.Add(new Forms.ToolStripSeparator());
        m.Add(Item(Loc.T("Live-Script installieren …", "Install Live Script …"), () => InstallScript(model)));
        m.Add(new Forms.ToolStripMenuItem(Loc.T("Stream-Deck-Verbindung", "Stream Deck link"), null, (_, _) =>
        {
            model.Config.StreamDeckEnabled = !model.Config.StreamDeckEnabled;
            model.ConfigChanged();
            OnStreamDeckChanged?.Invoke(model.Config.StreamDeckEnabled);
        }) { Checked = model.Config.StreamDeckEnabled });
        if (model.Config.StreamDeckEnabled)
            m.Add(Item(Loc.T("Stream-Deck-Link kopieren (Schnellsuche)", "Copy Stream Deck link (quick search)"), () =>
            {
                var link = RemoteCommand.QuickSearch.Link(http: true, model.Config.StreamDeckToken).OriginalString;
                Forms.Clipboard.SetText(link);
                model.Hud.Show(Loc.T("Link kopiert", "Link copied"));
            }));
        var language = new Forms.ToolStripMenuItem(Loc.T("Sprache", "Language"));
        foreach (var (title, value) in new (string, Language?)[] { (Loc.T("Automatisch", "Automatic"), null), ("Deutsch", Language.De), ("English", Language.En) })
            language.DropDownItems.Add(new Forms.ToolStripMenuItem(title, null, (_, _) => { model.Config.Language = value; model.ConfigChanged(); })
            { Checked = model.Config.Language == value });
        m.Add(language);
        var design = new Forms.ToolStripMenuItem(Loc.T("Design", "Look"));
        foreach (var theme in Enum.GetValues<AppTheme>())
        {
            var t = theme;
            design.DropDownItems.Add(new Forms.ToolStripMenuItem(t.Title(), null, (_, _) => { model.Config.Theme = t; model.ConfigChanged(); })
            { Checked = model.Config.Theme == t, ToolTipText = t.Subtitle() });
        }
        m.Add(design);
        m.Add(new Forms.ToolStripMenuItem(Loc.T("Mit Windows starten", "Start with Windows"), null, (_, _) =>
            WindowsDefaults.StartsWithWindows = !WindowsDefaults.StartsWithWindows) { Checked = WindowsDefaults.StartsWithWindows });
        m.Add(Item(Loc.T("Einstellungsordner öffnen", "Open settings folder"), () =>
            Process.Start(new ProcessStartInfo("explorer.exe", Path.GetDirectoryName(ConfigStore.DefaultPath)!) { UseShellExecute = true })));
        m.Add(Item(Loc.T("Einführung zeigen …", "Show Introduction …"), () => OnShowIntroduction?.Invoke()));
        m.Add(new Forms.ToolStripSeparator());
        m.Add(Item(Loc.T("HYNE ASM beenden", "Quit HYNE ASM"), () => OnQuit?.Invoke()));
    }

    static Forms.ToolStripMenuItem Item(string title, Action action) => new(title, null, (_, _) => action());

    public static void InstallScript(AppModel model)
    {
        try
        {
            ScriptInstaller.Install();
            MessageBox.Show(
                Loc.T($"ASMbridge ist installiert in\n{ScriptInstaller.Target}\n\nStarte Live neu und wähle unter Einstellungen → Link, Tempo & MIDI → Control Surface „ASMbridge“ (Input/Output: None).",
                      $"ASMbridge is installed in\n{ScriptInstaller.Target}\n\nRestart Live and choose “ASMbridge” under Settings → Link, Tempo & MIDI → Control Surface (Input/Output: None)."),
                "HYNE ASM", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception e)
        {
            MessageBox.Show(Loc.T("Installieren fehlgeschlagen: ", "Installing failed: ") + e.Message, "HYNE ASM", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        model.ConfigChanged();
    }

    public static void ImportMenu(AppModel model)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "HYNE ASM menu (*.hmlmenu)|*.hmlmenu|JSON|*.json" };
        if (dialog.ShowDialog() != true) return;
        try
        {
            model.ImportMenuFile(dialog.FileName);
            model.Hud.Show(Loc.T("Menü importiert", "Menu imported"));
        }
        catch (Exception)
        {
            MessageBox.Show(Loc.T("Das ist keine HYNE-ASM-Menüdatei.", "That isn't a HYNE ASM menu file."), "HYNE ASM", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    void ExportMenu()
    {
        var dialog = new Microsoft.Win32.SaveFileDialog { Filter = "HYNE ASM menu (*.hmlmenu)|*.hmlmenu", FileName = "HYNE ASM menu." + MenuDocument.FileExtension };
        if (dialog.ShowDialog() != true) return;
        try { model.ExportMenu(dialog.FileName); }
        catch (Exception e) { MessageBox.Show(e.Message, "HYNE ASM", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    void ImportLES()
    {
        if (model.Catalog.Items.Count == 0)
        {
            MessageBox.Show(Loc.T("Erst mit Live verbinden: HYNE ASM braucht Lives Plugin-Liste, um das LES-Menü zuzuordnen.",
                                  "Connect to Live first: HYNE ASM needs Live's plugin list to match the LES menu."), "HYNE ASM");
            return;
        }
        var start = Path.GetDirectoryName(LESMenuParser.DefaultPath)!;
        var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "LES menuconfig.ini|*.ini|*.*|*.*", InitialDirectory = Directory.Exists(start) ? start : null };
        if (dialog.ShowDialog() != true) return;
        try
        {
            var draft = model.LESDraft(dialog.FileName);
            var c = draft.Counts;
            var answer = MessageBox.Show(
                Loc.T($"{c.Found} gefunden, {c.Uncertain} unsicher, {c.NotFound} nicht gefunden.\n\nJa: dein Menü ersetzen · Nein: hinzufügen\n(Vorher wird eine Version gesichert.)",
                      $"{c.Found} found, {c.Uncertain} uncertain, {c.NotFound} not found.\n\nYes: replace your menu · No: add to it\n(A version is saved first.)"),
                Loc.T("LES-Menü importieren", "Import LES menu"), MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
            if (answer == MessageBoxResult.Cancel) return;
            model.ApplyLES(draft, answer == MessageBoxResult.Yes ? ImportMode.Replace : ImportMode.Add);
            model.Hud.Show(Loc.T("LES-Menü übernommen", "LES menu imported"));
        }
        catch (Exception e) { MessageBox.Show(e.Message, "HYNE ASM", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    public void Dispose() { icon.Visible = false; icon.Dispose(); }
}
