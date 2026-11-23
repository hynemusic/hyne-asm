using System.Linq;
using System.Windows;
using System.Windows.Controls;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Page "Shape Search": type a search, see the results exactly as the quick search ranks them, and pin,
/// reorder or hide results for that search term. The rules apply to the panel filter and the quick search.</summary>
sealed class SearchPage : Page
{
    readonly FrameworkElement field;
    readonly TextBox query;
    readonly ContentControl results = new();

    public SearchPage(AppModel model, SettingsWindow window) : base(model, window)
    {
        (field, query) = UI.SearchField("", Loc.T("Suchbegriff, z. B. „comp“ oder „serum“", "Search term, e.g. “comp” or “serum”"));
        query.TextChanged += (_, _) => FillResults();
    }

    public override UIElement Build()
    {
        var panel = new StackPanel();
        panel.Children.Add(UI.PageHeader(Loc.T("Suche formen", "Shape Search"),
            Loc.T("Pinne Treffer für einen Suchbegriff nach oben oder blende sie aus. Eine Regel für „ser“ gilt auch für „seru“, „serum“ … – die längste passende gewinnt.",
                  "Pin results for a search term to the top or hide them. A rule for “ser” also applies to “seru”, “serum” … – the longest matching rule wins.")));
        if (field.Parent is Panel old) old.Children.Remove(field);
        // A big field: the search is the point of this page.
        field.HorizontalAlignment = HorizontalAlignment.Stretch;
        field.MinHeight = 48;
        query.FontSize = 17;
        panel.Children.Add(field);
        if (results.Parent is Panel oldResults) oldResults.Children.Remove(results);
        results.Margin = new Thickness(0, 14, 0, 0);
        panel.Children.Add(results);
        FillResults();

        panel.Children.Add(UI.Label(Loc.T("Deine Regeln", "Your rules")));
        if (Model.Config.SearchRules.Count == 0) panel.Children.Add(UI.Card(UI.Row(Loc.T("Noch keine", "None yet"), null, null)));
        else panel.Children.Add(UI.Card(Model.Config.SearchRules.ToList().Select(rule =>
        {
            var buttons = new StackPanel { Orientation = Orientation.Horizontal };
            buttons.Children.Add(UI.SmallButton(Loc.T("Zeigen", "Show"), () => query.Text = rule.Query));
            buttons.Children.Add(UI.IconButton("", () => { Model.Config.RemoveSearchRule(rule.Id); Changed(); }, Loc.T("Regel löschen", "Delete rule")));
            return (UIElement)UI.Row("„" + rule.Query + "“", Loc.T($"{rule.Pinned.Count} angepinnt · {rule.Hidden.Count} ausgeblendet", $"{rule.Pinned.Count} pinned · {rule.Hidden.Count} hidden"), buttons);
        }).ToArray()));
        return UI.PageColumn(panel);
    }

    void FillResults()
    {
        var q = query.Text.Trim();
        if (q.Length == 0) { results.Content = null; return; }
        var rule = Model.Config.SearchRuleExactly(q);
        var hits = new QuickSearch(Model.Config, Model.SearchIndex, Model.Usage.Counts).Results(q).Take(25).ToList();
        var rows = hits.Select((h, i) =>
        {
            var row = h.Row;
            var key = row.UsageKey;
            var pinned = rule?.Pinned.Contains(key) == true;
            var buttons = new StackPanel { Orientation = Orientation.Horizontal };
            if (pinned)
            {
                buttons.Children.Add(UI.IconButton("", () => { Model.Config.MovePinnedSearchResult(key, -1, q); Changed(); }, Loc.T("Höher", "Up")));
                buttons.Children.Add(UI.IconButton("", () => { Model.Config.MovePinnedSearchResult(key, 1, q); Changed(); }, Loc.T("Tiefer", "Down")));
                buttons.Children.Add(UI.SmallButton(Loc.T("Lösen", "Unpin"), () => { Model.Config.UnpinSearchResult(key, q); Changed(); }));
            }
            else buttons.Children.Add(UI.SmallButton(Loc.T("Anpinnen", "Pin"), () => { Model.Config.PinSearchResult(key, q); Changed(); }, ""));
            buttons.Children.Add(UI.IconButton("", () => { Model.Config.HideSearchResult(key, q); Changed(); }, Loc.T("Ausblenden", "Hide")));
            var lead = UI.Text($"{i + 1}", 12.5, pinned ? Theme.Accent : Theme.TextTertiary);
            lead.Width = 22;
            return (UIElement)UI.Row(row.Title, h.Place ?? PluginGrouping.FormatLabel(new PluginItem(row.Uri, row.Name, row.Source, row.Path)), buttons, lead, 52);
        }).ToList();
        if (rows.Count == 0) rows.Add(UI.Row(Loc.T("Keine Treffer", "No results"), null, null));
        if (rule is { Hidden.Count: > 0 })
            foreach (var key in rule.Hidden.ToList())
                rows.Add(UI.Row(UsageStats.ReadableName(key), Loc.T("ausgeblendet", "hidden"), UI.SmallButton(Loc.T("Wieder zeigen", "Show again"), () => { Model.Config.UnhideSearchResult(key, q); Changed(); })));
        results.Content = UI.Card(rows.ToArray());
    }
}
