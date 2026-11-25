using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>The wrench next to the "Plugins &amp; Presets" count: the folders Live reads the list from and how to add
/// more in Live (the list comes from Live's browser, so folders are managed there). Same as the Mac's popover.</summary>
static class LibraryLocationsPopup
{
    public static Border Button(Func<string?> liveVersion, Action reload)
    {
        Border? button = null;
        button = UI.IconButton("", () => Show(button!, liveVersion(), reload),
            Loc.T("Ordner, aus denen Live die Liste liest", "Folders Live reads this list from"));
        return button;
    }

    static void Show(FrameworkElement at, string? liveVersion, Action reload)
    {
        var popup = new Popup
        {
            PlacementTarget = at, Placement = PlacementMode.Bottom, StaysOpen = false, AllowsTransparency = true,
            PopupAnimation = PopupAnimation.Fade, VerticalOffset = 4,
        };
        var locations = LibraryLocations.All(liveVersion);

        var folders = new StackPanel();
        Section(folders, Loc.T("Plugins", "Plug-ins"), locations.Where(l => l.Kind == LibraryLocationKind.PluginFolder && Directory.Exists(l.Path)));
        Section(folders, "User Library", locations.Where(l => l.Kind == LibraryLocationKind.UserLibrary));
        var places = locations.Where(l => l.Kind == LibraryLocationKind.Place).ToList();
        if (places.Count > 0) Section(folders, Loc.T("Orte", "Places"), places);
        else
        {
            folders.Children.Add(SectionLabel(Loc.T("Orte", "Places")));
            folders.Children.Add(UI.Caption(Loc.T("Keine eigenen Ordner in Live.", "No folders added in Live.")));
        }

        var body = new StackPanel { Width = 440 };
        body.Children.Add(UI.Text(Loc.T("Bibliotheks-Ordner", "Library Locations"), 14, weight: FontWeights.Bold));
        var sub = UI.Caption(Loc.T("Die Liste kommt aus Lives Browser. Live liest diese Ordner.", "The list comes from Live's browser. Live reads these folders."));
        sub.Margin = new Thickness(0, 2, 0, 6);
        body.Children.Add(sub);
        body.Children.Add(new ScrollViewer { Content = folders, MaxHeight = 340, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        body.Children.Add(new Border { Height = 1, Background = Theme.Stroke, Margin = new Thickness(0, 12, 0, 10) });
        body.Children.Add(UI.Text(Loc.T("Ordner hinzufügen oder entfernen", "Add or remove a folder"), 12.5, weight: FontWeights.SemiBold));
        Step(body, "1", Loc.T("Presets: In Lives Browser unter „Orte“ auf „Ordner hinzufügen …“ klicken. Entfernen per Rechtsklick → „Aus Seitenleiste entfernen“.",
                              "Presets: in Live's browser, click \"Add Folder…\" under Places. To remove one, right-click it and choose \"Remove from Sidebar\"."));
        Step(body, "2", Loc.T("Plugins: Live → Einstellungen → Plug-Ins → „Eigenen VST3-/VST2-Ordner verwenden“ einschalten und Ordner wählen.",
                              "Plug-ins: Live → Settings → Plug-Ins → turn on \"Use VST3/VST2 Custom Folder\" and pick the folder."));
        Step(body, "3", Loc.T("Danach hier die Liste neu laden.", "Then reload the list here."));
        var reloadButton = UI.Button(Loc.T("Liste neu laden", "Reload List"), () => { popup.IsOpen = false; reload(); });
        reloadButton.HorizontalAlignment = HorizontalAlignment.Right;
        reloadButton.Margin = new Thickness(0, 10, 0, 0);
        body.Children.Add(reloadButton);

        popup.Child = new Border
        {
            Child = body, Background = UI.Surface, BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(Theme.Radius(12)), Padding = new Thickness(16), Margin = new Thickness(0, 0, 14, 14),
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 22, ShadowDepth = 5, Opacity = 0.5, Color = Colors.Black },
        };
        popup.IsOpen = true;
    }

    static TextBlock SectionLabel(string text)
    {
        var label = UI.Text(text, 12, Theme.TextTertiary, FontWeights.SemiBold);
        label.Margin = new Thickness(0, 10, 0, 4);
        return label;
    }

    static void Section(StackPanel into, string title, IEnumerable<LibraryLocation> items)
    {
        var list = items.ToList();
        if (list.Count == 0) return;
        into.Children.Add(SectionLabel(title));
        foreach (var location in list) into.Children.Add(Row(location));
    }

    static FrameworkElement Row(LibraryLocation location)
    {
        var exists = Directory.Exists(location.Path);
        var row = new DockPanel { Margin = new Thickness(0, 3, 0, 3), ToolTip = location.Path };
        var icon = UI.Icon(exists ? "" : "", 13, exists ? Theme.TextSecondary : Brushes.Orange);
        icon.Width = 22;
        DockPanel.SetDock(icon, Dock.Left);
        row.Children.Add(icon);
        if (exists)
        {
            var reveal = UI.IconButton("", () => Reveal(location.Path), Loc.T("Im Explorer zeigen", "Show in Explorer"));
            DockPanel.SetDock(reveal, Dock.Right);
            row.Children.Add(reveal);
        }
        var text = new StackPanel();
        text.Children.Add(UI.Text(location.Name, 12.5, weight: FontWeights.SemiBold));
        var path = UI.Text(exists ? location.Path : location.Path + Loc.T(" (nicht gefunden)", " (not found)"), 11.5, Theme.TextTertiary);
        path.TextTrimming = TextTrimming.CharacterEllipsis;
        text.Children.Add(path);
        row.Children.Add(text);
        return row;
    }

    static void Step(StackPanel into, string number, string text)
    {
        var line = new DockPanel { Margin = new Thickness(0, 6, 0, 0) };
        var n = UI.Text(number, 12, Theme.TextTertiary, FontWeights.SemiBold);
        n.Width = 16;
        DockPanel.SetDock(n, Dock.Left);
        line.Children.Add(n);
        line.Children.Add(UI.Text(text, 12, Theme.TextSecondary, wrap: true));
        into.Children.Add(line);
    }

    static void Reveal(string path)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", "\"" + path + "\"") { UseShellExecute = true }); }
        catch (Exception) { /* Explorer missing or path gone: nothing to show */ }
    }
}
