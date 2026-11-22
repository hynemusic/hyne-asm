using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using HyneAsm.Core.Json;

namespace HyneAsm.Core.Tests;

public static partial class Fixtures
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
        ["search.quick_state"] = SearchQuickState,
        ["text.input"] = TextInputOps,
        ["keys.double_right_click"] = DoubleRightClick,
        ["keys.digit"] = input => new JsonArray(input!.AsArray()
            .Select(n => DigitKeys.Digit((ushort)n!.GetValue<double>()) is int d ? JsonValue.Create(d) : null).ToArray()),
        ["keys.shortcut_match"] = ShortcutMatch,
        ["keys.panel_bindings"] = PanelBindings,
        ["keys.translation"] = KeyTranslationOp,
        ["panel.state"] = PanelStateOp,
        ["panel.grid"] = PanelGridOp,
        ["entry.resolve"] = EntryResolve,
        ["browser.selection"] = EditScriptOp,
        ["edit.multi"] = EditScriptOp,
        ["edit.config"] = EditScriptOp,
        ["colors.labels"] = EditScriptOp,
        ["profiles.ops"] = EditScriptOp,
        ["les.parse"] = LesParse,
        ["les.query"] = LesQuery,
        ["les.match"] = LesMatch,
        ["files.hmlmenu"] = FilesMenu,
        ["files.hmlusage"] = FilesUsage,
        ["files.seen"] = FilesSeen,
        ["usage.summary"] = UsageSummaryOp,
        ["presets.match"] = PresetsMatch,
        ["remote.parse"] = RemoteParse,
        ["remote.link"] = RemoteLink,
        ["remote.request"] = RemoteRequestOp,
        ["bridge.protocol"] = BridgeProtocolOp,
        ["guards.main_window"] = GuardsMainWindow,
        ["guards.tooltip"] = GuardsTooltip,
        ["onboarding.steps"] = OnboardingSteps,
    };

    // MARK: Keys and text

    static int Int(JsonNode? n) => (int)n!.GetValue<double>();

    static readonly Dictionary<string, PanelKeyKind> SimpleKeys = new()
    {
        ["backspace"] = PanelKeyKind.Backspace, ["left"] = PanelKeyKind.Left, ["right"] = PanelKeyKind.Right, ["tab"] = PanelKeyKind.Tab,
        ["up"] = PanelKeyKind.Up, ["down"] = PanelKeyKind.Down, ["return"] = PanelKeyKind.ReturnKey, ["escape"] = PanelKeyKind.Escape,
        ["selectAll"] = PanelKeyKind.SelectAll, ["deleteWord"] = PanelKeyKind.DeleteWord, ["deleteToStart"] = PanelKeyKind.DeleteToStart,
    };

    /// <summary>A key as fixture JSON: a name, <c>{"digit": 4}</c> or <c>{"char": "é"}</c> (one Character).</summary>
    static PanelKey ParseKey(JsonNode? node)
    {
        if (node is JsonValue v && SimpleKeys.TryGetValue(v.GetValue<string>(), out var kind)) return PanelKey.Of(kind);
        if (node is JsonObject o && o["digit"] is JsonNode d) return PanelKey.OfDigit(Int(d));
        if (node is JsonObject c && c["char"] is JsonNode ch)
        {
            var s = Str(ch);
            if (Text.Count(s) != 1) throw new InvalidOperationException("char must be one Character: " + s);
            return PanelKey.OfCharacter(s);
        }
        throw new InvalidOperationException("unknown key " + node?.ToJsonString());
    }

    static string KeyName(PanelKey k) => k.Kind switch
    {
        PanelKeyKind.Digit => "digit " + k.Digit,
        PanelKeyKind.Character => "char " + k.Character,
        _ => SimpleKeys.First(p => p.Value == k.Kind).Key,
    };

    static KeyCombo Combo(JsonNode? n) => new((ushort)Int(n!["keyCode"]), (ModifierSet)(byte)Int(n["modifiers"]));

    static JsonObject ComboJson(KeyCombo c) => new() { ["keyCode"] = (int)c.KeyCode, ["modifiers"] = (int)c.Modifiers };

    static string CamelName<T>(T value) where T : struct, Enum
    {
        var n = value.ToString();
        return char.ToLowerInvariant(n[0]) + n[1..];
    }

    static JsonNode? TextInputOps(JsonNode? input)
    {
        var t = new TextInput(input!["initial"] is JsonNode i ? Str(i) : "");
        var steps = new JsonArray();
        foreach (var op in input["ops"]!.AsArray())
        {
            JsonNode? handled = null;
            if (op is JsonValue v && v.GetValue<string>() == "deselect") t.Deselect();
            else handled = JsonValue.Create(t.Apply(ParseKey(op)));
            steps.Add(new JsonObject { ["handled"] = handled, ["text"] = t.Text, ["selected"] = t.IsAllSelected });
        }
        return new JsonObject { ["steps"] = steps };
    }

    static JsonNode? DoubleRightClick(JsonNode? input)
    {
        var d = new DoubleRightClickDetector(TimeSpan.FromSeconds(input!["interval"]!.GetValue<double>()));
        var epoch = new DateTime(2000, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        return Strings(input["times"]!.AsArray().Select(t =>
            d.RightMouseDown(epoch + TimeSpan.FromSeconds(t!.GetValue<double>())) == ClickVerdict.OpenPanel ? "openPanel" : "passThrough"));
    }

    static JsonNode? ShortcutMatch(JsonNode? input)
    {
        var settings = input!["settings"] is JsonObject s ? Decode<ShortcutSettings>(s) : ShortcutSettings.Default;
        var matcher = new ShortcutMatcher(settings);
        var items = (input["items"]?.AsArray() ?? new JsonArray()).Select(i =>
            new ItemShortcut(Combo(i), new PluginItem(Str(i!["uri"]), Str(i["uri"]), ItemSource.Plugins, new List<string>()))).ToList();
        return new JsonArray(input["probes"]!.AsArray().Select(p =>
        {
            var c = Combo(p);
            var action = matcher.Match(c.KeyCode, c.Modifiers);
            var item = ShortcutMatcher.ItemShortcutFor(c.KeyCode, c.Modifiers, items);
            return (JsonNode?)new JsonObject { ["action"] = action is { } a ? CamelName(a) : null, ["item"] = item?.Uri };
        }).ToArray());
    }

    static JsonNode? PanelBindings(JsonNode? input) => WithGerman(() =>
    {
        var bindings = PanelKeyBindings.Default;
        if (input!["json"] is JsonObject j)
        {
            try { bindings = Decode<PanelKeyBindings>(j); }
            catch (Exception e) when (e is System.Text.Json.JsonException or InvalidOperationException) { return new JsonObject { ["error"] = true }; }
        }
        var perAction = new JsonObject();
        var labels = new JsonObject();
        foreach (var a in Enum.GetValues<PanelKeyAction>())
        {
            perAction[SwiftJson.RawValue(a)] = new JsonArray(bindings[a].Select(c => (JsonNode?)ComboJson(c)).ToArray());
            labels[SwiftJson.RawValue(a)] = a.Label();
        }
        var keys = input["probes"]!.AsArray().Select(p => bindings.Key(Combo(p)) is { } k ? JsonValue.Create(KeyName(k)) : null);
        return new JsonObject { ["bindings"] = perAction, ["keys"] = new JsonArray(keys.ToArray()), ["labels"] = labels };
    });

    static JsonNode? SearchQuickState(JsonNode? input) => WithGerman(() =>
    {
        var items = Decode<List<PluginItem>>(input!["items"]);
        var config = Decode<LauncherConfig>(input["config"]);
        var usage = new Dictionary<string, int>(Text.Canonical);
        foreach (var pair in input["usage"]?.AsArray() ?? new JsonArray()) usage[Str(pair![0])] = Int(pair[1]);
        var state = new QuickSearchState(new QuickSearch(config, items, usage));
        JsonNode Snapshot(string action) => new JsonObject
        {
            ["action"] = action, ["query"] = state.Query, ["selected"] = state.IsQuerySelected, ["highlighted"] = state.Highlighted,
            ["titles"] = Strings(state.Results.Select(r => r.Row.Title)),
        };
        var steps = new JsonArray { Snapshot("start") };
        foreach (var k in input["keys"]!.AsArray())
        {
            var result = state.Handle(ParseKey(k));
            steps.Add(Snapshot(result.Kind switch
            {
                PanelActionKind.None => "none",
                PanelActionKind.Close => "close",
                _ => "insert " + result.Row!.UsageKey,
            }));
        }
        return steps;
    });

    /// <summary><c>{mac:{keyCode,modifiers}}</c> → <c>{windows:{vk,modifiers}|null}</c>, and <c>{windows}</c> → <c>{mac|null}</c> (hand-written expected).</summary>
    static JsonNode? KeyTranslationOp(JsonNode? input)
    {
        if (input!["mac"] is JsonNode mac)
            return new JsonObject
            {
                ["windows"] = KeyTranslation.ToWindows(Combo(mac)) is var (vk, mods)
                    ? new JsonObject { ["vk"] = (int)vk, ["modifiers"] = (int)mods } : null,
            };
        var w = input["windows"]!;
        return new JsonObject
        {
            ["mac"] = KeyTranslation.FromWindows((ushort)Int(w["vk"]), (WinModifiers)(byte)Int(w["modifiers"])) is { } c ? ComboJson(c) : null,
        };
    }

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
        return WithGerman(() =>
            JsonValue.Create(ReplaceGenerated(SwiftJson.Serialize(SwiftJson.Deserialize<LauncherConfig>(text), pretty: true), text)));
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
