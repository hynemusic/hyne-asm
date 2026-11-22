using System.Text.Json;
using System.Text.Json.Nodes;
using HyneAsm.Core.Json;

namespace HyneAsm.Core.Tests;

/// <summary>Fixture handlers for the panel, menu editing, colors and profiles — the same input shapes as
/// Tests/HMLauncherCoreTests/SharedFixtureEditing.swift.</summary>
public static partial class Fixtures
{
    // MARK: Items and edit scripts

    static bool IsNull(JsonNode? n) => n is null || n.GetValueKind() == JsonValueKind.Null;

    static bool IsNumber(JsonNode? n) => n is JsonValue && n.GetValueKind() == JsonValueKind.Number;

    static bool IsTrue(JsonNode? n) => n is JsonValue && n.GetValueKind() == JsonValueKind.True;

    static bool IsFalse(JsonNode? n) => n is JsonValue && n.GetValueKind() == JsonValueKind.False;

    /// <summary><c>{name, uri?, source?, path?}</c>; uri defaults to "u:&lt;name&gt;", source to plugins.</summary>
    static PluginItem FixtureItem(JsonNode? v)
    {
        var name = Str(v!["name"]);
        var uri = v["uri"] is JsonNode u ? Str(u) : "u:" + name;
        var source = v["source"] is JsonNode s ? Decode<ItemSource>(s) : ItemSource.Plugins;
        return new PluginItem(uri, name, source, StrList(v["path"]));
    }

    /// <summary>Runs ops on a config; references as described in the Swift <c>EditScript</c>.</summary>
    sealed class EditScript
    {
        public LauncherConfig Config;
        readonly JsonObject items;
        readonly Dictionary<string, Guid> vars = new();

        public EditScript(JsonNode input)
        {
            Config = input["config"] is JsonObject c ? Decode<LauncherConfig>(c) : LauncherConfig.MakeDefault();
            items = input["items"] as JsonObject ?? new JsonObject();
        }

        public PluginItem Item(JsonNode? v)
        {
            if (v is JsonValue s && s.GetValueKind() == JsonValueKind.String)
                return FixtureItem(items[s.GetValue<string>()] ?? throw new InvalidOperationException("unknown item " + s));
            return FixtureItem(v);
        }

        public List<PluginItem> ItemList(JsonNode? v) => v is JsonArray a ? a.Select(Item).ToList() : new();

        Guid? Variable(string s)
        {
            if (!s.StartsWith('$')) return null;
            return vars.TryGetValue(s[1..], out var id) ? id : throw new InvalidOperationException("unbound " + s);
        }

        public Guid Category(JsonNode? v)
        {
            if (IsNumber(v)) return Config.Categories[Int(v)].Id;
            var s = Str(v);
            if (Variable(s) is { } id) return id;
            if (s == "favorites") return Config.FavoritesID;
            if (Guid.TryParse(s, out var g)) return g;
            return (Config.Categories.FirstOrDefault(c => Text.Equal(c.Name, s)) ?? throw new InvalidOperationException("no category " + s)).Id;
        }

        public Guid Entry(JsonNode? v, Guid categoryID)
        {
            var s = Str(v);
            if (Variable(s) is { } id) return id;
            if (Guid.TryParse(s, out var g)) return g;
            foreach (var e in Config.OrderedEntryIDs(categoryID))
                if (Text.Equal(Config.FindEntry(e, categoryID)?.Title, s)) return e;
            throw new InvalidOperationException("no entry " + s);
        }

        Guid? OptionalEntry(JsonNode? v, Guid categoryID) => IsNull(v) ? null : Entry(v, categoryID);

        List<Guid> Entries(JsonNode? v, Guid categoryID) => v is JsonArray a ? a.Select(e => Entry(e, categoryID)).ToList() : new();

        Guid Profile(JsonNode? v)
        {
            if (IsNumber(v)) return Config.Profiles[Int(v)].Id;
            var s = Str(v);
            return Variable(s) ?? (Guid.TryParse(s, out var g) ? g : throw new InvalidOperationException("bad profile " + s));
        }

        static LiveAction Action(JsonNode? v) => Decode<LiveAction>(v);

        static ColorRule Rule(JsonNode? v) =>
            v is JsonValue s && s.GetValueKind() == JsonValueKind.String && s.GetValue<string>() == "live"
                ? new ColorRule.LiveDevices() : new ColorRule.Vendor(Str(v!["vendor"]));

