using System.Text.Json.Nodes;

namespace HyneAsm.Core.Tests;

[Collection(LocCollection.Name)]
public class SharedFixtureTests
{
    public static IEnumerable<object[]> Cases() =>
        Fixtures.All().Select(c => new object[] { c.File, c.Area, c.CaseName });

    [Theory, MemberData(nameof(Cases))]
    public void Case_matches_expected(string file, string area, string name)
    {
        var c = Fixtures.All().Single(x => x.File == file && x.Area == area && x.CaseName == name);
        var actual = Fixtures.Handlers[area](c.Input);
        Assert.True(JsonNode.DeepEquals(actual, c.Expected),
            $"{file} / {area} / {name}\nexpected: {c.Expected?.ToJsonString() ?? "null"}\nactual:   {actual?.ToJsonString() ?? "null"}");
    }

    [Fact]
    public void Every_fixture_area_has_a_handler()
    {
        var missing = Fixtures.All().Select(c => c.Area).Distinct()
            .Where(a => !Fixtures.Handlers.ContainsKey(a)).ToList();
        Assert.True(missing.Count == 0, "Fixture areas without a C# handler: " + string.Join(", ", missing));
    }

    [Fact]
    public void Case_names_are_unique_per_area()
    {
        var dupes = Fixtures.All().GroupBy(c => (c.Area, c.CaseName)).Where(g => g.Count() > 1)
            .Select(g => $"{g.Key.Area}/{g.Key.CaseName}").ToList();
        Assert.True(dupes.Count == 0, "Duplicate case names: " + string.Join(", ", dupes));
    }
}
