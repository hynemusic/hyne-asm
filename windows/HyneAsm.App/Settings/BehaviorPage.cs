using System;
using System.Windows;
using System.Windows.Controls;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Page "Behavior": the panel's layout, where inserted items land, hints, the Stream Deck link, look and language.</summary>
sealed class BehaviorPage : Page
{
    public BehaviorPage(AppModel model, SettingsWindow window) : base(model, window) { }

    public override UIElement Build()
    {
        var c = Model.Config;
        var panel = new StackPanel { Margin = new Thickness(28, 22, 28, 22), MaxWidth = 820, HorizontalAlignment = HorizontalAlignment.Left };
        panel.Children.Add(UI.Title(Loc.T("Verhalten", "Behavior")));

        panel.Children.Add(UI.Section(Loc.T("Panel", "Panel")));
        var layout = new StackPanel();
        layout.Children.Add(UI.Row(Loc.T("Darstellung", "Layout"), Loc.T("Quadratische Pads im Raster oder Zeilen als Liste.", "Square pads in a grid, or rows in a list."),
            UI.Segmented(new[] { (Loc.T("Raster", "Grid"), PanelStyle.Grid), (Loc.T("Liste", "List"), PanelStyle.List) }, c.PanelStyle, v => { c.PanelStyle = v; Changed(); })));
        if (c.PanelStyle == PanelStyle.Grid)
        {
            layout.Children.Add(UI.Row(Loc.T("Spalten", "Columns"), null, UI.Stepper(c.PanelGrid.Columns, PanelGridSize.Range.Lower, PanelGridSize.Range.Upper,
                v => { c.PanelGrid = new PanelGridSize(v, c.PanelGrid.Rows); Changed(); })));
            layout.Children.Add(UI.Row(Loc.T("Reihen", "Rows"), null, UI.Stepper(c.PanelGrid.Rows, PanelGridSize.Range.Lower, PanelGridSize.Range.Upper,
                v => { c.PanelGrid = new PanelGridSize(c.PanelGrid.Columns, v); Changed(); })));
        }
        else
        {
            layout.Children.Add(UI.Row(Loc.T("Spalten", "Columns"), null, UI.Stepper(c.PanelList.Columns, PanelListSize.ColumnRange.Lower, PanelListSize.ColumnRange.Upper,
                v => { c.PanelList = new PanelListSize(v, c.PanelList.Rows); Changed(); })));
            layout.Children.Add(UI.Row(Loc.T("Zeilen", "Rows"), null, UI.Stepper(c.PanelList.Rows, PanelListSize.RowRange.Lower, PanelListSize.RowRange.Upper,
                v => { c.PanelList = new PanelListSize(c.PanelList.Columns, v); Changed(); })));
        }
        var size = c.PanelSize;
        layout.Children.Add(UI.Row(Loc.T("Breite", "Width"), Loc.T("Breite einer Spalte (Raster: drei Pads).", "Width of a column (grid: three pads)."),
            UI.Stepper((int)Math.Round(size.ColumnWidth / 10), (int)(PanelSize.WidthRange.Lower / 10), (int)(PanelSize.WidthRange.Upper / 10),
                v => { c.PanelSize = new PanelSize(v * 10, size.ItemHeight); Changed(); })));
        layout.Children.Add(UI.Row(Loc.T("Höhe", "Height"), Loc.T("Höhe eines Eintrags.", "Height of an entry."),
            UI.Stepper((int)Math.Round(size.ItemHeight / 2), (int)(PanelSize.HeightRange.Lower / 2), (int)(PanelSize.HeightRange.Upper / 2),
                v => { c.PanelSize = new PanelSize(size.ColumnWidth, v * 2); Changed(); })));
        panel.Children.Add(UI.Card(layout));

        panel.Children.Add(UI.Section(Loc.T("Einfügen", "Inserting")));
        var insert = new StackPanel();
        var caps = Model.Hello?.Capabilities;
        insert.Children.Add(UI.Row(Loc.T("Wo landen Plugins, Racks und Ketten?", "Where do plugins, racks and chains land?"),
            caps is { MoveDevice: false } ? Loc.T("„Hinter dem ausgewählten Device“ braucht ein neueres Live-Script (Tray → Live-Script installieren).", "“After the selected device” needs a newer Live script (tray → Install Live Script).")
                : Loc.T("Ohne ausgewähltes Device landet es am Ende.", "With no device selected it goes to the end."),
            UI.Segmented(new[] { (Loc.T("Am Ende der Kette", "End of the chain"), InsertPosition.End), (Loc.T("Hinter dem ausgewählten Device", "After the selected device"), InsertPosition.AfterSelected) },
                c.Insert.Position, v => { c.Insert = new InsertOptions(v, c.Insert.AllSelectedTracks); Changed(); })));
        insert.Children.Add(UI.Row(Loc.T("Auf alle ausgewählten Spuren einfügen", "Insert on all selected tracks"), null,
            UI.Toggle(c.Insert.AllSelectedTracks, v => { c.Insert = new InsertOptions(c.Insert.Position, v); Changed(); })));
        panel.Children.Add(UI.Card(insert));

        panel.Children.Add(UI.Section(Loc.T("Hinweise", "Hints")));
        panel.Children.Add(UI.Card(UI.Row(Loc.T("Kaum genutzte Einträge in der Statistik zeigen", "Show rarely used entries on Stats"),
            Loc.T("Listet Panel-Einträge, die du fast nie einfügst, damit du aufräumen kannst.", "Lists panel entries you hardly ever insert, so you can tidy up."),
            UI.Toggle(c.ShowRarelyUsed, v => { c.ShowRarelyUsed = v; Changed(); }))));

        panel.Children.Add(UI.Section(Loc.T("Stream Deck", "Stream Deck")));
        var deck = new StackPanel();
        var server = Model.StreamDeck;
        deck.Children.Add(UI.Row(Loc.T("Stream-Deck-Verbindung", "Stream Deck connection"),
            !c.StreamDeckEnabled ? Loc.T("Aus. Eingeschaltet erreicht sie nur dieser PC (127.0.0.1).", "Off. When on, only this PC can reach it (127.0.0.1).")
            : server.Error is { } err ? Loc.T("Konnte nicht starten: ", "Couldn't start: ") + err
            : Loc.T($"Läuft auf 127.0.0.1:{RemoteCommand.HttpPort}. Nur dieser PC erreicht sie.", $"Running on 127.0.0.1:{RemoteCommand.HttpPort}. Only this PC can reach it."),
            UI.Toggle(c.StreamDeckEnabled, v => { c.StreamDeckEnabled = v; Changed(); })));
        if (c.StreamDeckEnabled)
        {
            deck.Children.Add(UI.Caption(Loc.T("In Stream Deck: Aktion „Website“, Link einfügen, „Im Hintergrund aufrufen“ anhaken.",
                                               "In Stream Deck: “Website” action, paste the link, tick “Access in background”.")));
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
                deck.Children.Add(UI.Row(title, link, UI.Button(Loc.T("Kopieren", "Copy"), () =>
                {
                    System.Windows.Clipboard.SetText(link);
                    Model.Hud.Show(Loc.T("Kopiert", "Copied"));
                })));
            }
            deck.Children.Add(UI.Caption(Loc.T("Einen Eintrag per Name einfügen: …/insert?name=Pro-Q%204 (gleicher Link, anderer Befehl). Ohne Stream Deck funktionieren dieselben Befehle als hyneasm://-Link.",
                                               "Insert an entry by name: …/insert?name=Pro-Q%204 (same link, other command). Without a Stream Deck the same commands work as hyneasm:// links.")));
        }
        panel.Children.Add(UI.Card(deck));

