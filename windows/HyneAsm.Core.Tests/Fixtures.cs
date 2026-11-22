using System.Text.Json.Nodes;

namespace HyneAsm.Core.Tests;

public static class Fixtures
{
    /// <summary>One handler per fixture area. Later tasks add entries here.</summary>
    public static readonly Dictionary<string, Func<JsonNode?, JsonNode?>> Handlers = new()
    {
        ["smoke.echo"] = input => input?.DeepClone(),
    };

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
