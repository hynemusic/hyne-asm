using System.Diagnostics;
using System.Text.Json.Nodes;

namespace HyneAsm.Core.Tests;

/// <summary>Mirrors BridgeClientTests.swift (and PluginCatalogTests.swift for the catalog on a real client) against an
/// in-process <see cref="FakeBridgeServer"/>. Timeouts are injected short; the defaults are asserted separately.</summary>
public sealed class BridgeClientTests : IAsyncLifetime
{
    FakeBridgeServer server = new();
    BridgeClient client = null!;

    public async Task InitializeAsync()
    {
        server.Start();
        client = new BridgeClient(port: server.Port, requestTimeout: TimeSpan.FromSeconds(1), reconnectInterval: TimeSpan.FromSeconds(0.3));
        client.Start();
        Assert.True(await FakeBridgeServer.WaitUntil(() => client.IsConnected));
    }

    public Task DisposeAsync()
    {
        client.Stop();
        server.Stop();
        return Task.CompletedTask;
    }

    static JsonObject Item(string uri, string name, string source, params string[] path) =>
        new() { ["uri"] = uri, ["name"] = name, ["source"] = source, ["path"] = new JsonArray(path.Select(p => (JsonNode?)p).ToArray()) };

    [Fact]
    public void Defaults_are_3s_request_30s_load_2s_reconnect()
    {
        var c = new BridgeClient();
        Assert.Equal("127.0.0.1", c.Host);
        Assert.Equal(47820, c.Port);
        Assert.Equal(TimeSpan.FromSeconds(3), c.RequestTimeout);
        Assert.Equal(TimeSpan.FromSeconds(30), c.LoadTimeout);
        Assert.Equal(TimeSpan.FromSeconds(2), c.ReconnectInterval);
    }

    [Fact]
    public async Task Hello_decodes_versions()
    {
        server.Respond = r => FakeBridgeServer.Ok(r, new JsonObject { ["script_version"] = "1", ["live_version"] = "12.4.16" });
        var hello = await client.Hello();
        Assert.Equal("1", hello.ScriptVersion);
        Assert.Equal("12.4.16", hello.LiveVersion);
    }

    [Fact]
    public async Task Load_success()
    {
        JsonObject? seen = null;
        server.Respond = r => { seen = r; return FakeBridgeServer.Ok(r); };
        await client.Load("query:AudioFx#EQ%20Eight");
        Assert.Equal("load", (string?)seen!["cmd"]);
        Assert.Equal("query:AudioFx#EQ%20Eight", (string?)seen["uri"]);
    }

    [Fact]
    public async Task Load_chain_with_options()
    {
        JsonObject? seen = null;
        server.Respond = r => { seen = r; return FakeBridgeServer.Ok(r); };
        await client.Load(new[] { "u:a", "u:b" }, new InsertOptions(InsertPosition.AfterSelected, allSelectedTracks: true));
        Assert.Equal(new[] { "u:a", "u:b" }, seen!["uris"]!.AsArray().Select(n => (string?)n));
        Assert.Equal("after_selected", (string?)seen["position"]);
        Assert.True((bool)seen["all_selected"]!);
    }

    /// <summary>Version-3 scripts only read "uri": every load must still carry it.</summary>
    [Fact]
    public async Task Load_always_carries_first_uri_for_older_scripts()
    {
        JsonObject? seen = null;
        server.Respond = r => { seen = r; return FakeBridgeServer.Ok(r); };
        await client.Load(new[] { "u:a", "u:b" }, InsertOptions.Default);
        Assert.Equal("u:a", (string?)seen!["uri"]);
    }

    [Fact]
    public async Task Runs_live_action()
    {
        JsonObject? seen = null;
        server.Respond = r => { seen = r; return FakeBridgeServer.Ok(r); };
        await client.Run(new LiveAction(LiveActionKind.SetTempo, 128));
        Assert.Equal("action", (string?)seen!["cmd"]);
        Assert.Equal("set_tempo", (string?)seen["name"]);
        Assert.Equal(128, (double)seen["value"]!);
    }

