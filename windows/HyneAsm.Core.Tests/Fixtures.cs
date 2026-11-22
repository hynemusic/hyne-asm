using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using HyneAsm.Core.Json;

namespace HyneAsm.Core.Tests;

public static class Fixtures
{
    /// <summary>One handler per fixture area. Later tasks add entries here.</summary>
    public static readonly Dictionary<string, Func<JsonNode?, JsonNode?>> Handlers = new()
    {
        ["smoke.echo"] = input => input?.DeepClone(),
        ["config.roundtrip"] = ConfigRoundtrip,
        ["config.migrate"] = ConfigMigrate,
        ["search.score"] = SearchScore,
        ["search.vocabulary"] = input => Strings(SearchVocabulary.Icons(Str(input)).Order(StringComparer.Ordinal)),
        ["search.popularity"] = input => JsonValue.Create(Popularity.Score(Str(input))),
        ["search.tuning"] = SearchTuningOp,
        ["variants.collapse"] = VariantsCollapse,
        ["variants.channel"] = input =>
        {
            var (b, label) = PluginVariants.Channel(Str(input));
            return new JsonObject { ["base"] = b, ["label"] = label };
        },
        ["plugins.groups"] = PluginsGroups,
        ["icons.guess"] = input => Strings(Decode<List<PluginItem>>(input).Select(IconGuesser.Guess)),
        ["icons.catalog"] = _ => new JsonObject
        {
            ["all"] = Strings(IconCatalog.AllIDs), ["defaultID"] = IconCatalog.DefaultID, ["folderID"] = IconCatalog.FolderID,
        },
        ["search.index"] = SearchIndexRows,
        ["search.quick"] = SearchQuick,
    };

    /// <summary>Config text → decode → <c>ConfigStore.Migrate</c> → encode as <c>Save</c> does.</summary>
    static JsonNode? ConfigMigrate(JsonNode? input)
    {
        var text = Str(input);
        return WithGerman(() =>
        {
            var config = SwiftJson.Deserialize<LauncherConfig>(text);
            ConfigStore.Migrate(config);
            return JsonValue.Create(ReplaceGenerated(SwiftJson.Serialize(config, pretty: true), text));
        });
    }

    // MARK: Search and plugin lists (same shapes as the Swift handlers)

    static string Str(JsonNode? node) => node!.GetValue<string>();

    static List<string> StrList(JsonNode? node) => node is JsonArray a ? a.Select(Str).ToList() : new();

    static JsonArray Strings(IEnumerable<string> values) => new(values.Select(v => (JsonNode?)JsonValue.Create(v)).ToArray());

    static T Decode<T>(JsonNode? node) => SwiftJson.Deserialize<T>(node!.ToJsonString());

    /// <summary>Loc.Language is global: handlers that need German hold a lock, so parallel tests can't see each other's language.</summary>
    static readonly object LanguageLock = new();

    static JsonNode? WithGerman(Func<JsonNode?> body)
    {
        lock (LanguageLock)
        {
            var saved = Loc.Language;
            Loc.Language = Language.De;
            try { return body(); }
            finally { Loc.Language = saved; }
        }
    }

    static JsonNode? SearchScore(JsonNode? input)
    {
        string name = Str(input!["name"]), query = Str(input["query"]);
        var score = input["iconID"] is JsonNode icon
            ? SearchMatcher.Score(new SearchMatcher.Prepared(name), new SearchMatcher.Prepared(query), Str(icon), SearchVocabulary.Icons(query))
            : SearchMatcher.Score(name, query);
        return score is int s ? JsonValue.Create(s) : null;
    }

    static JsonObject RuleJSON(SearchRule r) => new() { ["query"] = r.Query, ["pinned"] = Strings(r.Pinned), ["hidden"] = Strings(r.Hidden) };