        static string? OptionalString(JsonNode? v) => IsNull(v) ? null : Str(v);

        static JsonNode? Id(Guid? id) => id is { } g ? JsonValue.Create(g.ToString().ToUpperInvariant()) : null;

        JsonNode? Bind(JsonNode op, Guid? id)
        {
            if (op["as"] is JsonNode name && id is { } g) vars[Str(name)] = g;
            return Id(id);
        }

        /// <summary>One op; returns what the method returns (ids as strings), or null.</summary>
        public JsonNode? Run(JsonNode op)
        {
            var c = Config;
            switch (Str(op["op"]))
            {
                // ConfigEditing
                case "addEntry":
                {
                    var cat = Category(op["cat"]);
                    c.AddEntry(Item(op["item"]), cat, OptionalEntry(op["folder"], cat));
                    break;
                }
                case "addChain":
                {
                    var cat = Category(op["cat"]);
                    return Bind(op, c.AddChain(Str(op["name"]), ItemList(op["steps"]), cat, OptionalEntry(op["folder"], cat)));
                }
                case "updateChain":
                {
                    var cat = Category(op["cat"]);
                    c.UpdateChain(Entry(op["entry"], cat), cat, Str(op["name"]), ItemList(op["steps"]));
                    break;
                }
                case "updateAction":
                {
                    var cat = Category(op["cat"]);
                    c.UpdateAction(Entry(op["entry"], cat), cat, Action(op["action"]));
                    break;
                }
                case "addAction":
                {
                    var cat = Category(op["cat"]);
                    c.AddAction(Action(op["action"]), cat, OptionalEntry(op["folder"], cat));
                    break;
                }
                case "addFolder": return Bind(op, c.AddFolder(Str(op["name"]), Category(op["cat"])));
                case "removeEntry":
                {
                    var cat = Category(op["cat"]);
                    c.RemoveEntry(Entry(op["entry"], cat), cat);
                    break;
                }
                case "moveEntry":
                {
                    var cat = Category(op["cat"]);
                    c.MoveEntry(cat, OptionalEntry(op["folder"], cat), Int(op["from"]), Int(op["to"]));
                    break;
                }
                case "moveToFolder":
                {
                    var cat = Category(op["cat"]);
                    c.MoveEntry(Entry(op["entry"], cat), OptionalEntry(op["folder"], cat), cat);
                    break;
                }
                case "renameFolder":
                {
                    var cat = Category(op["cat"]);
                    c.RenameFolder(Entry(op["folder"], cat), cat, Str(op["name"]));
                    break;
                }
                case "dissolveFolder":
                {
                    var cat = Category(op["cat"]);
                    c.DissolveFolder(Entry(op["folder"], cat), cat);
                    break;
                }
                case "addCategory": return Bind(op, c.AddCategory(Str(op["name"])));
                case "renameCategory": c.RenameCategory(Category(op["cat"]), Str(op["name"])); break;
                case "deleteCategory": c.DeleteCategory(Category(op["cat"])); break;
                case "moveCategory": c.MoveCategory(Int(op["from"]), Int(op["to"])); break;
                case "moveCategoryBefore": c.MoveCategory(Category(op["cat"]), IsNull(op["before"]) ? null : Category(op["before"])); break;
                case "setIcon":
                {
                    var cat = Category(op["cat"]);
                    c.SetIcon(Str(op["icon"]), Entry(op["entry"], cat), cat);
                    break;
                }
                case "setDisplayName":
                {
                    var cat = Category(op["cat"]);
                    c.SetDisplayName(OptionalString(op["name"]), Entry(op["entry"], cat), cat);
                    break;
                }
                case "allPluginEntries": return Strings(c.AllPluginEntries.Select(e => e.Title));
                case "favoritesID": return Id(c.FavoritesID);
                case "favoriteEntry":
                {
                    var row = new PanelRow { Uri = Str(op["uri"]), IsAvailable = true, FolderID = IsTrue(op["folderRow"]) ? Guid.NewGuid() : null };
                    return Id(c.FavoriteEntry(row, ItemList(op["installed"]))?.Id);
                }
                // MultiEdit
                case "orderedEntryIDs":
                    return new JsonArray(c.OrderedEntryIDs(Category(op["cat"])).Select(id => Id(id)).ToArray());
                case "moveEntries":
                {
                    var cat = Category(op["cat"]);
                    c.MoveEntries(Entries(op["entries"], cat), OptionalEntry(op["folder"], cat), OptionalEntry(op["before"], cat), cat);
                    break;
                }
                case "moveEntriesToCategory":
                {
                    var from = Category(op["from"]);
                    c.MoveEntries(Entries(op["entries"], from), Category(op["to"]), from);
                    break;
                }
                case "groupEntries":
                {
                    var cat = Category(op["cat"]);
                    return Bind(op, c.GroupEntries(Entries(op["entries"], cat), cat, Str(op["name"])));
                }
                // BrowserSelection
                case "addSelection":
                {
                    var cat = Category(op["cat"]);
                    var folders = (op["folders"] as JsonArray ?? new JsonArray())
                        .Select(f => new BrowserSelection.Folder(Str(f!["title"]), ItemList(f["items"])));
                    var actions = (op["actions"] as JsonArray ?? new JsonArray()).Select(Action);
                    var selection = new BrowserSelection(folders, ItemList(op["items"]), actions);
                    c.Add(selection, cat, OptionalEntry(op["folder"], cat), asFolders: !IsFalse(op["asFolders"]));
                    return new JsonObject { ["pluginCount"] = selection.PluginCount, ["isEmpty"] = selection.IsEmpty };
                }
                // ColorLabels
                case "setColor":
                {
                    var cat = Category(op["cat"]);
                    c.SetColor(OptionalString(op["color"]), Entry(op["entry"], cat), cat);
                    break;
                }
                case "setColorRule": c.SetColorRule(OptionalString(op["color"]), Rule(op["rule"])); break;
                case "colorOf":
                {
                    var cat = Category(op["cat"]);
                    return c.FindEntry(Entry(op["entry"], cat), cat) is { } e ? c.ColorID(e) : null;
                }
                case "colorOfItem": return c.ColorID(Item(op["item"]));
                case "colorRule": return c.GetColorRule(Rule(op["rule"]));
                case "rulesForItem": return Strings(ColorRule.ForItem(Item(op["item"])).Select(r => r.Key));
                case "palette":
                    return new JsonArray(ColorPalette.All.Select(d => (JsonNode?)new JsonObject
                    {
                        ["id"] = d.Id, ["label"] = d.Label, ["red"] = d.Red, ["green"] = d.Green, ["blue"] = d.Blue,
                    }).ToArray());
                case "color": return ColorPalette.Color(OptionalString(op["id"]))?.Id;
                // Profiles
                case "addProfile": return Bind(op, c.AddProfile(Str(op["name"]), IsTrue(op["copy"])));
                case "switchProfile": c.SwitchProfile(Profile(op["profile"])); break;
                case "nextProfile": c.SwitchToNextProfile(); break;
                case "renameProfile": c.RenameProfile(Profile(op["profile"]), Str(op["name"])); break;
                case "deleteProfile": c.DeleteProfile(Profile(op["profile"])); break;
                case "activeProfile":
                    return new JsonObject { ["id"] = Id(c.ActiveProfile.Id), ["name"] = c.ActiveProfile.Name };
                // Search rules (set up for panel.state)
                case "pin": c.PinSearchResult(Str(op["key"]), Str(op["query"])); break;
                case "hide": c.HideSearchResult(Str(op["key"]), Str(op["query"])); break;
                default: throw new InvalidOperationException("unknown op " + Str(op["op"]));
            }
            return null;
        }
    }