    [Fact]
    public async Task Hello_reads_capabilities_and_older_bridges_without()
    {
        server.Respond = r => FakeBridgeServer.Ok(r, new JsonObject
        {
            ["script_version"] = "4", ["live_version"] = "12.4.16",
            ["capabilities"] = new JsonObject { ["move_device"] = true, ["multi_select"] = false },
        });
        Assert.Equal(new BridgeCapabilities(moveDevice: true, multiSelect: false), (await client.Hello()).Capabilities);
        server.Respond = r => FakeBridgeServer.Ok(r, new JsonObject { ["script_version"] = "3", ["live_version"] = "12.4.16" });
        Assert.Equal(new BridgeCapabilities(moveDevice: false, multiSelect: false), (await client.Hello()).Capabilities);
    }

    [Fact]
    public async Task Load_remote_error_throws_remote()
    {
        server.Respond = r => new JsonObject { ["id"] = r["id"]!.DeepClone(), ["ok"] = false, ["result"] = null, ["error"] = "not_found" };
        var e = await Assert.ThrowsAsync<BridgeError>(() => client.Load("x"));
        Assert.Equal(BridgeErrorKind.Remote, e.Kind);
        Assert.Equal("not_found", e.Remote);
    }

    [Fact]
    public async Task Request_while_disconnected_throws_not_connected()
    {
        using var lonely = new BridgeClient(port: 1, requestTimeout: TimeSpan.FromSeconds(5));
        var watch = Stopwatch.StartNew();
        var e = await Assert.ThrowsAsync<BridgeError>(() => lonely.Hello());
        Assert.Equal(BridgeErrorKind.NotConnected, e.Kind);
        Assert.True(watch.Elapsed < TimeSpan.FromSeconds(0.5));
    }

    /// <summary>A load waits for the load timeout (default 30 s), not the request timeout: here 0.5 s vs 3 s, reply after 1.2 s.</summary>
    [Fact]
    public async Task Load_uses_30s_timeout()
    {
        Assert.Equal(TimeSpan.FromSeconds(30), new BridgeClient().LoadTimeout);
        using var slow = new BridgeClient(port: server.Port, requestTimeout: TimeSpan.FromSeconds(0.5), loadTimeout: TimeSpan.FromSeconds(3));
        slow.Start();
        Assert.True(await FakeBridgeServer.WaitUntil(() => slow.IsConnected));
        server.ReplyDelay = TimeSpan.FromSeconds(1.2);
        server.Respond = r => FakeBridgeServer.Ok(r);
        await slow.Load("query:M4L#Heavy");
    }

    /// <summary>A silent bridge fails the request after the request timeout (default 3 s; 1 s here).</summary>
    [Fact]
    public async Task Request_times_out_after_3s()
    {
        Assert.Equal(TimeSpan.FromSeconds(3), new BridgeClient().RequestTimeout);
        server.Respond = _ => null;
        var watch = Stopwatch.StartNew();
        var e = await Assert.ThrowsAsync<BridgeError>(() => client.Hello());
        Assert.Equal(BridgeErrorKind.Timeout, e.Kind);
        Assert.InRange(watch.Elapsed.TotalSeconds, 0.9, 2.5);
    }

    [Fact]
    public async Task Reads_large_response_split_across_chunks()
    {
        server.ChunkSize = 1024;
        var items = new JsonArray(Enumerable.Range(0, 3000)
            .Select(i => (JsonNode?)Item($"u:{i}", $"Plugin {i}", "plugins", "VST3", "Vendor")).ToArray());
        server.Respond = r => FakeBridgeServer.Ok(r, new JsonObject { ["items"] = items.DeepClone() });
        var result = await client.ListItems();
        Assert.Equal(3000, result.Count);
        Assert.Equal(new PluginItem("u:2999", "Plugin 2999", ItemSource.Plugins, new List<string> { "VST3", "Vendor" }), result[2999]);
    }

    [Fact]
    public async Task Unknown_items_are_skipped()
    {
        var glue = Item("u:glue", "My Glue", "user_library", "Presets");
        glue["format"] = "adg";
        var items = new JsonArray(glue, Item("u:new", "Future", "some_new_root"), Item("u:eq", "EQ Eight", "audio_effects"));
        server.Respond = r => FakeBridgeServer.Ok(r, new JsonObject { ["items"] = items.DeepClone() });
        var result = await client.ListItems();
        Assert.Equal(new[] { "My Glue", "EQ Eight" }, result.Select(i => i.Name));
        Assert.Equal("adg", result[0].Format);
        Assert.Equal(ItemSource.UserLibrary, result[0].Source);
        Assert.Null(result[1].Format);
    }

