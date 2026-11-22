using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using HyneAsm.Core.Json;

namespace HyneAsm.Core.Tests;

/// <summary>Fixture handlers for the LES import, menu files and versions, usage, new &amp; rarely used items and presets —
/// the same input shapes as Tests/HMLauncherCoreTests/SharedFixtureFiles.swift. File handlers go through real files.</summary>
public static partial class Fixtures
{
    static readonly DateTime Epoch = DateTime.UnixEpoch;

    static DateTime Date(JsonNode? n) => Epoch.AddTicks((long)(n!.GetValue<double>() * TimeSpan.TicksPerSecond));

    static double Seconds(DateTime d) => (double)(d - Epoch).Ticks / TimeSpan.TicksPerSecond;

    static JsonArray List(JsonNode? n) => n as JsonArray ?? new JsonArray();

    static Dictionary<string, int> Counts(JsonNode? n)
    {
        var result = new Dictionary<string, int>(Text.Canonical);
        if (n is JsonObject o) foreach (var (k, v) in o) result[k] = Int(v);
        return result;
    }

    static JsonObject CountsJSON(IReadOnlyDictionary<string, int> counts)
    {
        var o = new JsonObject();
        foreach (var (k, v) in counts) o[k] = v;
        return o;
    }

    static JsonValue? Optional(string? s) => s is null ? null : JsonValue.Create(s);

