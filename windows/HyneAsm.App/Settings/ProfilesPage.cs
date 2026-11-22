using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Page "Profiles": named menus ("Production", "Mixing", "Live Show") — switch, add, copy, rename, delete.</summary>
sealed class ProfilesPage : Page
{
    public ProfilesPage(AppModel model, SettingsWindow window) : base(model, window) { }

    public override UIElement Build()
    {
        var c = Model.Config;
        var panel = new StackPanel { Margin = new Thickness(28, 22, 28, 22), MaxWidth = 760, HorizontalAlignment = HorizontalAlignment.Left };
        panel.Children.Add(UI.Title(Loc.T("Profile", "Profiles")));
        panel.Children.Add(UI.Caption(Loc.T("Jedes Profil ist ein eigenes Menü. Das Panel zeigt das aktive; wechseln geht hier, im Tray-Menü oder per Tastenkürzel.",
                                            "Each profile is its own menu. The panel shows the active one; switch here, in the tray menu or with a shortcut.")));
        panel.Children.Add(UI.Section(Loc.T("Deine Profile", "Your profiles")));
        foreach (var p in c.Profiles)
        {
            var active = p.Id == c.ActiveProfileID;
            var categories = active ? c.Categories : p.Categories;
            var buttons = new StackPanel { Orientation = Orientation.Horizontal };
            if (!active) buttons.Children.Add(UI.Button(Loc.T("Aktivieren", "Switch to"), () => { c.SwitchProfile(p.Id); Changed(); }, primary: true));
            else buttons.Children.Add(UI.Text(Loc.T("Aktiv", "Active"), 12, Theme.Accent, FontWeights.SemiBold));
            buttons.Children.Add(UI.IconButton("", () =>
            {
                if (UI.Ask(Window, Loc.T("Profil umbenennen", "Rename profile"), p.Name) is { } n) { c.RenameProfile(p.Id, n); Changed(); }
            }, Loc.T("Umbenennen", "Rename")));
            if (c.Profiles.Count > 1)
                buttons.Children.Add(UI.IconButton("", () =>
                {
                    if (UI.Confirm(Window, "HYNE ASM", Loc.T($"Profil „{p.Name}“ löschen?", $"Delete the profile “{p.Name}”?"))) { c.DeleteProfile(p.Id); Changed(); }
                }, Loc.T("Löschen", "Delete")));
            var entries = categories.Sum(x => x.Entries.Count);
            panel.Children.Add(UI.Card(UI.Row(p.Name, $"{categories.Count} " + Loc.T("Kategorien", "categories") + $" · {entries} " + Loc.T("Einträge", "entries"), buttons)));
            ((FrameworkElement)panel.Children[^1]).Margin = new Thickness(0, 0, 0, 6);
        }
        var add = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 10, 0, 0) };
        add.Children.Add(UI.Button(Loc.T("Neues leeres Profil", "New empty profile"), () => Add(false), icon: ""));
        add.Children.Add(UI.Button(Loc.T("Aktuelles kopieren", "Copy current"), () => Add(true), icon: ""));
        panel.Children.Add(add);
        return UI.Scroll(panel);
    }

    void Add(bool copy)
    {
        var suggestion = copy ? Model.Config.ActiveProfile.Name + Loc.T(" Kopie", " copy") : Loc.T("Neues Profil", "New profile");
        if (UI.Ask(Window, Loc.T("Name des Profils", "Profile name"), suggestion) is not { } name) return;
        var id = Model.Config.AddProfile(name, copy);
        Model.Config.SwitchProfile(id);
        Changed();
    }
}
