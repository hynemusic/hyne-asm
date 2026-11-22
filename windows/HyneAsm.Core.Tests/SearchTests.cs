using System.Diagnostics;
using System.Globalization;
using System.Text.Json.Nodes;
using Xunit.Abstractions;

namespace HyneAsm.Core.Tests;

public class SearchTests
{
    readonly ITestOutputHelper output;

    public SearchTests(ITestOutputHelper output) { this.output = output; }

    /// <summary>Review Focus 5: lowercasing and sorting must not follow the PC's culture (Turkish dotted/dotless i).</summary>
    [Fact]
    public void Quick_search_is_culture_independent()
    {
        var cases = Fixtures.All().Where(c => c.Area == "search.quick").ToList();
        Assert.NotEmpty(cases);
        var (culture, ui) = (CultureInfo.CurrentCulture, CultureInfo.CurrentUICulture);
        try
        {
            CultureInfo.CurrentCulture = CultureInfo.CurrentUICulture = new CultureInfo("tr-TR");
            Assert.Equal("ı", "I".ToLower());   // the culture really is in effect
            foreach (var c in cases)
            {
                var actual = Fixtures.SearchQuick(c.Input);
                Assert.True(JsonNode.DeepEquals(actual, c.Expected), $"{c.CaseName} differs under tr-TR");
            }
        }
        finally
        {
            CultureInfo.CurrentCulture = culture;
            CultureInfo.CurrentUICulture = ui;
        }
    }

    static List<PluginItem> Library(int count, string tag) => Enumerable.Range(0, count).Select(i => new PluginItem(
        $"u:{tag}{i}", $"{tag} Plugin {i / 3} {new[] { "Comp", "EQ", "Verb", "Delay" }[i % 4]}", ItemSource.Plugins,
        new[] { new[] { "VST3", "AUv2", "VST" }[i % 3], $"Vendor{i % 60}" })).ToList();

    /// <summary>Swift: building the index takes 50–130 ms for ~3,500 items. Timing only means something in an optimized
    /// build, so this guard runs in Release (<c>dotnet test -c Release</c>) and is skipped in Debug.</summary>
#if DEBUG
    [Fact(Skip = "Performance guard: runs in Release only (dotnet test -c Release)")]
#else
    [Fact]
#endif
    [Trait("Category", "Performance")]
    public void Search_index_builds_3500_items_under_200ms()
    {
        var config = LauncherConfig.MakeDefault();
        _ = new SearchIndex(Library(3500, "Warmup"), config);   // JIT; different names, so the icon cache stays cold
        var items = Library(3500, "Real");
        var watch = Stopwatch.StartNew();
        var index = new SearchIndex(items, config);
        watch.Stop();
        output.WriteLine($"SearchIndex for {items.Count} items: {watch.ElapsedMilliseconds} ms, {index.GlobalRows.Count} rows");
        Assert.True(watch.ElapsedMilliseconds < 200, $"took {watch.ElapsedMilliseconds} ms");
    }
}