    static JsonNode? SearchTuningOp(JsonNode? input)
    {
        var o = input!.AsObject();
        if (o["normalize"] is JsonNode n) return SearchTuning.Normalize(Str(n));
        if (o["rule"] is JsonValue q)
            return SearchTuning.Rule(Str(q), StrList(o["rules"]).Select(r => new SearchRule(r)).ToList())?.Query;
        if (o["apply"] is JsonArray apply)
        {
            var rule = o["rule"] is JsonObject r ? new SearchRule(Str(r["query"]), StrList(r["pinned"]), StrList(r["hidden"])) : null;
            var inject = new HashSet<string>(StrList(o["inject"]), Text.Canonical);
            return Strings(SearchTuning.Apply(StrList(apply), k => k, rule, k => inject.Contains(k) ? k : null));
        }
        var c = LauncherConfig.MakeDefault();
        foreach (var op in o["edit"]!.AsArray())
        {
            string key = Str(op!["key"]), query = Str(op["query"]);
            switch (Str(op["op"]))
            {
                case "pin": c.PinSearchResult(key, query); break;
                case "unpin": c.UnpinSearchResult(key, query); break;
                case "hide": c.HideSearchResult(key, query); break;
                case "unhide": c.UnhideSearchResult(key, query); break;
                case "move": c.MovePinnedSearchResult(key, op["by"]!.GetValue<int>(), query); break;
                default: throw new InvalidOperationException("search.tuning: unknown op");
            }
        }
        return new JsonArray(c.SearchRules.Select(r => (JsonNode?)RuleJSON(r)).ToArray());
    }

    static JsonNode? VariantsCollapse(JsonNode? input)
    {
        var items = Decode<List<PluginItem>>(input);
        var keys = new PluginVariants.Keys(items);
        var groups = PluginVariants.Collapse(items).Select(g => (JsonNode?)new JsonObject
        {
            ["variants"] = Strings(g.Variants.Select(v => v.Uri)),
            ["formats"] = Strings(g.Formats),
            ["channels"] = Strings(g.Channels),
            ["labels"] = Strings(g.Variants.Select(PluginVariants.Label)),
        });
        return new JsonObject { ["groups"] = new JsonArray(groups.ToArray()), ["keys"] = Strings(items.Select(keys.Key)) };
    }

    static JsonNode? PluginsGroups(JsonNode? input) => WithGerman(() =>
    {
        var items = Decode<List<PluginItem>>(input!["items"]);
        var groups = PluginGrouping.Groups(items, Str(input["search"]))
            .Select(g => (JsonNode?)new JsonObject { ["title"] = g.Title, ["items"] = Strings(g.Items.Select(i => i.Uri)) });
        return new JsonObject
        {
            ["groups"] = new JsonArray(groups.ToArray()), ["formatLabels"] = Strings(items.Select(PluginGrouping.FormatLabel)),
        };
    });

    static JsonObject RowJSON(PanelRow r)
    {
        var o = new JsonObject
        {
            ["title"] = r.Title, ["uri"] = r.Uri, ["name"] = r.Name, ["iconID"] = r.IconID, ["usageKey"] = r.UsageKey,
            ["isGlobal"] = r.IsGlobal, ["isAvailable"] = r.IsAvailable, ["isNew"] = r.IsNew, ["path"] = Strings(r.Path),
        };
        if (r.ColorID != null) o["colorID"] = r.ColorID;
        if (r.Chain != null) o["chain"] = Strings(r.Chain);
        if (r.Action != null) o["action"] = r.Action.Title;
        return o;
    }

    static JsonNode? SearchIndexRows(JsonNode? input)
    {
        var items = Decode<List<PluginItem>>(input!["items"]);
        var config = input["config"] is JsonObject c ? Decode<LauncherConfig>(c) : LauncherConfig.MakeDefault();
        var index = new SearchIndex(items, config, new HashSet<string>(StrList(input["newURIs"]), Text.Canonical));
        var rows = index.GlobalRows.Select(r =>
        {
            var o = RowJSON(r);
            o["alternatives"] = Strings(index.Alternatives(r.UsageKey).Select(a => a.Uri));
            o["popularity"] = Popularity.Score(r.Title);
            return (JsonNode?)o;
        });
        return new JsonObject
        {
            ["rows"] = new JsonArray(rows.ToArray()),
            ["usageKeys"] = new JsonArray(items.Select(i => (JsonNode?)(index.UsageKey.TryGetValue(i.Uri, out var k) ? k : null)).ToArray()),
        };
    }