    /// <summary>A model value as fixture JSON (its Codable form).</summary>
    static JsonNode? Json(object value) => JsonNode.Parse(SwiftJson.Serialize(value));

    /// <summary>Ids the run generated (not in <paramref name="input"/>) → NEW-1, NEW-2 … in order of appearance in
    /// the canonical (sorted-key) text, as the Swift runner does.</summary>
    static JsonNode? NormalizeGenerated(JsonNode output, JsonNode input) =>
        JsonNode.Parse(ReplaceGenerated(SwiftJson.Serialize(output, pretty: true), SwiftJson.Serialize(input, pretty: true)));

    /// <summary><c>{config?, items?, ops, show?}</c> → <c>{results, categories, …show}</c> (German UI strings).</summary>
    static JsonNode? EditScriptOp(JsonNode? input) => WithGerman(() =>
    {
        var script = new EditScript(input!);
        var results = new JsonArray(input!["ops"]!.AsArray().Select(op => script.Run(op!)).ToArray());
        var c = script.Config;
        var output = new JsonObject { ["results"] = results, ["categories"] = Json(c.Categories) };
        foreach (var key in StrList(input["show"]))
            output[key] = key switch
            {
                "colorRules" => Json(c.ColorRules),
                "profiles" => Json(c.Profiles),
                "activeProfileID" => c.ActiveProfileID.ToString().ToUpperInvariant(),
                _ => throw new InvalidOperationException("unknown show " + key),
            };
        return NormalizeGenerated(output, input);
    });