        panel.Children.Add(UI.Section(Loc.T("Allgemein", "General")));
        var general = new StackPanel();
        general.Children.Add(UI.Row(Loc.T("Design", "Look"), c.Theme.Subtitle(), Themes(c)));
        general.Children.Add(UI.Row(Loc.T("Sprache", "Language"), null,
            UI.Segmented(new (string, Language?)[] { (Loc.T("Automatisch", "Automatic"), null), ("Deutsch", Language.De), ("English", Language.En) },
                c.Language, v => { c.Language = v; Changed(); })));
        general.Children.Add(UI.Row(Loc.T("Mit Windows starten", "Start with Windows"), Loc.T("Startet still im Infobereich.", "Starts quietly in the notification area."),
            UI.Toggle(WindowsDefaults.StartsWithWindows, v => { WindowsDefaults.StartsWithWindows = v; Window.Redraw(); })));
        panel.Children.Add(UI.Card(general));
        return UI.Scroll(panel);
    }

    UIElement Themes(LauncherConfig c)
    {
        var row = new WrapPanel { MaxWidth = 440, HorizontalAlignment = HorizontalAlignment.Right };
        foreach (var t in Enum.GetValues<AppTheme>())
        {
            var theme = t;
            var p = Palette.Make(t);
            var swatch = new StackPanel { Orientation = Orientation.Horizontal };
            swatch.Children.Add(UI.Dot(p.PanelSurface, 12));
            var accent = UI.Dot(p.Accent, 12);
            accent.Margin = new Thickness(-4, 0, 6, 0);
            swatch.Children.Add(accent);
            swatch.Children.Add(UI.Text(t.Title(), 12, c.Theme == t ? Theme.OnAccent : Theme.TextPrimary, FontWeights.SemiBold));
            var chip = new Border
            {
                Child = swatch, Padding = new Thickness(8, 4, 10, 4), Margin = new Thickness(0, 0, 6, 6), CornerRadius = new CornerRadius(Theme.Radius(7)),
                Background = c.Theme == t ? Theme.Accent : UI.Hover, Cursor = System.Windows.Input.Cursors.Hand,
            };
            chip.MouseLeftButtonUp += (_, _) => { c.Theme = theme; Changed(); };
            row.Children.Add(chip);
        }
        return row;
    }
}