    static string TempDir()
    {
        var dir = Path.Combine(Path.GetTempPath(), "hyneasm-fixture-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    static void RemoveDir(string dir)
    {
        try { Directory.Delete(dir, recursive: true); } catch (IOException) { }
    }

    static void WriteFile(string path, string text) => File.WriteAllBytes(path, Encoding.UTF8.GetBytes(text));

    static string ReadFile(string path) => Encoding.UTF8.GetString(File.ReadAllBytes(path));

    /// <summary><c>{json, text?}</c> or null; the exact text only for files with at most one key (as in Swift).</summary>
    static JsonNode? FileJSON(string path)
    {
        if (!File.Exists(path)) return null;
        var text = ReadFile(path);
        var tree = JsonNode.Parse(text.StartsWith('﻿') ? text[1..] : text);
        var o = new JsonObject { ["json"] = tree };
        if (!(tree is JsonObject d && d.Count > 1)) o["text"] = text;
        return o;
    }

    // MARK: LES import

    static JsonNode? LesParse(JsonNode? input) => WithGerman(() => new JsonArray(LESMenuParser.Parse(Str(input)).Select(c =>
        (JsonNode?)new JsonObject
        {
            ["name"] = c.Name, ["parent"] = c.Parent is int p ? JsonValue.Create(p) : null,
            ["items"] = new JsonArray(c.Items.Select(i => (JsonNode?)new JsonObject { ["display"] = i.Display, ["query"] = i.Query }).ToArray()),
        }).ToArray()));

    static JsonNode? LesQuery(JsonNode? input)
    {
        var q = new LESQuery(Str(input));
        return new JsonObject { ["text"] = q.Text, ["format"] = q.Format is { } f ? CamelName(f) : null, ["isPreset"] = q.IsPreset };
    }

    static JsonObject MatchJSON(LESMatch m) => new()
    {
        ["status"] = CamelName(m.Status), ["item"] = m.Item?.Uri, ["alternatives"] = Strings(m.Alternatives.Select(a => a.Uri)),
        ["isPreset"] = m.IsPreset,
    };

    static JsonObject MenuEntryJSON(Entry e)
    {
        var o = new JsonObject { ["name"] = e.Name, ["title"] = e.Title, ["uri"] = e.Uri, ["iconID"] = e.IconID };
        if (e.DisplayName != null) o["displayName"] = e.DisplayName;
        if (e.Children != null) o["children"] = new JsonArray(e.Children.Select(c => (JsonNode?)MenuEntryJSON(c)).ToArray());
        return o;
    }

    static JsonArray MenuJSON(IEnumerable<Category> categories) => new(categories.Select(c => (JsonNode?)new JsonObject
    {
        ["name"] = c.Name, ["isFavorites"] = c.IsFavorites,
        ["entries"] = new JsonArray(c.Entries.Select(e => (JsonNode?)MenuEntryJSON(e)).ToArray()),
    }).ToArray());

    static JsonObject DraftJSON(ImportDraft d)
    {
        var ids = d.Categories.Select(c => c.Id).ToList();
        var categories = d.Categories.Select(c =>
        {
            JsonNode? parent = null;
            if (c.ParentID is { } p) parent = ids.IndexOf(p) is var i and >= 0 ? JsonValue.Create(i) : JsonValue.Create("missing");
            return (JsonNode?)new JsonObject
            {
                ["name"] = c.Name, ["parent"] = parent,
                ["rows"] = new JsonArray(c.Rows.Select(r => (JsonNode?)new JsonObject
                {
                    ["display"] = r.Display, ["query"] = r.Query, ["match"] = MatchJSON(r.Match),
                }).ToArray()),
            };
        });
        var n = d.Counts;
        return new JsonObject
        {
            ["categories"] = new JsonArray(categories.ToArray()),
            ["counts"] = new JsonObject { ["found"] = n.Found, ["uncertain"] = n.Uncertain, ["notFound"] = n.NotFound },
        };
    }

    static void DraftOp(ImportDraft d, JsonNode op)
    {
        var ids = d.Categories.Select(c => c.Id).ToList();
        Guid Category(string key) => ids[Int(op[key])];
        Guid Row(int c) => d.Categories[c].Rows[Int(op["row"])].Id;
        switch (Str(op["op"]))
        {
            case "removeRow": { var c = Int(op["category"]); d.RemoveRow(Row(c), ids[c]); break; }
            case "moveRow": d.MoveRow(Category("category"), Int(op["from"]), Int(op["to"])); break;
            case "rename": d.RenameCategory(Category("category"), Str(op["name"])); break;
            case "removeCategory": d.RemoveCategory(Category("category")); break;
            case "setParent": d.SetParent(Category("category"), IsNull(op["parent"]) ? null : Category("parent")); break;
            case "moveCategory": d.MoveCategory(Int(op["from"]), Int(op["to"])); break;
            case "merge": d.MergeCategory(Category("source"), Category("target")); break;
            case "setMatch": { var c = Int(op["category"]); d.SetMatch(FixtureItem(op["item"]), Row(c), ids[c]); break; }
            default: throw new InvalidOperationException("les.match: unknown op");
        }
    }

    static JsonNode? LesMatch(JsonNode? input) => WithGerman(() =>
    {
        if (input!["restore"] is JsonArray restore)
        {
            var c = LauncherConfig.MakeDefault();
            c.RestoreMenu(Decode<List<Category>>(restore));
            return MenuJSON(c.Categories);
        }
        var items = List(input["items"]).Select(FixtureItem).ToList();
        if (input["text"] is not JsonValue text)
            return MatchJSON(new LESMatcher(items).Match(Str(input["display"]), Str(input["query"])));
        var draft = ImportDraft.Make(Str(text), items);
        foreach (var op in List(input["ops"])) DraftOp(draft, op!);
        var output = new JsonObject { ["draft"] = DraftJSON(draft) };
        if (input["apply"] is JsonArray applies)
        {
            var c = LauncherConfig.MakeDefault();
            foreach (var s in List(input["setup"]))
            {
                if (s!["category"] is JsonNode name) { c.AddCategory(Str(name)); continue; }
                var target = s["to"] is JsonValue v && v.GetValueKind() == JsonValueKind.String && Str(v) == "favorites"
                    ? c.FavoritesID : c.Categories[Int(s["to"])].Id;
                c.AddEntry(FixtureItem(s["add"]), target);
            }
            foreach (var a in applies) c.Apply(draft, Str(a!["mode"]) == "add" ? ImportMode.Add : ImportMode.Replace);
            output["menu"] = MenuJSON(c.Categories);
        }
        return output;
    });

    // MARK: Menu files and versions

    static JsonObject VersionJSON(MenuVersion v, bool randomID = false)
    {
        var id = v.Id;
        var dash = id.IndexOf('-');
        if (randomID && dash >= 0)
        {
            var suffix = id[(dash + 1)..];
            if (suffix.Length == 8 && suffix.All(ch => char.IsAsciiHexDigit(ch) && !char.IsAsciiLetterLower(ch))) id = id[..(dash + 1)] + "HEX8";
        }
        return new JsonObject
        {
            ["id"] = id, ["name"] = v.Name, ["date"] = Seconds(v.Date), ["isAutomatic"] = v.IsAutomatic,
            ["categoryCount"] = v.CategoryCount, ["entryCount"] = v.EntryCount,
        };
    }

    static JsonNode? FilesMenu(JsonNode? input)
    {
        var dir = TempDir();
        try
        {
            if (input!["text"] is JsonNode text)
            {
                string source = Path.Combine(dir, "in.hmlmenu"), target = Path.Combine(dir, "out.hmlmenu");
                WriteFile(source, Str(text));
                MenuDocument doc;
                try { doc = MenuDocument.Read(source); }
                catch (MenuDocument.NotAMenuFile) { return new JsonObject { ["error"] = "notAMenuFile" }; }
                catch (JsonException) { return new JsonObject { ["error"] = "unreadable" }; }
                doc.Write(target);
                return new JsonObject { ["text"] = ReadFile(target) };
            }
            var store = new MenuVersionStore(Path.Combine(dir, "Versions"));
            if (input["save"] is JsonObject s)
            {
                var v = store.Save(Str(s["name"]), Decode<List<Category>>(s["categories"]), IsTrue(s["isAutomatic"]), Date(s["date"]));
                return new JsonObject
                {
                    ["version"] = VersionJSON(v, randomID: true), ["text"] = ReadFile(Path.Combine(store.Directory, v.Id + ".json")),
                    ["listed"] = new JsonArray(store.List().Select(x => (JsonNode?)VersionJSON(x, randomID: true)).ToArray()),
                };
            }
            var files = input["files"] as JsonObject ?? throw new InvalidOperationException("files.hmlmenu: unknown input");
            Directory.CreateDirectory(store.Directory);
            foreach (var (name, content) in files) WriteFile(Path.Combine(store.Directory, name), Str(content));
            var output = new JsonObject { ["list"] = new JsonArray(store.List().Select(x => (JsonNode?)VersionJSON(x)).ToArray()) };
            if (input["load"] is JsonNode id)
            {
                var target = Path.Combine(dir, "loaded.hmlmenu");
                store.Load(Str(id)).Write(target);
                output["loaded"] = ReadFile(target);
            }
            return output;
        }
        finally { RemoveDir(dir); }
    }

    // MARK: Usage

    static JsonNode? FilesUsage(JsonNode? input)
    {
        if (input!["read"] is JsonNode read)
        {
            try { return new JsonObject { ["counts"] = CountsJSON(UsageExport.Read(Encoding.UTF8.GetBytes(Str(read)))) }; }
            catch (UsageExport.NotUsageFile) { return new JsonObject { ["error"] = true }; }
        }
        if (input["write"] is JsonObject w)
            return new JsonObject { ["text"] = Encoding.UTF8.GetString(new UsageExport(Counts(w["counts"]), Date(w["exported"])).Data()) };
        var s = input["store"] as JsonObject ?? throw new InvalidOperationException("files.hmlusage: unknown input");
        var dir = TempDir();
        try
        {
            var path = Path.Combine(dir, "usage.json");
            if (s["initial"] is JsonNode initial) WriteFile(path, Str(initial));
            var store = new UsageStore(path);
            foreach (var op in List(s["ops"]))
            {
                switch (Str(op!["op"]))
                {
                    case "record": store.Record(Str(op["key"])); break;
                    case "merge": store.Merge(Counts(op["counts"])); break;
                    case "replaceAll": store.ReplaceAll(Counts(op["counts"])); break;
                    case "reset": store.Reset(); break;
                    case "remove": store.Remove(Str(op["key"])); break;
                    default: throw new InvalidOperationException("files.hmlusage: unknown op");
                }
            }
            return new JsonObject
            {
                ["counts"] = CountsJSON(store.Counts), ["reloaded"] = CountsJSON(new UsageStore(path).Counts), ["file"] = FileJSON(path),
            };
        }
        finally { RemoveDir(dir); }
    }

    static JsonNode? FilesSeen(JsonNode? input)
    {
        var dir = TempDir();
        try
        {
            var path = Path.Combine(dir, "seen.json");
            if (input!["initial"] is JsonNode initial) WriteFile(path, Str(initial));
            var store = new SeenStore(path);
            foreach (var u in List(input["updates"])) store.Update(List(u!["items"]).Select(FixtureItem).ToList(), Date(u["now"]));
            var probe = input["probe"];
            var config = LauncherConfig.MakeDefault();
            foreach (var f in List(probe?["file"])) config.AddEntry(FixtureItem(f), config.FavoritesID);
            var items = List(probe?["items"]).Select(FixtureItem).ToList();
            var usage = Counts(probe?["usage"]);
            var now = Date(probe?["now"]);
            JsonArray NewURIs(SeenStore seen) => Strings(NewItems.Uris(items, seen, config, usage, now).Order(Comparer<string>.Create(Text.CompareScalars)));
            return new JsonObject { ["file"] = FileJSON(path), ["new"] = NewURIs(store), ["newAfterReload"] = NewURIs(new SeenStore(path)) };
        }
        finally { RemoveDir(dir); }
    }

    static JsonNode? UsageSummaryOp(JsonNode? input) => WithGerman(() =>
    {
        if (input!["readableName"] is JsonArray keys) return Strings(keys.Select(k => UsageStats.ReadableName(Str(k))));
        if (input["rare"] is JsonObject r)
        {
            var config = Decode<LauncherConfig>(r["config"]);
            foreach (var k in StrList(r["keep"])) config.KeepEntry(Guid.Parse(k));
            var index = new SearchIndex(Decode<List<PluginItem>>(r["items"]), config);
            var threshold = IsNull(r["threshold"]) ? 1 : Int(r["threshold"]);
            var rare = RarelyUsed.Entries(config, index, Counts(r["usage"]), threshold);
            return new JsonObject
            {
                ["rare"] = new JsonArray(rare.Select(e => (JsonNode?)new JsonObject
                {
                    ["title"] = e.Entry.Title, ["place"] = e.Place, ["count"] = e.Count,
                    ["category"] = config.Categories.FindIndex(c => c.Id == e.CategoryID),
                }).ToArray()),
                ["kept"] = Strings(config.KeptEntries.Select(g => g.ToString("D").ToUpperInvariant())),
            };
        }
        var items = Decode<List<PluginItem>>(input["items"]);
        var cfg = input["config"] is JsonObject c ? Decode<LauncherConfig>(c) : LauncherConfig.MakeDefault();
        var s = UsageStats.Summarize(Counts(input["counts"]), items, cfg);
        return new JsonObject
        {
            ["stats"] = new JsonArray(s.Stats.Select(st => (JsonNode?)new JsonObject
            {
                ["key"] = st.Key, ["name"] = st.Name, ["kind"] = SwiftJson.RawValue(st.Kind), ["count"] = st.Count, ["share"] = st.Share,
                ["iconID"] = st.IconID, ["colorID"] = st.ColorID, ["isAvailable"] = st.IsAvailable,
            }).ToArray()),
            ["total"] = s.Total,
            ["byKind"] = new JsonArray(s.ByKind.Select(k => (JsonNode?)new JsonObject
            {
                ["kind"] = SwiftJson.RawValue(k.Kind), ["count"] = k.Count, ["title"] = k.Kind.Title(),
            }).ToArray()),
            ["topShare"] = new JsonArray(new[] { 1, 2, 3 }.Select(n => (JsonNode?)JsonValue.Create(s.TopShare(n))).ToArray()),
        };
    });

    // MARK: Presets

    static JsonNode? PresetsMatch(JsonNode? input)
    {
        switch (Str(input!["op"]))
        {
            case "match":
                return Optional(PresetImport.Match(Str(input["file"]), Decode<List<PluginItem>>(input["items"]), Str(input["library"]))?.Uri);
            case "isInside":
                var folder = Str(input["folder"]);
                return new JsonArray(StrList(input["files"]).Select(f => (JsonNode?)JsonValue.Create(PresetImport.IsInside(f, folder))).ToArray());
            case "isPresetFile":
                return new JsonArray(StrList(input["files"]).Select(f => (JsonNode?)JsonValue.Create(PresetFormat.IsPresetFile(f))).ToArray());
            case "describe":
                return new JsonArray(Decode<List<PluginItem>>(input["items"]).Select(i => (JsonNode?)new JsonObject
                {
                    ["label"] = PresetFormat.Label(i), ["group"] = PresetFormat.GroupTitle(i), ["fallbackIcon"] = PresetFormat.FallbackIcon(i),
                }).ToArray());
            case "copyDestination":
                var library = TempDir();
                try
                {
                    var target = Path.Combine(library, "Presets", "HYNE ASM");
                    Directory.CreateDirectory(target);
                    foreach (var name in StrList(input["existing"])) File.WriteAllBytes(Path.Combine(target, name), Array.Empty<byte>());
                    var dest = PresetImport.CopyDestination(Str(input["file"]), library);
                    var parent = new DirectoryInfo(Path.GetDirectoryName(dest)!);
                    return new JsonObject { ["name"] = Path.GetFileName(dest), ["folder"] = Strings(new[] { parent.Parent!.Name, parent.Name }) };
                }
                finally { RemoveDir(library); }
            default:
                throw new InvalidOperationException("presets.match: unknown op");
        }
    }
}
