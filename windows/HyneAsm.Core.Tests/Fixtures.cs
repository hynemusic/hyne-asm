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
    };

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