    [Fact]
    public async Task Responses_matched_by_id()
    {
        server.ReverseOrder = true;
        server.Respond = r => (string?)r["cmd"] == "hello"
            ? FakeBridgeServer.Ok(r, new JsonObject { ["script_version"] = "1", ["live_version"] = "12" })
            : FakeBridgeServer.Ok(r, new JsonObject { ["items"] = new JsonArray() });
        var hello = client.Hello();
        var items = client.ListItems();
        Assert.Equal("12", (await hello).LiveVersion);
        Assert.Empty(await items);
    }

    [Fact]
    public async Task Reconnects_after_server_restart()
    {
        var states = new List<bool>();
        client.SetConnectionHandler(v => { lock (states) states.Add(v); });
        var port = server.Port;
        server.Stop();
        Assert.True(await FakeBridgeServer.WaitUntil(() => !client.IsConnected));
        server = new FakeBridgeServer();
        server.Start(port);
        Assert.True(await FakeBridgeServer.WaitUntil(() => client.IsConnected, 1.3));
        lock (states) Assert.Equal(new[] { false, true }, states.Take(2));
    }

    [Fact]
    public async Task Pending_requests_fail_not_connected_when_the_bridge_goes_away()
    {
        server.Respond = _ => null;
        var hello = client.Hello();
        await Task.Delay(100);
        server.Stop();
        var e = await Assert.ThrowsAsync<BridgeError>(() => hello);
        Assert.Equal(BridgeErrorKind.NotConnected, e.Kind);
    }

    [Fact]
    public async Task Catalog_refresh_through_the_client_writes_cache_and_load_cache_restores()
    {
        server.Respond = r => FakeBridgeServer.Ok(r, new JsonObject { ["items"] = new JsonArray(Item("u:eq", "EQ Eight", "audio_effects")) });
        var cache = Path.Combine(Path.GetTempPath(), "hyneasm-test-" + Guid.NewGuid().ToString("N"), "catalog-cache.json");
        var catalog = new PluginCatalog(cache, client);
        await catalog.Refresh();
        Assert.Equal(new[] { "EQ Eight" }, catalog.Items.Select(i => i.Name));
        var restored = new PluginCatalog(cache, client);
        restored.LoadCache();
        Assert.Equal(catalog.Items, restored.Items);
        Directory.Delete(Path.GetDirectoryName(cache)!, recursive: true);
    }

    [Fact]
    public async Task Catalog_refresh_failure_keeps_items()
    {
        var dir = Path.Combine(Path.GetTempPath(), "hyneasm-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var cache = Path.Combine(dir, "catalog-cache.json");
        var items = new List<PluginItem> { new("u:1", "Utility", ItemSource.AudioEffects, new List<string>()) };
        File.WriteAllText(cache, Json.SwiftJson.Serialize(items));
        var catalog = new PluginCatalog(cache, new BridgeClient(port: 1));
        catalog.LoadCache();
        await Assert.ThrowsAsync<BridgeError>(() => catalog.Refresh());
        Assert.Equal(items, catalog.Items);
        Directory.Delete(dir, recursive: true);
    }
}

/// <summary>Skipped unless HM_LIVE_TEST=1 (run: <c>HM_LIVE_TEST=1 dotnet test --filter Live</c>).</summary>
public sealed class LiveFactAttribute : FactAttribute
{
    public LiveFactAttribute()
    {
        if (Environment.GetEnvironmentVariable("HM_LIVE_TEST") != "1") Skip = "set HM_LIVE_TEST=1";
    }
}

/// <summary>Mirrors LiveIntegrationTests.swift: needs ASMbridge selected in a running Live.</summary>
public sealed class LiveIntegrationTests
{
    [LiveFact]
    public async Task Hello_and_list_against_running_Live()
    {
        using var client = new BridgeClient(requestTimeout: TimeSpan.FromSeconds(10));
        client.Start();
        Assert.True(await FakeBridgeServer.WaitUntil(() => client.IsConnected, 5));
        var hello = await client.Hello();
        Assert.StartsWith("12.", hello.LiveVersion);
        var items = await client.ListItems();
        Assert.Contains(items, i => i.Name == "EQ Eight" && i.Source == ItemSource.AudioEffects);
        Assert.DoesNotContain(items, i => i.Uri.Contains(":FileId_") && i.Source != ItemSource.MaxForLive);
        Console.WriteLine($"LIVE: {hello.LiveVersion}, {items.Count} items");
    }
}
