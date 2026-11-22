namespace HyneAsm.Core.Tests;

/// <summary>Mirrors the parts of RemoteCommandTests.swift / RemoteRequestTests.swift not covered by the remote.* fixtures.</summary>
public class RemoteCommandTests
{
    static PluginItem Item(string name, string uri) => new(uri, name, ItemSource.Plugins, new List<string>());

    [Fact]
    public void Resolves_names_entries_first_then_plugins()
    {
        var serum = Item("Serum 2", "s");
        var c = LauncherConfig.MakeDefault();
        c.Categories[0].Entries = new List<Entry> { Entry.ChainNamed("Vocal Basic", new List<PluginItem> { serum }) };
        var index = new SearchIndex(new List<PluginItem> { serum, Item("Serum FX", "fx") }, c);
        Assert.Equal(new[] { "s" }, RemoteTarget.Row("vocal basic", c, index)?.Chain);
        Assert.Equal("s", RemoteTarget.Row("Serum 2", c, index)?.Uri);
        Assert.Equal("fx", RemoteTarget.Row("serum fx", c, index)?.Uri);
        Assert.Null(RemoteTarget.Row("Nothing Like This", c, index));
    }

    [Fact]
    public void Config_has_a_stable_token_and_old_configs_get_one()
    {
        var c = LauncherConfig.MakeDefault();
        Assert.Matches("^[0-9a-f]{20}$", c.StreamDeckToken);
        Assert.False(c.StreamDeckEnabled);
        Assert.Equal(c.StreamDeckToken, Json.SwiftJson.Clone(c).StreamDeckToken);
        var old = Json.SwiftJson.Deserialize<LauncherConfig>("{\"version\": 4, \"categories\": []}");
        Assert.Matches("^[0-9a-f]{20}$", old.StreamDeckToken);
    }

    [Fact]
    public void Links_parse_from_a_Uri_and_keep_their_exact_text()
    {
        var link = RemoteCommand.Insert("Vocal Basic").Link(http: true, token: "abc123");
        Assert.Equal("http://127.0.0.1:47821/insert?name=Vocal%20Basic&token=abc123", link.OriginalString);
        Assert.Equal(RemoteCommand.Insert("Vocal Basic"), RemoteCommand.TryParse(link));
        Assert.Equal(RemoteRequest.Outcome.Run(RemoteCommand.Insert("Vocal Basic")),
            RemoteRequest.Handle($"GET {link.PathAndQuery} HTTP/1.1\r\n\r\n", "abc123"));
    }
}
