namespace HyneAsm.Core.Tests;

/// <summary>Every Swift core file has a C# file with the same name, unless windows/core-exceptions.txt lists it with a reason.</summary>
public class CoverageTests
{
    [Fact]
    public void Every_swift_core_file_has_a_csharp_counterpart()
    {
        var root = Fixtures.RepoRoot();
        var swift = Names(Path.Combine(root, "Sources", "HMLauncherCore"), "*.swift");
        var csharp = Names(Path.Combine(root, "windows", "HyneAsm.Core"), "*.cs");
        var exceptions = File.ReadLines(Path.Combine(root, "windows", "core-exceptions.txt"))
            .Select(line => line.Trim())
            .Where(line => line.Length > 0 && !line.StartsWith('#'))
            .ToHashSet();

        var missing = swift.Where(name => !csharp.Contains(name) && !exceptions.Contains(name))
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToList();

        Assert.True(missing.Count == 0,
            "Swift core files with no C# counterpart in windows/HyneAsm.Core (add the .cs file, or list the name in windows/core-exceptions.txt with a reason):\n"
            + string.Join("\n", missing.Select(name => "  " + name + ".swift")));
    }

    static HashSet<string> Names(string dir, string pattern) =>
        Directory.GetFiles(dir, pattern).Select(path => Path.GetFileNameWithoutExtension(path)).ToHashSet();
}
