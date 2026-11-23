using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Page "Profiles" (like the Mac's): the profiles, bringing a menu over from LES, saving the current menu as a
/// version, and the saved versions (restore, export, delete).</summary>
sealed class ProfilesPage : Page
{
    TextBox? versionName;

    public ProfilesPage(AppModel model, SettingsWindow window) : base(model, window) { }

    public override UIElement Build()
    {
        var c = Model.Config;
        var panel = new StackPanel();
        panel.Children.Add(UI.PageHeader(Loc.T("Profile", "Profiles"),
            Loc.T("Verschiedene Menüs für verschiedene Arbeit (z. B. Produktion und Mixing). Unten: frühere Stände, Export und Import.",
                  "Different menus for different work (e.g. production and mixing). Below: earlier states, export and import."),
            UI.Button(Loc.T("Importieren …", "Import …"), () => TrayIcon.ImportMenu(Model), ""),
            UI.Button(Loc.T("Exportieren …", "Export …"), () => TrayIcon.ExportMenu(Model), "")));

        Border? add = null;
        add = UI.Link(Loc.T("Neues Profil", "New Profile") + "  ⌄", () => UI.Menu(add!, new List<UI.MenuItem>
        {
            new(Loc.T("Leer", "Empty"), () => Add(false), Glyph: ""),
            new(Loc.T("Kopie von „", "Copy of “") + c.ActiveProfile.Name + Loc.T("“", "”"), () => Add(true), Glyph: ""),
        }, atMouse: false), "");
        panel.Children.Add(UI.Label(Loc.T("Profile", "Profiles"), add));
        var rows = new StackPanel();
        foreach (var p in c.Profiles)
        {
            var active = p.Id == c.ActiveProfileID;
            var entries = (active ? c.Categories : p.Categories).Sum(x => x.Entries.Count);
            var lead = new Border
            {
                Width = 22, Height = 22, CornerRadius = new CornerRadius(11), Background = active ? Theme.Accent : Brushes.Transparent,
                BorderBrush = active ? Theme.Accent : Theme.TextTertiary, BorderThickness = new Thickness(active ? 0 : 1.5),
                Child = active ? UI.Icon("", 11, Theme.OnAccent) : null,
            };
            if (lead.Child is TextBlock t) t.HorizontalAlignment = HorizontalAlignment.Center;
            var buttons = new StackPanel { Orientation = Orientation.Horizontal };
            buttons.Children.Add(UI.IconButton("", () => { if (UI.Ask(Window, Loc.T("Profil umbenennen", "Rename profile"), p.Name) is { Length: > 0 } n) { c.RenameProfile(p.Id, n); Changed(); } }, Loc.T("Umbenennen", "Rename")));
            var delete = UI.IconButton("", () =>
            {
                if (UI.Confirm(Window, Loc.T($"„{p.Name}“ löschen?", $"Delete “{p.Name}”?"), Loc.T("Das Profil und sein Menü werden entfernt.", "The profile and its menu are removed."), Loc.T("Löschen", "Delete")))
                { c.DeleteProfile(p.Id); Changed(); }
            }, Loc.T("Löschen", "Delete"));
            delete.IsEnabled = c.Profiles.Count > 1;
            delete.Opacity = c.Profiles.Count > 1 ? 1 : 0.3;
            buttons.Children.Add(delete);
            var row = UI.Row(p.Name, (active ? Loc.T("Aktiv · ", "Active · ") : "") + Loc.T($"{entries} Einträge", $"{entries} entries"), buttons, lead, 64);
            var card = new Border
            {
                Child = row, Padding = new Thickness(20, 0, 14, 0), Margin = new Thickness(0, 0, 0, 8), CornerRadius = new CornerRadius(Theme.Radius(12)),
                Background = active ? UI.AccentTint(0.22) : UI.Raised, BorderBrush = active ? UI.AccentTint(0.45) : Theme.Stroke, BorderThickness = new Thickness(1),
                Cursor = active ? null : System.Windows.Input.Cursors.Hand,
            };
            if (!active) card.MouseLeftButtonUp += (_, _) => { c.SwitchProfile(p.Id); Changed(); };
            rows.Children.Add(card);
        }
        panel.Children.Add(rows);
        var tip = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(2, 2, 0, 0) };
        tip.Children.Add(UI.Icon("", 12, Theme.TextTertiary));
        var tipText = UI.Text(Loc.T("Tipp: „Nächstes Profil“ bekommt unter Tastenkürzel eine Taste; das Tray-Menü wechselt auch.",
                                    "Tip: “Next profile” can get a key under Shortcuts; the tray menu switches too."), 12.5, Theme.TextTertiary);
        tipText.Margin = new Thickness(8, 0, 0, 0);
        tip.Children.Add(tipText);
        panel.Children.Add(tip);

        var les = UI.Row(Loc.T("Aus Live Enhancement Suite übernehmen", "Bring Over from Live Enhancement Suite"),
            Loc.T("Liest menuconfig.ini und zeigt, was zugeordnet wird, bevor sich etwas ändert.", "Reads menuconfig.ini and shows what gets matched before anything changes."),
            UI.SmallButton(Loc.T("LES-Import …", "LES Import …"), () => TrayIcon.ImportLES(Model)), UI.IconTile("", Theme.Accent), 68);
        var lesCard = UI.Card(les);
        lesCard.Margin = new Thickness(0, 26, 0, 0);
        panel.Children.Add(lesCard);

        var history = UI.Text(Loc.T("Verlauf aller Profile. Wiederherstellen ersetzt das aktive Profil.", "History of all profiles. Restoring one replaces the active profile."), 13, Theme.TextSecondary, FontWeights.SemiBold);
        history.Margin = new Thickness(0, 34, 0, 18);
        panel.Children.Add(history);

        versionName ??= UI.TextBox("", Loc.T("Name der Version, z. B. „Sommer-Liveset“", "Version name, e.g. “Summer live set”"));
        if (versionName.Parent is Panel old) old.Children.Remove(versionName);
        var save = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 16, 0, 10) };
        var saveButton = UI.Primary(Loc.T("Aktuelles Menü sichern", "Save Current Menu"), SaveVersion);
        DockPanel.SetDock(saveButton, Dock.Right);
        save.Children.Add(saveButton);
        save.Children.Add(versionName);
        var saveStack = new StackPanel();
        saveStack.Children.Add(save);
        var auto = UI.Caption(Loc.T("Vor jedem Import, LES-Übernehmen und Wiederherstellen wird automatisch gesichert.", "A backup is saved automatically before every import, LES push and restore."));
        auto.Margin = new Thickness(0, 0, 0, 14);
        saveStack.Children.Add(auto);
        panel.Children.Add(UI.Card(saveStack));

        panel.Children.Add(UI.Label(Loc.T("Gesicherte Versionen", "Saved versions"), UI.Text(Loc.T("Automatische Sicherungen: die letzten 30", "Automatic backups: last 30 kept"), 12.5, Theme.TextSecondary)));
        List<MenuVersion> versions;
        try { versions = Model.Versions.List(); } catch (Exception) { versions = new(); }
        if (versions.Count == 0) panel.Children.Add(UI.Card(UI.Row(Loc.T("Noch keine Versionen", "No versions yet"), null, null)));
        else panel.Children.Add(UI.Card(versions.Select(VersionRow).ToArray()));
        return UI.PageColumn(panel);
    }

    UIElement VersionRow(MenuVersion v)
    {
        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        buttons.Children.Add(UI.SmallButton(Loc.T("Wiederherstellen …", "Restore …"), () =>
        {
            if (!UI.Confirm(Window, Loc.T($"„{v.Name}“ wiederherstellen?", $"Restore “{v.Name}”?"),
                    Loc.T("Das ersetzt das Menü des aktiven Profils. Der jetzige Stand wird vorher gesichert.", "This replaces the active profile's menu. The current state is saved first."),
                    Loc.T("Wiederherstellen", "Restore"))) return;
            Model.RestoreVersion(v);
        }));
        buttons.Children.Add(UI.IconButton("", () => Export(v), Loc.T("Als Datei exportieren", "Export as a file")));
        buttons.Children.Add(UI.IconButton("", () => { Model.Versions.Delete(v.Id); Window.Redraw(); }, Loc.T("Löschen", "Delete")));
        var detail = $"{v.Date.ToLocalTime():g} · {v.CategoryCount} " + Loc.T("Kategorien", "categories") + $" · {v.EntryCount} Plugins" + (v.IsAutomatic ? " · " + Loc.T("automatisch", "automatic") : "");
        return UI.Row(v.Name, detail, buttons, UI.IconTile("", Theme.TextSecondary), 66);
    }

    void Export(MenuVersion v)
    {
        var dialog = new Microsoft.Win32.SaveFileDialog { Filter = "HYNE ASM menu (*.hmlmenu)|*.hmlmenu", FileName = v.Name + "." + MenuDocument.FileExtension };
        if (dialog.ShowDialog(Window) != true) return;
        try { Model.Versions.Load(v.Id).Write(dialog.FileName); }
        catch (Exception e) { UI.Tell(Window, "HYNE ASM", e.Message); }
    }

    void SaveVersion()
    {
        var name = versionName?.Text.Trim() is { Length: > 0 } n ? n : DateTime.Now.ToString("g");
        Model.Versions.Save(name, Model.Config.Categories, isAutomatic: false);
        if (versionName != null) versionName.Text = "";
        Model.Hud.Show(Loc.T("Version gesichert", "Version saved"));
        Window.Redraw();
    }

    void Add(bool copy)
    {
        var suggestion = copy ? Model.Config.ActiveProfile.Name + Loc.T(" Kopie", " copy") : Loc.T("Neues Profil", "New profile");
        if (UI.Ask(Window, Loc.T("Name des Profils", "Profile name"), suggestion) is not { Length: > 0 } name) return;
        var id = Model.Config.AddProfile(name, copy);
        Model.Config.SwitchProfile(id);
        Changed();
    }
}