    // MARK: Panel

    static JsonObject PanelRowJSON(PanelRow r)
    {
        var o = RowJSON(r);
        if (r.FolderID is { } f)
        {
            o["folderID"] = f.ToString().ToUpperInvariant();
            o["childCount"] = r.ChildCount;
        }
        return o;
    }

    /// <summary>Events and snapshots as described in the Swift <c>panelState</c> handler.</summary>
    static JsonNode? PanelStateOp(JsonNode? input) => WithGerman(() =>
    {
        var script = new EditScript(input!);
        foreach (var op in input!["ops"]?.AsArray() ?? new JsonArray()) script.Run(op!);
        var usage = new Dictionary<string, int>(Text.Canonical);
        foreach (var pair in input["usage"]?.AsArray() ?? new JsonArray()) usage[Str(pair![0])] = Int(pair[1]);
        var selected = IsNumber(input["selectedTab"]) ? Int(input["selectedTab"]) : 0;
        var state = new PanelState(script.Config, script.ItemList(input["installed"]), selected, usage);
        Guid CurrentCategory() => state.Tabs[state.SelectedTab] is PanelTab.Category t ? t.Id : Guid.NewGuid();
        JsonObject Snapshot(string ev, PanelAction? action) => new()
        {
            ["event"] = ev,
            ["action"] = action?.Kind switch
            {
                null => null,
                PanelActionKind.None => "none",
                PanelActionKind.Close => "close",
                _ => "insert " + action.Row!.UsageKey,
            },
            ["tab"] = state.SelectedTab, ["filter"] = state.Filter, ["filterSelected"] = state.IsFilterSelected,
            ["highlighted"] = state.Highlighted, ["page"] = state.Page, ["pageSize"] = state.PageSize,
            ["openFolder"] = state.OpenFolderName,
            ["rows"] = new JsonArray(state.Rows.Select(r => (JsonNode?)PanelRowJSON(r)).ToArray()),
        };
        var start = Snapshot("start", null);
        start["tabs"] = Strings(state.Tabs.Select(t => ((PanelTab.Category)t).Name));
        var steps = new JsonArray { start };
        foreach (var ev in input["events"]!.AsArray())
        {
            var type = Str(ev!["type"]);
            PanelAction? action = null;
            JsonArray? folderRows = null;
            switch (type)
            {
                case "tab": state.SelectTab(Int(ev["index"])); break;
                case "key": action = state.Handle(ParseKey(ev["key"])); break;
                case "text":
                    foreach (var ch in Text.Characters(Str(ev["chars"]))) action = state.Handle(PanelKey.OfCharacter(ch));
                    break;
                case "page": state.Page = Int(ev["page"]); break;
                case "pageSize": state.PageSize = Int(ev["size"]); break;
                case "openFolder": state.OpenFolder(script.Entry(ev["folder"], CurrentCategory())); break;
                case "closeFolder": state.CloseFolder(); break;
                case "folderRows":
                    folderRows = new JsonArray(state.FolderRows(script.Entry(ev["folder"], CurrentCategory()))
                        .Select(r => (JsonNode?)PanelRowJSON(r)).ToArray());
                    break;
                default: throw new InvalidOperationException("unknown panel event " + type);
            }
            var snapshot = Snapshot(type, action);
            if (folderRows != null) snapshot["folderRows"] = folderRows;
            steps.Add(snapshot);
        }
        return NormalizeGenerated(steps, input);
    });

    static (int, int) Pair(JsonNode? v)
    {
        var a = v!.AsArray();
        if (a.Count != 2) throw new InvalidOperationException("expected two numbers");
        return (Int(a[0]), Int(a[1]));
    }

