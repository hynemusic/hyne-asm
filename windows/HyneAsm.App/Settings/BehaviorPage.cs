using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Page "Behavior" (like the Mac's): the panel (categories placement, grid or list and its size with a live
/// preview), where items land, hints, the Stream Deck link; plus starting with Windows.</summary>
sealed class BehaviorPage : Page
{
    public BehaviorPage(AppModel model, SettingsWindow window) : base(model, window) { }

    public override UIElement Build()
    {
        var c = Model.Config;
        var panel = new StackPanel();
        panel.Children.Add(UI.PageHeader(Loc.T("Verhalten", "Behavior"),
            Loc.T("Wie das Panel aussieht, wo Plugins in Live landen und was andere Geräte auslösen können.", "How the panel looks, where plugins land in Live and what other devices can trigger.")));

        // Panel
        panel.Children.Add(UI.GroupHeader("", Loc.T("Panel", "Panel")));
        var page = c.PanelPage;
        var sizeText = c.PanelStyle == PanelStyle.Grid
            ? Loc.T($"{page.Size} Pads pro Seite. Tasten 1–9 gelten für den ersten 3×3-Block.", $"{page.Size} pads per page. Keys 1–9 go to the first 3×3 block.")
            : Loc.T($"{page.Size} Einträge pro Seite, höchstens {page.Rows} pro Spalte. Tasten 1–9 laufen die erste Spalte hinunter.", $"{page.Size} entries per page, at most {page.Rows} per column. Keys 1–9 run down the first column.");
        var steppers = new StackPanel();
        if (c.PanelStyle == PanelStyle.Grid)
        {
            steppers.Children.Add(UI.Stepper(Loc.T("Spalten", "Columns"), c.PanelGrid.Columns, PanelGridSize.Range.Lower, PanelGridSize.Range.Upper, v => { c.PanelGrid = new PanelGridSize(v, c.PanelGrid.Rows); Changed(); }));
            steppers.Children.Add(UI.Stepper(Loc.T("Reihen", "Rows"), c.PanelGrid.Rows, PanelGridSize.Range.Lower, PanelGridSize.Range.Upper, v => { c.PanelGrid = new PanelGridSize(c.PanelGrid.Columns, v); Changed(); }));
        }
        else
        {
            steppers.Children.Add(UI.Stepper(Loc.T("Spalten", "Columns"), c.PanelList.Columns, PanelListSize.ColumnRange.Lower, PanelListSize.ColumnRange.Upper, v => { c.PanelList = new PanelListSize(v, c.PanelList.Rows); Changed(); }));
            steppers.Children.Add(UI.Stepper(Loc.T("Zeilen", "Rows"), c.PanelList.Rows, PanelListSize.RowRange.Lower, PanelListSize.RowRange.Upper, v => { c.PanelList = new PanelListSize(c.PanelList.Columns, v); Changed(); }));
        }
        var size = new StackPanel { Orientation = Orientation.Horizontal };
        size.Children.Add(SizePreview(c));
        steppers.Margin = new Thickness(16, 0, 0, 0);
        size.Children.Add(steppers);
        var s = c.PanelSize;
        var entry = new StackPanel();
        entry.Children.Add(UI.Stepper(Loc.T("Breite", "Width"), (int)Math.Round(s.ColumnWidth), (int)PanelSize.WidthRange.Lower, (int)PanelSize.WidthRange.Upper,
            v => { c.PanelSize = new PanelSize(Math.Clamp(Math.Round(s.ColumnWidth / 10) * 10 + (v > s.ColumnWidth ? 10 : -10), PanelSize.WidthRange.Lower, PanelSize.WidthRange.Upper), s.ItemHeight); Changed(); }));
        entry.Children.Add(UI.Stepper(Loc.T("Höhe", "Height"), (int)Math.Round(s.ItemHeight), (int)PanelSize.HeightRange.Lower, (int)PanelSize.HeightRange.Upper,
            v => { c.PanelSize = new PanelSize(s.ColumnWidth, Math.Clamp(s.ItemHeight + (v > s.ItemHeight ? 2 : -2), PanelSize.HeightRange.Lower, PanelSize.HeightRange.Upper)); Changed(); }));
        panel.Children.Add(UI.Card(
            UI.Row(Loc.T("Kategorien", "Categories"), Loc.T("Als Tabs über den Pads oder als Liste links daneben.", "Tabs above the pads, or a list beside them."),
                UI.Segmented(new[] { (Loc.T("Oben", "Top"), CategoryPlacement.Top), (Loc.T("Links", "Left"), CategoryPlacement.Left) }, c.CategoryPlacement, v => { c.CategoryPlacement = v; Changed(); })),
            UI.Row(Loc.T("Darstellung", "Layout"), Loc.T("Quadratische Pads im Raster oder Zeilen als Liste.", "Square pads in a grid, or rows in a list."),
                UI.Segmented(new[] { (Loc.T("Raster", "Grid"), PanelStyle.Grid), (Loc.T("Liste", "List"), PanelStyle.List) }, c.PanelStyle, v => { c.PanelStyle = v; Changed(); })),
            UI.Row(Loc.T("Größe", "Size"), sizeText, size, minHeight: 96),
            UI.Row(Loc.T("Einträge", "Entries"), Loc.T("Breite einer Spalte und Höhe eines Eintrags (im Panel auch mit dem Griff unten rechts).", "Width of a column and height of an entry."), entry, minHeight: 80)));

        // Inserting
        panel.Children.Add(UI.GroupHeader("", Loc.T("Einfügen", "Inserting")));
        var caps = Model.Hello?.Capabilities;
        var where = new StackPanel { Margin = new Thickness(0, 14, 0, 14) };
        where.Children.Add(UI.Text(Loc.T("Wo landen Plugins, Racks und Ketten?", "Where do plugins, racks and chains land?"), 14, weight: FontWeights.SemiBold));
        var seg = UI.Segmented(new[] { (Loc.T("Am Ende der Kette", "End of the chain"), InsertPosition.End), (Loc.T("Hinter dem ausgewählten Device", "After the selected device"), InsertPosition.AfterSelected) },
            c.Insert.Position, v => { c.Insert = new InsertOptions(v, c.Insert.AllSelectedTracks); Changed(); }, minWidth: 220);
        ((FrameworkElement)seg).Margin = new Thickness(48, 12, 0, 10);
        where.Children.Add(seg);
        where.Children.Add(UI.Caption(caps is { MoveDevice: false }
            ? Loc.T("„Hinter dem ausgewählten Device“ braucht ein neueres Live-Script (Tray → Live-Script installieren).", "“After the selected device” needs a newer Live script (tray → Install Live Script).")
            : Loc.T("Ohne ausgewähltes Device landet es am Ende.", "With no device selected it goes to the end.")));
        panel.Children.Add(UI.Card(where,
            UI.Row(Loc.T("Auf alle ausgewählten Spuren einfügen", "Insert on all selected tracks"),
                Loc.T("Sind in Live mehrere Spuren ausgewählt, bekommt jede ihr eigenes.", "With several tracks selected in Live, each one gets its own instance."),
                UI.Toggle(c.Insert.AllSelectedTracks, v => { c.Insert = new InsertOptions(c.Insert.Position, v); Changed(); }))));

        // Hints
        panel.Children.Add(UI.GroupHeader("", Loc.T("Hinweise", "Hints")));
        panel.Children.Add(UI.Card(UI.Row(Loc.T("Kaum genutzte Einträge in der Statistik zeigen", "Show rarely used entries on Stats"),
            Loc.T("Listet Panel-Einträge, die du fast nie einfügst, damit du aufräumen kannst.", "Lists panel entries you hardly ever insert, so you can tidy up."),
            UI.Toggle(c.ShowRarelyUsed, v => { c.ShowRarelyUsed = v; Changed(); }))));

        // Stream Deck
        panel.Children.Add(UI.GroupHeader("", "Stream Deck"));
        var server = Model.StreamDeck;
        var rows = new System.Collections.Generic.List<UIElement>
        {
            UI.Row(Loc.T("Stream-Deck-Verbindung", "Stream Deck connection"),
                (!c.StreamDeckEnabled ? Loc.T("Aus. Eingeschaltet erreicht sie nur dieser PC (127.0.0.1).", "Off. When on, only this PC can reach it (127.0.0.1).")
                : server.Error is { } err ? Loc.T("Konnte nicht starten: ", "Couldn't start: ") + err
                : Loc.T($"Läuft auf 127.0.0.1:{RemoteCommand.HttpPort}. Nur dieser PC erreicht sie.", $"Running on 127.0.0.1:{RemoteCommand.HttpPort}. Only this PC can reach it."))
                + "\n" + Loc.T("Jeder Link trägt einen geheimen Schlüssel, damit Webseiten im Browser die Verbindung nicht nutzen können.", "Every link carries a secret key, so web pages in your browser can't use the connection."),
                UI.Toggle(c.StreamDeckEnabled, v => { c.StreamDeckEnabled = v; Changed(); })),
            UI.Row(Loc.T("So richtest du eine Taste ein", "Set up a key"),
                Loc.T("In Stream Deck die Aktion „Website“ auf eine Taste ziehen, einen Link unten einfügen und „Im Hintergrund aufrufen“ anhaken.",
                      "In Stream Deck, drag the “Website” action onto a key, paste a link from below and tick “Access in background”."), null),
        };
        if (c.StreamDeckEnabled)
            foreach (var (title, command) in new (string, RemoteCommand)[]
            {
                (Loc.T("Schnellsuche öffnen", "Open quick search"), RemoteCommand.QuickSearch),
                (Loc.T("Panel an der Maus öffnen", "Open the panel at the mouse"), RemoteCommand.Panel),
                (Loc.T("Nächstes Profil", "Next profile"), RemoteCommand.NextProfile),
                (Loc.T("Alle Plugin-Fenster schließen", "Close all plugin windows"), RemoteCommand.ClosePluginWindows),
                ("Tempo 128", RemoteCommand.OfAction(new LiveAction(LiveActionKind.SetTempo, 128))),
            })
            {
                var link = command.Link(http: true, c.StreamDeckToken).OriginalString;
                rows.Add(UI.Row(title, link, UI.SmallButton(Loc.T("Kopieren", "Copy"), () => { Clipboard.SetText(link); Model.Hud.Show(Loc.T("Kopiert", "Copied")); })));
            }
        rows.Add(UI.Row(Loc.T("Ohne Stream Deck", "Without a Stream Deck"),
            Loc.T("Dieselben Befehle funktionieren als hyneasm://-Link, z. B. hyneasm://insert?name=Pro-Q%204.", "The same commands work as hyneasm:// links, e.g. hyneasm://insert?name=Pro-Q%204."), null));
        panel.Children.Add(UI.Card(rows.ToArray()));

        // Windows
        panel.Children.Add(UI.GroupHeader("", "Windows"));
        panel.Children.Add(UI.Card(UI.Row(Loc.T("Mit Windows starten", "Start with Windows"), Loc.T("Startet still im Infobereich.", "Starts quietly in the notification area."),
            UI.Toggle(WindowsDefaults.StartsWithWindows, v => { WindowsDefaults.StartsWithWindows = v; Window.Redraw(); }))));
        return UI.PageColumn(panel);
    }

    /// <summary>The Mac's little picture of one page: cells in the page layout, keys 1–9 lit in the accent.</summary>
    static FrameworkElement SizePreview(LauncherConfig c)
    {
        var page = c.PanelPage;
        var grid = c.PanelStyle == PanelStyle.Grid;
        var cellW = grid ? 9.0 : Math.Max(14, 56.0 / page.Columns);
        var cellH = grid ? 9.0 : 4.0;
        var g = new Grid();
        for (var x = 0; x < page.Columns; x++) g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(cellW + 3) });
        for (var y = 0; y < page.Rows; y++) g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(cellH + 3) });
        for (var slot = 0; slot < page.Size; slot++)
        {
            var (row, column) = page.Position(slot);
            var key = grid ? row < 3 && column < 3 : slot < 9;
            var cell = new Border
            {
                Width = cellW, Height = cellH, CornerRadius = new CornerRadius(grid ? 2 : 1),
                Background = key ? Theme.Accent : Theme.Ink(0.2), Margin = new Thickness(0, 0, 3, 3),
            };
            Grid.SetRow(cell, row);
            Grid.SetColumn(cell, column);
            g.Children.Add(cell);
        }
        return new Border
        {
            Child = new Viewbox { Child = g, StretchDirection = StretchDirection.DownOnly, MaxWidth = 92, MaxHeight = 70 },
            Padding = new Thickness(12, 10, 9, 7), CornerRadius = new CornerRadius(Theme.Radius(8)), Background = UI.Canvas,
            BorderBrush = Theme.Stroke, BorderThickness = new Thickness(1), VerticalAlignment = VerticalAlignment.Center,
        };
    }
}