    /// <summary><c>{items, config, usage: [[key, count]], queries}</c> → <c>[{query, results}]</c> (German action titles).</summary>
    public static JsonNode? SearchQuick(JsonNode? input) => WithGerman(() =>
    {
        var items = Decode<List<PluginItem>>(input!["items"]);
        var config = Decode<LauncherConfig>(input["config"]);
        var usage = new Dictionary<string, int>(Text.Canonical);
        foreach (var pair in input["usage"]?.AsArray() ?? new JsonArray()) usage[Str(pair![0])] = pair[1]!.GetValue<int>();
        var search = new QuickSearch(config, items, usage);
        return new JsonArray(StrList(input["queries"]).Select(q => (JsonNode?)new JsonObject
        {
            ["query"] = q,
            ["results"] = new JsonArray(search.Results(q).Select(r =>
            {
                var o = RowJSON(r.Row);
                if (r.Place != null) o["place"] = r.Place;
                return (JsonNode?)o;
            }).ToArray()),
        }).ToArray());
    });

    /// <summary>Config text → decode → encode as <c>ConfigStore.Save</c> does; generated ids/token → NEW-n / NEW-TOKEN.</summary>
    static JsonNode? ConfigRoundtrip(JsonNode? input)
    {
        var text = input!.GetValue<string>();
        var saved = Loc.Language;
        Loc.Language = Language.De;
        try
        {
            var output = SwiftJson.Serialize(SwiftJson.Deserialize<LauncherConfig>(text), pretty: true);
            return JsonValue.Create(ReplaceGenerated(output, text));
        }
        finally { Loc.Language = saved; }
    }

    /// <summary>Same as the Swift runner: UUIDs (and the Stream Deck token) in <paramref name="output"/> that are
    /// not in <paramref name="input"/> become NEW-1, NEW-2 … in order of first appearance, and NEW-TOKEN.</summary>
    public static string ReplaceGenerated(string output, string input)
    {
        var known = input.ToUpperInvariant();
        var result = output;
        var token = Regex.Match(result, "\"streamDeckToken\" : \"([0-9a-f]{20})\"");
        if (token.Success && !input.Contains(token.Groups[1].Value, StringComparison.Ordinal))
            result = result.Remove(token.Groups[1].Index, token.Groups[1].Length).Insert(token.Groups[1].Index, "NEW-TOKEN");
        var names = new Dictionary<string, string>();
        foreach (Match m in Regex.Matches(result, "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"))
            if (!known.Contains(m.Value, StringComparison.Ordinal) && !names.ContainsKey(m.Value))
                names[m.Value] = "NEW-" + (names.Count + 1);
        foreach (var (id, name) in names) result = result.Replace(id, name, StringComparison.Ordinal);
        return result;
    }

    public static string FixturesDir()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            var candidate = Path.Combine(dir.FullName, "spec", "fixtures");
            if (Directory.Exists(candidate)) return candidate;
            dir = dir.Parent;
        }
        throw new DirectoryNotFoundException("spec/fixtures not found above " + AppContext.BaseDirectory);
    }

    public static IEnumerable<(string File, string Area, string CaseName, JsonNode? Input, JsonNode? Expected)> All()
    {
        foreach (var path in Directory.GetFiles(FixturesDir(), "*.json").OrderBy(p => p, StringComparer.Ordinal))
        {
            var root = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
            var area = root["area"]!.GetValue<string>();
            foreach (var c in root["cases"]!.AsArray())
            {
                var o = c!.AsObject();
                yield return (Path.GetFileName(path), area, o["name"]!.GetValue<string>(),
                    o["input"]?.DeepClone(), o["expected"]?.DeepClone());
            }
        }
    }
}