    static JsonObject SizeJSON(int columns, int rows, int pageSize) => new() { ["columns"] = columns, ["rows"] = rows, ["pageSize"] = pageSize };

    static JsonObject PageJSON(PanelPage p) => new() { ["columns"] = p.Columns, ["rows"] = p.Rows, ["columnMajor"] = p.ColumnMajor, ["size"] = p.Size };

    static JsonObject PanelSizeJSON(PanelSize s) => new() { ["columnWidth"] = s.ColumnWidth, ["itemHeight"] = s.ItemHeight };

    /// <summary>Input forms as described in the Swift <c>panelGrid</c> handler.</summary>
    static JsonNode? PanelGridOp(JsonNode? input)
    {
        if (input!["order"] is JsonArray order)
            return new JsonArray(PanelGrid.Order(Int(order[0]), Int(order[1]), Int(order[2])).Select(i => (JsonNode?)i).ToArray());
        if (input["size"] is JsonArray size)
            return PanelSizeJSON(new PanelSize(size[0]!.GetValue<double>(), size[1]!.GetValue<double>()));
        if (input["grid"] is JsonArray)
        {
            var (c, r) = Pair(input["grid"]);
            var g = new PanelGridSize(c, r);
            if (input["set"]?["columns"] is JsonNode sc) g.Columns = Int(sc);
            if (input["set"]?["rows"] is JsonNode sr) g.Rows = Int(sr);
            return SizeJSON(g.Columns, g.Rows, g.PageSize);
        }
        if (input["list"] is JsonArray)
        {
            var (c, r) = Pair(input["list"]);
            var l = new PanelListSize(c, r);
            if (input["set"]?["columns"] is JsonNode sc) l.Columns = Int(sc);
            if (input["set"]?["rows"] is JsonNode sr) l.Rows = Int(sr);
            return SizeJSON(l.Columns, l.Rows, l.PageSize);
        }
        if (input["page"] is JsonObject p)
        {
            PanelPage page;
            if (p["style"] is JsonNode style)
            {
                var (gc, gr) = Pair(p["grid"]);
                var (lc, lr) = Pair(p["list"]);
                page = new PanelPage(Decode<PanelStyle>(style), new PanelGridSize(gc, gr), new PanelListSize(lc, lr));
            }
            else page = new PanelPage(Int(p["columns"]), Int(p["rows"]), IsTrue(p["columnMajor"]));
            var o = PageJSON(page);
            o["slots"] = new JsonArray((input["slots"] as JsonArray ?? new JsonArray()).Select(rc =>
            {
                var (r, c) = Pair(rc);
                return (JsonNode?)page.Slot(r, c);
            }).ToArray());
            o["positions"] = new JsonArray((input["positions"] as JsonArray ?? new JsonArray()).Select(s =>
            {
                var (row, column) = page.Position(Int(s));
                return (JsonNode?)new JsonArray(row, column);
            }).ToArray());
            return o;
        }
        var config = Decode<LauncherConfig>(input["config"]);
        return new JsonObject
        {
            ["panelPage"] = PageJSON(config.PanelPage),
            ["panelGrid"] = SizeJSON(config.PanelGrid.Columns, config.PanelGrid.Rows, config.PanelGrid.PageSize),
            ["panelList"] = SizeJSON(config.PanelList.Columns, config.PanelList.Rows, config.PanelList.PageSize),
            ["panelStyle"] = SwiftJson.RawValue(config.PanelStyle), ["categoryPlacement"] = SwiftJson.RawValue(config.CategoryPlacement),
            ["panelSize"] = PanelSizeJSON(config.PanelSize),
        };
    }

    /// <summary><c>{installed, probes}</c> (probes are items, turned into entries) → <c>[{linear, index}]</c> resolved uris.</summary>
    static JsonNode? EntryResolve(JsonNode? input)
    {
        var installed = input!["installed"]!.AsArray().Select(FixtureItem).ToList();
        var index = new EntryResolver.Index(installed);
        return new JsonArray(input["probes"]!.AsArray().Select(p =>
        {
            var e = new Entry(FixtureItem(p));
            return (JsonNode?)new JsonObject { ["linear"] = EntryResolver.Resolve(e, installed)?.Uri, ["index"] = index.Resolve(e)?.Uri };
        }).ToArray());
    }
}
