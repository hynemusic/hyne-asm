using System.Linq;
using System.Windows;
using System.Windows.Controls;
using HyneAsm.Core;

namespace HyneAsm.App.Settings;

/// <summary>Page "Shape Search": type a search, see the results exactly as the quick search ranks them, and pin,
/// reorder or hide results for that search term. The rules apply to the panel filter and the quick search.</summary>
sealed class SearchPage : Page
{
    readonly TextBox query;
    readonly StackPanel results = new();

    public SearchPage(AppModel model, SettingsWindow window) : base(model, window)
    {
        query = UI.TextBox("", Loc.T("Suchbegriff, z. B. „comp“ oder „serum“", "Search term, e.g. “comp” or “serum”"));
        query.Width = 360;
        query.HorizontalAlignment = HorizontalAlignment.Left;
        query.TextChanged += (_, _) => FillResults();
    }

    public override UIElement Build()
    {
        var panel = new StackPanel { Margin = new Thickness(28, 22, 28, 22), MaxWidth = 820, HorizontalAlignment = HorizontalAlignment.Left };
        panel.Children.Add(UI.Title(Loc.T("Suche formen", "Shape Search")));
        panel.Children.Add(UI.Caption(Loc.T("Pinne Treffer für einen Suchbegriff nach oben oder blende sie aus. Eine Regel für „ser“ gilt auch für „seru“, „serum“ … – die längste passende gewinnt.",
                                            "Pin results for a search term to the top or hide them. A rule for “ser” also applies to “seru”, “serum” … – the longest matching rule wins.")));
        if (query.Parent is Panel old) old.Children.Remove(query);
        query.Margin = new Thickness(0, 14, 0, 8);
        panel.Children.Add(query);
        if (results.Parent is Panel oldResults) oldResults.Children.Remove(results);
        panel.Children.Add(results);
        FillResults();

        panel.Children.Add(UI.Section(Loc.T("Deine Regeln", "Your rules")));
        var rules = new StackPanel();
        if (Model.Config.SearchRules.Count == 0) rules.Children.Add(UI.Caption(Loc.T("Noch keine.", "None yet.")));
        foreach (var rule in Model.Config.SearchRules.ToList())
        {
            var buttons = new StackPanel { Orientation = Orientation.Horizontal };
            buttons.Children.Add(UI.Button(Loc.T("Zeigen", "Show"), () => query.Text = rule.Query));
            buttons.Children.Add(UI.IconButton("", () => { Model.Config.RemoveSearchRule(rule.Id); Changed(); }, Loc.T("Regel löschen", "Delete rule")));
            rules.Children.Add(UI.Row("„" + rule.Query + "“",
                Loc.T($"{rule.Pinned.Count} angepinnt · {rule.Hidden.Count} ausgeblendet", $"{rule.Pinned.Count} pinned · {rule.Hidden.Count} hidden"), buttons));
        }
        panel.Children.Add(UI.Card(rules));
        return UI.Scroll(panel);
    }

    void FillResults()
    {
        results.Children.Clear();
        var q = query.Text.Trim();
        if (q.Length == 0) return;
        var rule = Model.Config.SearchRuleExactly(q);
        var list = new StackPanel();
        var hits = new QuickSearch(Model.Config, Model.SearchIndex, Model.Usage.Counts).Results(q).Take(25).ToList();
        if (hits.Count == 0) list.Children.Add(UI.Caption(Loc.T("Keine Treffer.", "No results.")));
        for (var i = 0; i < hits.Count; i++)
        {
            var row = hits[i].Row;
            var key = row.UsageKey;
            var pinned = rule?.Pinned.Contains(key) == true;
            var buttons = new StackPanel { Orientation = Orientation.Horizontal };
            if (pinned)
            {
                buttons.Children.Add(UI.IconButton("", () => { Model.Config.MovePinnedSearchResult(key, -1, q); Changed(); }, Loc.T("Höher", "Up")));
                buttons.Children.Add(UI.IconButton("", () => { Model.Config.MovePinnedSearchResult(key, 1, q); Changed(); }, Loc.T("Tiefer", "Down")));
                buttons.Children.Add(UI.Button(Loc.T("Lösen", "Unpin"), () => { Model.Config.UnpinSearchResult(key, q); Changed(); }));
            }
            else buttons.Children.Add(UI.Button(Loc.T("Anpinnen", "Pin"), () => { Model.Config.PinSearchResult(key, q); Changed(); }, icon: ""));
            buttons.Children.Add(UI.Button(Loc.T("Ausblenden", "Hide"), () => { Model.Config.HideSearchResult(key, q); Changed(); }, icon: ""));
            var title = $"{i + 1}.  " + row.Title + (pinned ? "  📌" : "");
            list.Children.Add(UI.Row(title, hits[i].Place ?? PluginGrouping.FormatLabel(new PluginItem(row.Uri, row.Name, row.Source, row.Path)), buttons));
        }
        if (rule is { Hidden.Count: > 0 })
        {
            list.Children.Add(UI.Section(Loc.T("Ausgeblendet", "Hidden")));
            foreach (var key in rule.Hidden.ToList())
                list.Children.Add(UI.Row(UsageStats.ReadableName(key), null,
                    UI.Button(Loc.T("Wieder zeigen", "Show again"), () => { Model.Config.UnhideSearchResult(key, q); Changed(); })));
        }
        results.Children.Add(UI.Card(list));
    }
}
